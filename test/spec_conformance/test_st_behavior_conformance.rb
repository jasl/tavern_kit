# frozen_string_literal: true

require "test_helper"

module TavernKit
  module SpecConformance
    class TestSTBehaviorConformance < Minitest::Test
      def setup
        @user = User.new(name: "User")
      end

      def test_main_prompt_system_message_position
        character = Character.create(name: "Char", mes_example: "")

        preset = Preset.new(
          main_prompt: "MainPrompt",
          post_history_instructions: "",
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset) do
          message "CURRENT"
        end

        msgs = plan.messages
        first = msgs.first
        assert_equal :system, first.role
        assert_includes first.content, "MainPrompt"
      end

      def test_worldinfo_before_triggers_on_keyword
        character = Character.create(name: "Char", mes_example: "")
        lore_book = {
          "name" => "TestLore",
          "entries" => [
            {
              "uid" => 1,
              "content" => "WorldInfo content",
              "key" => ["trigger"],
              "position" => "before_char_defs",
              "depth" => 4,
              "constant" => false,
              "enabled" => true,
            },
          ],
        }

        preset = Preset.new(
          main_prompt: "Main",
          post_history_instructions: "",
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset, lore_books: [lore_book]) do
          message "trigger"
        end

        contents = plan.messages.flat_map { |m| m.content.split }
        wi_idx = contents.index("WorldInfo")
        main_idx = contents.index("Main")
        assert wi_idx, "Expected WorldInfo content"
        # before_char_defs position appears after main_prompt but before character descriptions
        assert_operator wi_idx, :>, main_idx, "before_char_defs WI should appear after main_prompt"
      end

      def test_worldinfo_after_triggers_on_keyword
        character = Character.create(name: "Char", mes_example: "")
        lore_book = {
          "name" => "TestLore",
          "entries" => [
            {
              "uid" => 1,
              "content" => "AfterContent",
              "key" => ["activate"],
              "position" => "after_char_defs",
              "depth" => 4,
              "constant" => false,
              "enabled" => true,
            },
          ],
        }

        preset = Preset.new(
          main_prompt: "Main",
          post_history_instructions: "",
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset, lore_books: [lore_book]) do
          message "activate"
        end

        contents = plan.messages.flat_map { |m| m.content.split }
        after_idx = contents.index("AfterContent")
        main_idx = contents.index("Main")
        assert after_idx, "Expected AfterContent"
        assert_operator after_idx, :>, main_idx, "after_char_defs WI should appear after main_prompt"
      end

      def test_authors_note_position_in_chat
        character = Character.create(name: "Char", mes_example: "")

        preset = Preset.new(
          main_prompt: "Main",
          post_history_instructions: "",
          authors_note: "AuthorNote",
          authors_note_depth: 2,
          authors_note_position: :in_chat,
        )

        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "H1"),
          Prompt::Message.new(role: :assistant, content: "H2"),
          Prompt::Message.new(role: :user, content: "H3"),
          Prompt::Message.new(role: :assistant, content: "H4"),
        ])

        plan = TavernKit.build(character: character, user: @user, preset: preset, history: history) do
          message "CURRENT"
        end

        msgs = plan.messages
        idx = msgs.index { |m| m.content == "AuthorNote" }
        last_user_idx = msgs.rindex { |m| m.role == :user }
        assert idx, "Expected AuthorNote in messages"
        assert_operator idx, :<, last_user_idx
      end

      def test_macro_char_and_user_substitution
        character = Character.create(name: "Alice", mes_example: "")

        preset = Preset.new(
          main_prompt: "{{char}} and {{user}}",
          post_history_instructions: "",
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset) do
          message "Hi"
        end

        main = plan.messages.first.content
        assert_includes main, "Alice"
        assert_includes main, "User"
      end

      def test_persona_description_substitution
        character = Character.create(name: "Char", mes_example: "")
        user = User.new(name: "User", persona: "I am a warrior.")

        preset = Preset.new(
          main_prompt: "{{persona}}",
          post_history_instructions: "",
        )

        plan = TavernKit.build(character: character, user: user, preset: preset) do
          message "Hi"
        end

        assert_includes plan.messages.first.content, "I am a warrior"
      end

      def test_description_substitution
        character = Character.create(
          name: "Bob",
          description: "Bob is a cheerful assistant.",
          mes_example: ""
        )

        preset = Preset.new(
          main_prompt: "{{description}}",
          post_history_instructions: "",
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset) do
          message "Hi"
        end

        assert_includes plan.messages.first.content, "cheerful assistant"
      end

      def test_history_messages_order
        character = Character.create(name: "Char", mes_example: "")

        preset = Preset.new(
          main_prompt: "Main",
          post_history_instructions: "",
        )

        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "First"),
          Prompt::Message.new(role: :assistant, content: "Second"),
        ])

        plan = TavernKit.build(character: character, user: @user, preset: preset, history: history) do
          message "Current"
        end

        msgs = plan.messages
        first_idx = msgs.index { |m| m.content == "First" }
        second_idx = msgs.index { |m| m.content == "Second" }
        current_idx = msgs.index { |m| m.content == "Current" }

        assert first_idx, "History first should be present"
        assert second_idx, "History second should be present"
        assert current_idx, "Current message should be present"

        assert_operator first_idx, :<, second_idx
        assert_operator second_idx, :<, current_idx
      end

      def test_post_history_instructions_position
        character = Character.create(name: "Char", mes_example: "")

        preset = Preset.new(
          main_prompt: "Main",
          post_history_instructions: "PostHistoryInstructions",
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset) do
          message "Hi"
        end

        msgs = plan.messages
        system_msgs = msgs.select { |m| m.role == :system }
        last_system = system_msgs.last

        assert_equal "PostHistoryInstructions", last_system&.content
      end

      def test_relative_lore_injection_into_chat
        character = Character.create(name: "Char", mes_example: "")
        lore_book = {
          "name" => "TestLore",
          "entries" => [
            {
              "uid" => 1,
              "content" => "LoreInjected",
              "key" => ["kw"],
              "position" => "in_chat",
              "depth" => 1,
              "constant" => false,
              "role" => "system",
              "enabled" => true,
            },
          ],
        }

        preset = Preset.new(
          main_prompt: "Main",
          post_history_instructions: "",
        )

        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "One"),
          Prompt::Message.new(role: :assistant, content: "Two"),
          Prompt::Message.new(role: :user, content: "Three kw"),
        ])

        plan = TavernKit.build(character: character, user: @user, preset: preset, lore_books: [lore_book], history: history) do
          message "CURRENT"
        end

        msgs = plan.messages
        lore_idx = msgs.index { |m| m.content.include?("LoreInjected") }
        current_idx = msgs.index { |m| m.content == "CURRENT" }

        assert lore_idx, "LoreInjected should be present"
        assert_operator lore_idx, :<, current_idx
      end

      def test_mes_example_goes_in_chat_examples
        character = Character.create(
          name: "Char",
          mes_example: "<START>\n{{user}}: Hello\n{{char}}: Hi"
        )

        preset = Preset.new(
          main_prompt: "Main",
          post_history_instructions: "",
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset) do
          message "Hi"
        end

        # Check blocks that contain example content
        blocks = plan.blocks.select { |b| b.slot.to_s.include?("example") || b.content.to_s.include?("Hello") }
        assert blocks.any?, "Expected example blocks"
      end

      def test_constant_worldinfo_included_without_scan_matching
        character = Character.create(name: "Char", mes_example: "")
        lore_book = {
          "name" => "TestLore",
          "entries" => [
            {
              "uid" => 1,
              "content" => "ConstantContent",
              "key" => ["nevermatch"],
              "position" => "before_char_defs",
              "depth" => 4,
              "constant" => true,
              "enabled" => true,
            },
          ],
        }

        preset = Preset.new(
          main_prompt: "Main",
          post_history_instructions: "",
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset, lore_books: [lore_book]) do
          message "unrelated"
        end

        contents = plan.messages.map(&:content).join
        assert_includes contents, "ConstantContent"
      end

      def test_time_macros_expand
        character = Character.create(name: "Char", mes_example: "")

        preset = Preset.new(
          main_prompt: "{{time}}",
          post_history_instructions: "",
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset) do
          message "Hi"
        end

        refute_includes plan.messages.first.content, "{{time}}"
      end
    end
  end
end
