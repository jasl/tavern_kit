# frozen_string_literal: true

require "test_helper"

module TavernKit
  module STCompatibility
    # Tests for SillyTavern in-chat injection behavior.
    #
    # ST Prompt Manager in-chat rules:
    # 1. Depth=0 inserts after last message
    # 2. Depth=N inserts N messages from the end
    # 3. Role ordering at same depth+order: Assistant → User → System
    # 4. Same role+depth+order prompts are merged
    class TestInChatBehavior < Minitest::Test
      def setup
        @character = CharacterCard.load(
          {
            "spec" => "chara_card_v2",
            "spec_version" => "2.0",
            "data" => {
              "name" => "Alice",
              "description" => "A test character",
              "system_prompt" => nil,
              "post_history_instructions" => nil,
              "first_mes" => "Hello!",
              "mes_example" => "",
            },
          }
        )
        @user = User.new(name: "Bob", persona: nil)
      end

      # Test: depth=0 inserts after the last message
      def test_depth_zero_inserts_after_last_message
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "character_description", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
            { "id" => "depth_zero", "content" => "DEPTH_ZERO", "role" => "system", "position" => "in_chat", "depth" => 0 },
          ].map { |h| Prompt::PromptEntry.from_hash(h) }
        )

        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "First"),
          Prompt::Message.new(role: :assistant, content: "Second"),
        ])

        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Third")
        messages = plan.to_messages

        # Find positions
        third_idx = messages.index { |m| m[:content] == "Third" }
        depth_zero_idx = messages.index { |m| m[:content] == "DEPTH_ZERO" }

        refute_nil third_idx, "User message 'Third' should be present"
        refute_nil depth_zero_idx, "DEPTH_ZERO should be present"

        # depth=0 should be after the last message (user message "Third")
        assert depth_zero_idx > third_idx, "depth=0 injection should be after the last message"
      end

      # Test: depth=1 inserts before the last message
      def test_depth_one_inserts_before_last_message
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
            { "id" => "depth_one", "content" => "DEPTH_ONE", "role" => "system", "position" => "in_chat", "depth" => 1 },
          ].map { |h| Prompt::PromptEntry.from_hash(h) }
        )

        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "First"),
          Prompt::Message.new(role: :assistant, content: "Second"),
        ])

        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Third")
        messages = plan.to_messages

        third_idx = messages.index { |m| m[:content] == "Third" }
        depth_one_idx = messages.index { |m| m[:content] == "DEPTH_ONE" }

        refute_nil third_idx
        refute_nil depth_one_idx

        # depth=1 should be before "Third" (the last message)
        assert depth_one_idx < third_idx, "depth=1 injection should be before the last message"

        # And after "Second"
        second_idx = messages.index { |m| m[:content] == "Second" }
        assert depth_one_idx > second_idx, "depth=1 should be after Second"
      end

      # Test: depth=2 inserts two messages from the end
      def test_depth_two_inserts_two_from_end
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
            { "id" => "depth_two", "content" => "DEPTH_TWO", "role" => "system", "position" => "in_chat", "depth" => 2 },
          ].map { |h| Prompt::PromptEntry.from_hash(h) }
        )

        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "First"),
          Prompt::Message.new(role: :assistant, content: "Second"),
        ])

        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Third")
        messages = plan.to_messages

        third_idx = messages.index { |m| m[:content] == "Third" }
        second_idx = messages.index { |m| m[:content] == "Second" }
        depth_two_idx = messages.index { |m| m[:content] == "DEPTH_TWO" }

        refute_nil depth_two_idx

        # depth=2 should be before both "Third" and "Second"
        assert depth_two_idx < second_idx, "depth=2 should be before Second"
        assert depth_two_idx < third_idx, "depth=2 should be before Third"
      end

      # Test: Role ordering at same depth+order: Assistant → User → System
      def test_role_ordering_assistant_user_system
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
            # All at depth=0, same order group - should be ordered: assistant, user, system
            { "id" => "sys", "content" => "SYSTEM_MSG", "role" => "system", "position" => "in_chat", "depth" => 0, "order" => 10 },
            { "id" => "user", "content" => "USER_MSG", "role" => "user", "position" => "in_chat", "depth" => 0, "order" => 10 },
            { "id" => "asst", "content" => "ASSISTANT_MSG", "role" => "assistant", "position" => "in_chat", "depth" => 0, "order" => 10 },
          ].map { |h| Prompt::PromptEntry.from_hash(h) }
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")
        messages = plan.to_messages

        # Find the injected messages (they should be after "Hello" which is the user message)
        hello_idx = messages.index { |m| m[:content] == "Hello" }

        user_idx = messages.index { |m| m[:content] == "USER_MSG" }
        asst_idx = messages.index { |m| m[:content] == "ASSISTANT_MSG" }
        sys_idx = messages.index { |m| m[:content] == "SYSTEM_MSG" }

        refute_nil user_idx, "USER_MSG should be present"
        refute_nil asst_idx, "ASSISTANT_MSG should be present"
        refute_nil sys_idx, "SYSTEM_MSG should be present"

        # All should be after hello_idx (depth=0)
        assert user_idx > hello_idx
        assert asst_idx > hello_idx
        assert sys_idx > hello_idx

        # Order should be: Assistant → User → System
        assert asst_idx < user_idx, "Assistant should come before User"
        assert user_idx < sys_idx, "User should come before System"
      end

      # Test: injection_order creates ordering groups (no cross-group merge)
      def test_same_role_depth_orders_do_not_merge_and_sort_by_order
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
            # Three system messages at depth=0 with different orders
            { "id" => "sys3", "content" => "THIRD", "role" => "system", "position" => "in_chat", "depth" => 0, "order" => 30 },
            { "id" => "sys1", "content" => "FIRST", "role" => "system", "position" => "in_chat", "depth" => 0, "order" => 10 },
            { "id" => "sys2", "content" => "SECOND", "role" => "system", "position" => "in_chat", "depth" => 0, "order" => 20 },
          ].map { |h| Prompt::PromptEntry.from_hash(h) }
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")
        messages = plan.to_messages

        first_idx = messages.index { |m| m[:content] == "FIRST" }
        second_idx = messages.index { |m| m[:content] == "SECOND" }
        third_idx = messages.index { |m| m[:content] == "THIRD" }

        refute_nil first_idx
        refute_nil second_idx
        refute_nil third_idx

        assert first_idx < second_idx, "Lower injection order should appear earlier"
        assert second_idx < third_idx, "Lower injection order should appear earlier"
      end

      # Test: Different depths are not merged
      def test_different_depths_not_merged
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
            { "id" => "depth0", "content" => "DEPTH0", "role" => "system", "position" => "in_chat", "depth" => 0 },
            { "id" => "depth1", "content" => "DEPTH1", "role" => "system", "position" => "in_chat", "depth" => 1 },
          ].map { |h| Prompt::PromptEntry.from_hash(h) }
        )

        history = ChatHistory.wrap([Prompt::Message.new(role: :user, content: "First")])

        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Second")
        messages = plan.to_messages

        # Should be separate messages, not merged
        depth0_msg = messages.find { |m| m[:content] == "DEPTH0" }
        depth1_msg = messages.find { |m| m[:content] == "DEPTH1" }

        refute_nil depth0_msg, "DEPTH0 message should exist separately"
        refute_nil depth1_msg, "DEPTH1 message should exist separately"
      end

      # Test: Depth clamping - depth larger than history length clamps to start
      def test_depth_clamping_to_start
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
            # Depth 100 with only 2 messages in history - should clamp to start of chat
            { "id" => "deep", "content" => "VERY_DEEP", "role" => "system", "position" => "in_chat", "depth" => 100 },
          ].map { |h| Prompt::PromptEntry.from_hash(h) }
        )

        history = ChatHistory.wrap([Prompt::Message.new(role: :user, content: "First")])

        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Second")
        messages = plan.to_messages

        # Find positions within the chat history section
        first_idx = messages.index { |m| m[:content] == "First" }
        deep_idx = messages.index { |m| m[:content] == "VERY_DEEP" }

        refute_nil deep_idx, "VERY_DEEP should be present"

        # With depth > history length, it should be clamped to the start of chat history
        # So VERY_DEEP should appear before First
        assert deep_idx < first_idx, "Large depth should clamp to start of chat history"
      end

      # Test: Mixed in-chat injection (World Info + prompt entries)
      def test_mixed_in_chat_with_world_info
        card = CharacterCard.load(
          {
            "spec" => "chara_card_v2",
            "spec_version" => "2.0",
            "data" => {
              "name" => "Alice",
              "description" => "A test character",
              "system_prompt" => nil,
              "post_history_instructions" => nil,
              "first_mes" => "",
              "mes_example" => "",
              "character_book" => {
                "scan_depth" => 10,
                "entries" => [
                  { "uid" => "wi1", "keys" => ["magic"], "content" => "WORLD_INFO", "position" => "at_depth", "depth" => 0, "role" => "system" },
                ],
              },
            },
          }
        )

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "character_description", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
            { "id" => "prompt_entry", "content" => "PROMPT_ENTRY", "role" => "system", "position" => "in_chat", "depth" => 0, "order" => 50 },
          ].map { |h| Prompt::PromptEntry.from_hash(h) }
        )

        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "magic")
        messages = plan.to_messages

        prompt_idx = messages.index { |m| m[:content] == "PROMPT_ENTRY" }
        wi_idx = messages.index { |m| m[:content] == "WORLD_INFO" }

        refute_nil prompt_idx, "PROMPT_ENTRY should be present"
        refute_nil wi_idx, "WORLD_INFO should be present"

        assert prompt_idx < wi_idx, "Prompt entry (order 50) should come before WI (order 100)"
      end
    end
  end
end
