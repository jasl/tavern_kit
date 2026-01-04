# frozen_string_literal: true

require "test_helper"

module TavernKit
  module STCompatibility
    # Tests for SillyTavern World Info insertion positions.
    #
    # ST World Info positions:
    # - before_char_defs (position 0)
    # - after_char_defs (position 1)
    # - top_of_an (position 2)
    # - bottom_of_an (position 3)
    # - at_depth (position 4) with role override
    # - before_example_messages (position 5)
    # - after_example_messages (position 6)
    # - outlet (position 7) for {{outlet::name}} macro
    class TestWorldInfoPositions < Minitest::Test
      def setup
        @user = User.new(name: "Bob", persona: nil)
      end

      def build_card_with_entries(entries)
        CharacterCard.load(
          {
            "spec" => "chara_card_v2",
            "spec_version" => "2.0",
            "data" => {
              "name" => "Alice",
              "description" => "A wise guide",
              "personality" => "Calm",
              "scenario" => "Forest",
              "system_prompt" => nil,
              "post_history_instructions" => nil,
              "first_mes" => "",
              "mes_example" => <<~EX,
                <START>
                {{user}}: Hi
                {{char}}: Hello!
              EX
              "character_book" => {
                "scan_depth" => 10,
                "token_budget" => 1000,
                "entries" => entries,
              },
            },
          }
        )
      end

      # Test: before_char_defs position
      def test_before_char_defs_position
        card = build_card_with_entries([
          { "uid" => "wi1", "keys" => ["magic"], "content" => "BEFORE_CHAR", "position" => "before_char_defs" },
        ])

        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "")
        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "magic")

        blocks = plan.blocks
        slots = blocks.map(&:slot)

        wi_idx = slots.index(:world_info_before_char_defs)
        char_idx = slots.index(:character_description)

        refute_nil wi_idx, "World Info before_char should be present"
        refute_nil char_idx, "Character block should be present"
        assert wi_idx < char_idx, "before_char_defs should come before character"
      end

      # Test: after_char_defs position
      def test_after_char_defs_position
        card = build_card_with_entries([
          { "uid" => "wi1", "keys" => ["magic"], "content" => "AFTER_CHAR", "position" => "after_char_defs" },
        ])

        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "", new_example_chat: "[EX]")
        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "magic")

        blocks = plan.blocks
        slots = blocks.map(&:slot)

        wi_idx = slots.index(:world_info_after_char_defs)
        char_idx = slots.rindex { |s| [:character_description, :character_personality, :scenario].include?(s) }
        examples_idx = slots.index(:new_example_chat) || slots.index(:examples)

        refute_nil wi_idx, "World Info after_char should be present"
        assert wi_idx > char_idx, "after_char_defs should come after character"
        assert wi_idx < examples_idx, "after_char_defs should come before examples" if examples_idx
      end

      # Test: top_of_an and bottom_of_an positions
      def test_an_positions
        card = build_card_with_entries([
          { "uid" => "top", "keys" => ["magic"], "content" => "TOP_AN", "position" => "top_of_an" },
          { "uid" => "bottom", "keys" => ["magic"], "content" => "BOTTOM_AN", "position" => "bottom_of_an" },
        ])

        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "", authors_note: "AN_CONTENT")
        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "magic")

        an_block = plan.blocks.find { |b| b.slot == :authors_note }
        refute_nil an_block, "authors_note should be present"

        # When AN is inserted in-chat (ST default), top/bottom-of-AN World Info is merged into the AN block.
        top_idx = an_block.content.index("TOP_AN")
        an_idx = an_block.content.index("AN_CONTENT")
        bottom_idx = an_block.content.index("BOTTOM_AN")

        refute_nil top_idx, "top_of_an WI content should be present inside AN"
        refute_nil an_idx, "authors_note content should be present"
        refute_nil bottom_idx, "bottom_of_an WI content should be present inside AN"

        assert top_idx < an_idx, "TOP_AN should come before AN_CONTENT"
        assert an_idx < bottom_idx, "BOTTOM_AN should come after AN_CONTENT"
      end

      # Test: before_example_messages and after_example_messages positions
      def test_example_message_positions
        card = build_card_with_entries([
          { "uid" => "before", "keys" => ["magic"], "content" => "{{user}}: Before\n{{char}}: Before reply", "position" => "before_example_messages" },
          { "uid" => "after", "keys" => ["magic"], "content" => "{{user}}: After\n{{char}}: After reply", "position" => "after_example_messages" },
        ])

        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "", new_example_chat: "[EX]")
        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "magic")

        messages = plan.to_messages
        contents = messages.map { |m| m[:content] }

        # Find the example messages
        before_idx = contents.index { |c| c.include?("Before reply") }
        card_example_idx = contents.index { |c| c.include?("Hello!") } # From card's mes_example
        after_idx = contents.index { |c| c.include?("After reply") }

        refute_nil before_idx, "before_example_messages content should be present"
        refute_nil card_example_idx, "Card example should be present"
        refute_nil after_idx, "after_example_messages content should be present"

        assert before_idx < card_example_idx, "before_example should come before card examples"
        assert card_example_idx < after_idx, "after_example should come after card examples"
      end

      # Test: at_depth position with role override
      def test_at_depth_with_role_override
        card = build_card_with_entries([
          { "uid" => "depth0_sys", "keys" => ["magic"], "content" => "DEPTH0_SYSTEM", "position" => "at_depth", "depth" => 0, "role" => "system" },
          { "uid" => "depth0_user", "keys" => ["magic"], "content" => "DEPTH0_USER", "position" => "at_depth", "depth" => 0, "role" => "user" },
        ])

        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "")
        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "magic")

        messages = plan.to_messages

        # Find at_depth messages
        sys_msg = messages.find { |m| m[:content].include?("DEPTH0_SYSTEM") }
        user_msg = messages.find { |m| m[:content].include?("DEPTH0_USER") }

        refute_nil sys_msg
        refute_nil user_msg

        # Due to merging, they should be separate messages with correct roles
        # Actually, they have different roles so they won't be merged
        assert_equal "system", sys_msg[:role]
        assert_equal "user", user_msg[:role]
      end

      # Test: at_depth with various depths
      def test_at_depth_various_depths
        card = build_card_with_entries([
          { "uid" => "d0", "keys" => ["magic"], "content" => "DEPTH_0", "position" => "at_depth", "depth" => 0 },
          { "uid" => "d1", "keys" => ["magic"], "content" => "DEPTH_1", "position" => "at_depth", "depth" => 1 },
          { "uid" => "d2", "keys" => ["magic"], "content" => "DEPTH_2", "position" => "at_depth", "depth" => 2 },
        ])

        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "")
        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "First"),
          Prompt::Message.new(role: :assistant, content: "Second"),
        ])
        plan = TavernKit.build(character: card, user: @user, preset: preset, history: history, message: "magic")
        messages = plan.to_messages
        contents = messages.map { |m| m[:content] }

        d0_idx = contents.index { |c| c.include?("DEPTH_0") }
        d1_idx = contents.index { |c| c.include?("DEPTH_1") }
        d2_idx = contents.index { |c| c.include?("DEPTH_2") }
        user_msg_idx = contents.index("magic")

        refute_nil d0_idx
        refute_nil d1_idx
        refute_nil d2_idx

        # d0 after user message, d1 before user message, d2 before that
        assert d0_idx > user_msg_idx, "depth=0 should be after user message"
        assert d1_idx < user_msg_idx, "depth=1 should be before user message"
        assert d2_idx < d1_idx, "depth=2 should be before depth=1"
      end

      # Test: outlet position with macro expansion
      def test_outlet_position_with_macro
        card = build_card_with_entries([
          { "uid" => "outlet1", "keys" => ["magic"], "content" => "OUTLET_CONTENT", "position" => "outlet", "outlet" => "lore" },
        ])

        preset = Preset.new(
          main_prompt: "MAIN\n{{outlet::lore}}",
          post_history_instructions: ""
        )
        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "magic")

        messages = plan.to_messages
        main_msg = messages.find { |m| m[:content].include?("MAIN") }

        refute_nil main_msg
        assert_includes main_msg[:content], "OUTLET_CONTENT", "Outlet content should be expanded in main prompt"
      end

      # Test: Multiple outlet entries with same outlet name
      def test_multiple_outlets_same_name
        card = build_card_with_entries([
          { "uid" => "o1", "keys" => ["magic"], "content" => "FIRST", "position" => "outlet", "outlet" => "lore", "insertion_order" => 10 },
          { "uid" => "o2", "keys" => ["magic"], "content" => "SECOND", "position" => "outlet", "outlet" => "lore", "insertion_order" => 20 },
        ])

        preset = Preset.new(
          main_prompt: "{{outlet::lore}}",
          post_history_instructions: ""
        )
        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "magic")

        messages = plan.to_messages
        main_msg = messages.first

        # Both should be present, joined with newline
        assert_includes main_msg[:content], "FIRST"
        assert_includes main_msg[:content], "SECOND"

        # Order should be by insertion_order
        first_pos = main_msg[:content].index("FIRST")
        second_pos = main_msg[:content].index("SECOND")
        assert first_pos < second_pos, "FIRST should come before SECOND based on insertion_order"
      end

      # Test: World Info not triggered when keyword not present
      def test_world_info_not_triggered_without_keyword
        card = build_card_with_entries([
          { "uid" => "wi1", "keys" => ["magic"], "content" => "SHOULD_NOT_APPEAR", "position" => "after_char_defs" },
        ])

        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "")
        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "hello there")

        messages = plan.to_messages
        contents = messages.map { |m| m[:content] }.join("\n")

        refute_includes contents, "SHOULD_NOT_APPEAR", "WI should not appear without keyword match"
      end

      # Test: Constant World Info always appears
      def test_constant_world_info_always_appears
        card = build_card_with_entries([
          { "uid" => "const", "keys" => [], "content" => "ALWAYS_PRESENT", "position" => "after_char_defs", "constant" => true },
        ])

        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "")
        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "hello there")

        messages = plan.to_messages
        contents = messages.map { |m| m[:content] }.join("\n")

        assert_includes contents, "ALWAYS_PRESENT", "Constant WI should appear regardless of keywords"
      end

      # Test: All 8 positions in one test
      def test_all_positions_integration
        card = build_card_with_entries([
          { "uid" => "p0", "keys" => ["test"], "content" => "BEFORE_CHAR", "position" => 0 },
          { "uid" => "p1", "keys" => ["test"], "content" => "AFTER_CHAR", "position" => 1 },
          { "uid" => "p2", "keys" => ["test"], "content" => "TOP_AN", "position" => 2 },
          { "uid" => "p3", "keys" => ["test"], "content" => "BOTTOM_AN", "position" => 3 },
          { "uid" => "p4", "keys" => ["test"], "content" => "AT_DEPTH", "position" => 4, "depth" => 0 },
          { "uid" => "p5", "keys" => ["test"], "content" => "{{user}}: BEX\n{{char}}: BEX_REPLY", "position" => 5 },
          { "uid" => "p6", "keys" => ["test"], "content" => "{{user}}: AEX\n{{char}}: AEX_REPLY", "position" => 6 },
          { "uid" => "p7", "keys" => ["test"], "content" => "OUTLET_DATA", "position" => 7, "outlet" => "X" },
        ])

        preset = Preset.new(
          main_prompt: "MAIN {{outlet::X}}",
          post_history_instructions: "",
          new_example_chat: "[EX]",
          authors_note: "AN"
        )
        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "test")

        messages = plan.to_messages
        contents = messages.map { |m| m[:content] }
        all_content = contents.join("\n")

        # All should be present
        assert_includes all_content, "BEFORE_CHAR"
        assert_includes all_content, "AFTER_CHAR"
        assert_includes all_content, "TOP_AN"
        assert_includes all_content, "BOTTOM_AN"
        assert_includes all_content, "AT_DEPTH"
        assert_includes all_content, "BEX_REPLY"
        assert_includes all_content, "AEX_REPLY"
        assert_includes all_content, "OUTLET_DATA"
      end
    end
  end
end
