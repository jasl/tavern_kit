# frozen_string_literal: true

require "test_helper"

module TavernKit
  module STCompatibility
    # Tests for SillyTavern Prompt Manager entry normalization rules.
    #
    # ST Prompt Manager constraints:
    # 1. Multi-block markers (chat_history, chat_examples) cannot be in-chat
    # 2. PHI is always the last message regardless of position in entries list
    class TestEntryNormalization < Minitest::Test
      def setup
        @character = CharacterCard.load(
          {
            "spec" => "chara_card_v2",
            "spec_version" => "2.0",
            "data" => {
              "name" => "Alice",
              "description" => "A test character",
              "personality" => "Friendly",
              "scenario" => "Testing",
              "system_prompt" => nil,
              "post_history_instructions" => "Stay in character.",
              "first_mes" => "Hello!",
              "mes_example" => <<~EX,
                <START>
                {{user}}: Hi
                {{char}}: Hello there!
              EX
            },
          }
        )
        @user = User.new(name: "Bob", persona: nil)
      end

      # Test: chat_history set to in_chat should be forced to relative
      def test_chat_history_forced_to_relative_when_set_to_in_chat
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "character_description", "pinned" => true },
            # Attempt to set chat_history to in_chat - should be forced to relative
            { "id" => "chat_history", "pinned" => true, "position" => "in_chat", "depth" => 2 },
            { "id" => "post_history_instructions", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "First"),
          Prompt::Message.new(role: :assistant, content: "Second"),
        ])
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Third")

        # Chat history should appear in the normal order, not injected at depth
        messages = plan.to_messages

        # Find the history messages
        first_idx = messages.index { |m| m[:content] == "First" }
        second_idx = messages.index { |m| m[:content] == "Second" }
        third_idx = messages.index { |m| m[:content] == "Third" }

        refute_nil first_idx, "First history message should be present"
        refute_nil second_idx, "Second history message should be present"
        refute_nil third_idx, "Third (user) message should be present"

        # They should be in order
        assert first_idx < second_idx, "History messages should be in order"
        assert second_idx < third_idx, "User message should come after history"
      end

      # Test: chat_examples set to in_chat should be forced to relative
      def test_chat_examples_forced_to_relative_when_set_to_in_chat
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          new_example_chat: "[EXAMPLE]",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            # Attempt to set chat_examples to in_chat - should be forced to relative
            { "id" => "chat_examples", "pinned" => true, "position" => "in_chat", "depth" => 0 },
            { "id" => "chat_history", "pinned" => true },
            { "id" => "post_history_instructions", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")

        messages = plan.to_messages

        # Examples should appear before chat history (relative position), not at depth 0
        example_idx = messages.index { |m| m[:content].include?("Hello there!") }
        user_msg_idx = messages.index { |m| m[:content] == "Hello" }

        refute_nil example_idx, "Example message should be present"
        refute_nil user_msg_idx, "User message should be present"

        # Examples should come BEFORE user message (relative order)
        assert example_idx < user_msg_idx, "Examples should appear before user message in relative order"
      end

      # Test: PHI is always last regardless of position in prompt_entries
      def test_phi_always_last_regardless_of_entries_order
        # Use card without its own PHI to test preset PHI
        card = CharacterCard.load(
          {
            "spec" => "chara_card_v2",
            "spec_version" => "2.0",
            "data" => {
              "name" => "Alice",
              "description" => "A test character",
              "system_prompt" => nil,
              "post_history_instructions" => nil, # No card PHI
              "first_mes" => "Hello!",
            },
          }
        )

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "PHI CONTENT",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            # PHI placed in the middle - should still be last in output
            { "id" => "post_history_instructions", "pinned" => true },
            { "id" => "character_description", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "Hello")

        messages = plan.to_messages

        # PHI should be the absolute last message
        assert_equal "PHI CONTENT", messages.last[:content], "PHI should be the last message"
        assert_equal "system", messages.last[:role], "PHI should have system role"
      end

      # Test: PHI at the start of entries is still last in output
      def test_phi_at_start_still_last_in_output
        # Use card without its own PHI to test preset PHI
        card = CharacterCard.load(
          {
            "spec" => "chara_card_v2",
            "spec_version" => "2.0",
            "data" => {
              "name" => "Alice",
              "description" => "A test character",
              "system_prompt" => nil,
              "post_history_instructions" => nil, # No card PHI
              "first_mes" => "Hello!",
            },
          }
        )

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "PHI FIRST IN LIST",
          prompt_entries: [
            # PHI at the very start
            { "id" => "post_history_instructions", "pinned" => true },
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "character_description", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "Hello")

        messages = plan.to_messages

        # PHI should still be the last message
        assert_equal "PHI FIRST IN LIST", messages.last[:content]
      end

      # Test: Disabled PHI should not appear
      def test_disabled_phi_does_not_appear
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "DISABLED PHI",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "character_description", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
            { "id" => "post_history_instructions", "pinned" => true, "enabled" => false },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")

        messages = plan.to_messages

        # PHI should not appear when disabled
        refute messages.any? { |m| m[:content] == "DISABLED PHI" }, "Disabled PHI should not appear"
      end

      # Test: Pipeline correctly separates entries by position
      def test_pipeline_correctly_partitions_entries
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "PHI",
          prefer_char_instructions: false, # Don't use character's PHI
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "custom_in_chat", "content" => "INCHAT", "position" => "in_chat", "depth" => 0 },
            { "id" => "chat_history", "pinned" => true, "position" => "in_chat" }, # Should be forced relative
            { "id" => "post_history_instructions", "pinned" => true }, # Should be forced last
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")
        messages = plan.to_messages

        # Verify the final message structure
        # PHI should be last
        assert_equal "PHI", messages.last[:content]

        # INCHAT should be present at depth 0 (per ST: depth 0 = after the most recent message)
        inchat_idx = messages.index { |m| m[:content] == "INCHAT" }
        hello_idx = messages.index { |m| m[:content] == "Hello" }
        phi_idx = messages.index { |m| m[:content] == "PHI" }

        refute_nil inchat_idx, "INCHAT should be present"
        refute_nil hello_idx, "Hello (user message) should be present"

        # Per ST behavior: depth 0 = insert at the very end of chat history (after the most recent message)
        # So INCHAT should come after Hello but before PHI
        assert inchat_idx > hello_idx, "In-chat at depth 0 should be after the user message"
        assert inchat_idx < phi_idx, "In-chat should come before PHI (forced last)"
      end
    end
  end
end
