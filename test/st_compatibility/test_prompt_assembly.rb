# frozen_string_literal: true

require "test_helper"

module TavernKit
  module STCompatibility
    # Tests for SillyTavern prompt assembly order and structure.
    #
    # ST Prompt Manager assembly rules:
    # 1. Default order follows ST's built-in prompt manager sequence
    # 2. Custom prompt_entries ordering is respected (for relative entries)
    # 3. Disabled entries are skipped
    # 4. PHI is always last
    class TestPromptAssembly < Minitest::Test
      def setup
        @character = CharacterCard.load(
          {
            "spec" => "chara_card_v2",
            "spec_version" => "2.0",
            "data" => {
              "name" => "Alice",
              "description" => "A wise guide",
              "personality" => "Calm and collected",
              "scenario" => "A mystical forest",
              "system_prompt" => nil,
              "post_history_instructions" => "Stay in character.",
              "first_mes" => "Welcome!",
              "mes_example" => <<~EX,
                <START>
                {{user}}: Hello
                {{char}}: Greetings, traveler.
              EX
            },
          }
        )
        @user = User.new(name: "Bob", persona: "An adventurer seeking wisdom")
      end

      # Test: Default ST order is main → WI before → persona → char → WI after → examples → AN → history → PHI
      def test_default_st_order
        preset = Preset.new(
          main_prompt: "MAIN_PROMPT",
          post_history_instructions: "PHI_CONTENT",
          new_example_chat: "[EXAMPLE]",
          authors_note: "AN_CONTENT",
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")

        blocks = plan.blocks
        slots = blocks.map(&:slot)

        # Verify key slots appear in expected order
        main_idx = slots.index(:main_prompt)
        persona_idx = slots.index(:persona)
        char_desc_idx = slots.index(:character_description)
        user_msg_idx = slots.index(:user_message)
        phi_idx = slots.index(:post_history_instructions)

        refute_nil main_idx, "Main prompt should be present"
        refute_nil persona_idx, "Persona should be present"
        refute_nil char_desc_idx, "Character description should be present"
        refute_nil user_msg_idx, "User message should be present"
        refute_nil phi_idx, "PHI should be present"

        # Basic ordering checks
        assert main_idx < persona_idx, "Main prompt should come before persona"
        assert persona_idx < char_desc_idx, "Persona should come before character"
        assert user_msg_idx < phi_idx, "User message should come before PHI"
      end

      # Test: Custom prompt_entries ordering is respected
      def test_custom_entries_ordering
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "PHI",
          prompt_entries: [
            # Reordered: character before main_prompt
            { "id" => "character_description", "pinned" => true },
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "persona_description", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
            { "id" => "post_history_instructions", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")

        blocks = plan.blocks
        slots = blocks.map(&:slot)

        # Character should come before main_prompt due to custom ordering
        char_idx = slots.index(:character_description)
        main_idx = slots.index(:main_prompt)

        refute_nil char_idx
        refute_nil main_idx

        assert char_idx < main_idx, "Character should come before main_prompt per custom order"
      end

      # Test: Disabled entries are skipped
      def test_disabled_entries_skipped
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "persona_description", "pinned" => true, "enabled" => false }, # Disabled
            { "id" => "character_description", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")

        blocks = plan.blocks

        # Persona should not be present
        persona_block = blocks.find { |b| b.slot == :persona }
        assert_nil persona_block, "Disabled persona should not be present"

        # Other blocks should still be present
        main_block = blocks.find { |b| b.slot == :main_prompt }
        refute_nil main_block, "Main prompt should be present"
      end

      # Test: Custom relative prompt inserted at correct position
      def test_custom_relative_prompt_position
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "custom_between", "content" => "CUSTOM_BETWEEN", "role" => "system", "position" => "relative" },
            { "id" => "character_description", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")

        messages = plan.to_messages
        contents = messages.map { |m| m[:content] }

        custom_idx = contents.index("CUSTOM_BETWEEN")
        refute_nil custom_idx, "Custom relative prompt should be present"

        # Find main and character
        main_idx = contents.index { |c| c.include?("MAIN") }
        char_idx = contents.index { |c| c == "A wise guide" }

        # Custom should be between main and character
        assert custom_idx > main_idx, "Custom should be after main"
        assert custom_idx < char_idx, "Custom should be before character"
      end

      # Test: Multiple custom prompts maintain relative order
      def test_multiple_custom_prompts_order
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "custom1", "content" => "CUSTOM_ONE", "role" => "system", "position" => "relative" },
            { "id" => "custom2", "content" => "CUSTOM_TWO", "role" => "system", "position" => "relative" },
            { "id" => "custom3", "content" => "CUSTOM_THREE", "role" => "system", "position" => "relative" },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")

        messages = plan.to_messages
        contents = messages.map { |m| m[:content] }

        one_idx = contents.index("CUSTOM_ONE")
        two_idx = contents.index("CUSTOM_TWO")
        three_idx = contents.index("CUSTOM_THREE")

        refute_nil one_idx
        refute_nil two_idx
        refute_nil three_idx

        assert one_idx < two_idx, "CUSTOM_ONE should come before CUSTOM_TWO"
        assert two_idx < three_idx, "CUSTOM_TWO should come before CUSTOM_THREE"
      end

      # Test: Empty pinned group is skipped
      def test_empty_pinned_group_skipped
        card = CharacterCard.load(
          {
            "spec" => "chara_card_v2",
            "spec_version" => "2.0",
            "data" => {
              "name" => "Alice",
              "description" => "", # Empty
              "personality" => "", # Empty
              "scenario" => "", # Empty
              "system_prompt" => nil,
              "post_history_instructions" => nil,
              "first_mes" => "",
              "mes_example" => "",
            },
          }
        )

        user = User.new(name: "Bob", persona: nil) # No persona

        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "")
        plan = TavernKit.build(character: card, user: user, preset: preset, message: "Hello")

        blocks = plan.blocks

        # These should not appear as they are empty
        persona_block = blocks.find { |b| b.slot == :persona }
        desc_block = blocks.find { |b| b.slot == :character_description }
        pers_block = blocks.find { |b| b.slot == :character_personality }
        scenario_block = blocks.find { |b| b.slot == :scenario }

        assert_nil persona_block, "Empty persona should not appear"
        assert_nil desc_block, "Empty description should not appear"
        assert_nil pers_block, "Empty personality should not appear"
        assert_nil scenario_block, "Empty scenario should not appear"

        header_block = blocks.find { |b| b.slot == :character_header }
        assert_nil header_block, "Character header should not appear in ST-compatible output"
      end

      # Test: Role override for pinned groups
      def test_role_override_for_pinned_groups
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true, "role" => "user" }, # Override to user role
            { "id" => "character_description", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")

        messages = plan.to_messages

        # Main prompt should have user role now
        main_msg = messages.find { |m| m[:content].include?("MAIN") }
        refute_nil main_msg
        assert_equal "user", main_msg[:role], "Main prompt should have overridden user role"
      end
    end
  end
end
