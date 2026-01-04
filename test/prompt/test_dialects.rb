# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Prompt
    class TestDialects < Minitest::Test
      def setup
        @messages = [
          Message.new(role: :system, content: "You are a helpful assistant."),
          Message.new(role: :system, content: "Character info here."),
          Message.new(role: :user, content: "Hello!"),
          Message.new(role: :assistant, content: "Hi there!"),
          Message.new(role: :user, content: "How are you?"),
        ]
      end

      # --- OpenAI Dialect ---

      def test_openai_returns_array_of_hashes
        result = Dialects.convert(@messages, dialect: :openai)

        assert_kind_of Array, result
        assert_equal 5, result.length
        assert result.all? { |m| m.is_a?(Hash) }
      end

      def test_openai_preserves_roles_and_content
        result = Dialects.convert(@messages, dialect: :openai)

        assert_equal "system", result[0][:role]
        assert_equal "You are a helpful assistant.", result[0][:content]
        assert_equal "user", result[2][:role]
        assert_equal "Hello!", result[2][:content]
      end

      def test_openai_preserves_name_when_present
        messages = [
          Message.new(role: :user, content: "Hello!", name: "Alice"),
        ]
        result = Dialects.convert(messages, dialect: :openai)

        assert_equal "Alice", result[0][:name]
      end

      def test_openai_omits_name_when_nil_or_empty
        messages = [
          Message.new(role: :user, content: "Hello!"),
          Message.new(role: :user, content: "Hi!", name: ""),
        ]
        result = Dialects.convert(messages, dialect: :openai)

        refute result[0].key?(:name)
        refute result[1].key?(:name)
      end

      # --- Anthropic Dialect ---

      def test_anthropic_returns_hash_with_messages_and_system
        result = Dialects.convert(@messages, dialect: :anthropic)

        assert_kind_of Hash, result
        assert result.key?(:messages)
        assert result.key?(:system)
      end

      def test_anthropic_extracts_leading_system_messages
        result = Dialects.convert(@messages, dialect: :anthropic)

        assert_equal 2, result[:system].length
        assert_equal({ type: "text", text: "You are a helpful assistant." }, result[:system][0])
        assert_equal({ type: "text", text: "Character info here." }, result[:system][1])
      end

      def test_anthropic_converts_content_to_array_format
        result = Dialects.convert(@messages, dialect: :anthropic)

        result[:messages].each do |msg|
          assert_kind_of Array, msg[:content]
          assert msg[:content].all? { |c| c[:type] == "text" }
        end
      end

      def test_anthropic_converts_system_to_user_after_extraction
        messages = [
          Message.new(role: :user, content: "Hello!"),
          Message.new(role: :assistant, content: "Hi!"),
          Message.new(role: :system, content: "A system message in the middle."),
          Message.new(role: :assistant, content: "Sure!"),
        ]
        result = Dialects.convert(messages, dialect: :anthropic)

        # No leading system messages
        assert_empty result[:system]

        # All messages should only be user or assistant
        roles = result[:messages].map { |m| m[:role] }
        assert roles.all? { |r| %w[user assistant].include?(r) }

        # The system message should be converted to user (and merged with next same-role if any)
        # After conversion: user, assistant, user (from system), assistant
        # After merge: user, assistant, user, assistant (4 messages)
        assert_equal 4, result[:messages].length
        assert_equal "user", result[:messages][2][:role]
        assert_equal "A system message in the middle.", result[:messages][2][:content][0][:text]
      end

      def test_anthropic_merges_consecutive_same_role_messages
        messages = [
          Message.new(role: :user, content: "Hello!"),
          Message.new(role: :user, content: "Another message."),
          Message.new(role: :assistant, content: "Hi!"),
        ]
        result = Dialects.convert(messages, dialect: :anthropic)

        assert_equal 2, result[:messages].length
        assert_equal "user", result[:messages][0][:role]
        assert_equal 2, result[:messages][0][:content].length
        assert_equal "Hello!", result[:messages][0][:content][0][:text]
        assert_equal "Another message.", result[:messages][0][:content][1][:text]
      end

      def test_anthropic_adds_placeholder_for_empty_messages
        messages = [
          Message.new(role: :system, content: "System prompt."),
        ]
        result = Dialects.convert(messages, dialect: :anthropic)

        assert_equal 1, result[:system].length
        assert_equal 1, result[:messages].length
        assert_equal "user", result[:messages][0][:role]
        assert_equal Dialects::PLACEHOLDER, result[:messages][0][:content][0][:text]
      end

      def test_anthropic_prepends_name_to_content
        messages = [
          Message.new(role: :user, content: "Hello!", name: "Alice"),
        ]
        result = Dialects.convert(messages, dialect: :anthropic)

        assert_equal "Alice: Hello!", result[:messages][0][:content][0][:text]
        refute result[:messages][0].key?(:name)
      end

      def test_anthropic_uses_zero_width_space_for_empty_content
        messages = [
          Message.new(role: :user, content: ""),
        ]
        result = Dialects.convert(messages, dialect: :anthropic)

        assert_equal "\u200b", result[:messages][0][:content][0][:text]
      end

      # --- Text Dialect ---

      def test_text_returns_hash_with_prompt_and_stop_sequences
        result = Dialects.convert(@messages, dialect: :text)

        assert_kind_of Hash, result
        assert result.key?(:prompt)
        assert result.key?(:stop_sequences)
        assert_kind_of String, result[:prompt]
        assert_kind_of Array, result[:stop_sequences]
      end

      def test_text_ends_with_assistant_prompt
        result = Dialects.convert(@messages, dialect: :text)

        assert result[:prompt].end_with?("assistant:")
      end

      def test_text_formats_roles_correctly
        result = Dialects.convert(@messages, dialect: :text)

        lines = result[:prompt].split("\n")
        assert lines[0].start_with?("System:")
        assert lines[1].start_with?("System:")
        assert lines[2].start_with?("user:")
        assert lines[3].start_with?("assistant:")
        assert lines[4].start_with?("user:")
      end

      def test_text_uses_name_for_system_messages_with_name
        messages = [
          Message.new(role: :system, content: "Hello!", name: "Narrator"),
          Message.new(role: :system, content: "More info."),
        ]
        result = Dialects.convert(messages, dialect: :text)

        lines = result[:prompt].split("\n")
        assert lines[0].start_with?("Narrator:")
        assert lines[1].start_with?("System:")
      end

      # --- Additional ST-inspired Dialects ---

      def test_cohere_returns_hash_with_chat_history_and_prefixes_example_names
        messages = [
          Message.new(role: :system, content: "Example user line", name: "example_user"),
          Message.new(role: :user, content: "Hello"),
        ]

        result = Dialects.convert(messages, dialect: :cohere, names: { user_name: "Bob", char_name: "Alice" })

        assert_kind_of Hash, result
        assert result.key?(:chat_history)
        assert_equal "Bob: Example user line", result[:chat_history][0][:content]
        refute result[:chat_history][0].key?(:name)
      end

      def test_google_returns_contents_and_system_instruction
        messages = [
          Message.new(role: :system, content: "SYS"),
          Message.new(role: :user, content: "Hi"),
          Message.new(role: :assistant, content: "Hello"),
        ]

        result = Dialects.convert(messages, dialect: :google, model: "gemini-2.0", use_sys_prompt: true)

        assert_kind_of Hash, result
        assert_kind_of Array, result[:system_instruction][:parts]
        assert_equal({ text: "SYS" }, result[:system_instruction][:parts][0])
        assert_equal "user", result[:contents][0][:role]
        assert_equal "model", result[:contents][1][:role]
      end

      def test_ai21_squashes_leading_system_and_merges_consecutive_roles
        messages = [
          Message.new(role: :system, content: "S1"),
          Message.new(role: :system, content: "S2"),
          Message.new(role: :user, content: "U1"),
          Message.new(role: :user, content: "U2"),
        ]

        result = Dialects.convert(messages, dialect: :ai21)

        assert_kind_of Array, result
        assert_equal "system", result[0][:role]
        assert_equal "S1\n\nS2", result[0][:content]

        user_msg = result.find { |m| m[:role] == "user" }
        refute_nil user_msg
        assert_equal "U1\n\nU2", user_msg[:content]
      end

      def test_mistral_enable_prefix_marks_last_assistant
        messages = [
          Message.new(role: :user, content: "Hi"),
          Message.new(role: :assistant, content: "Hello"),
        ]

        result = Dialects.convert(messages, dialect: :mistral, enable_prefix: true)

        assert_equal true, result.last[:prefix]
      end

      def test_xai_prefixes_assistant_with_character_name_and_removes_name_field
        messages = [
          Message.new(role: :assistant, content: "Hello there", name: "example_assistant"),
        ]

        result = Dialects.convert(messages, dialect: :xai, names: { char_name: "Alice" })

        assert_equal "Alice: Hello there", result[0][:content]
        refute result[0].key?(:name)
      end

      # --- Error Handling ---

      def test_raises_for_unknown_dialect
        error = assert_raises(ArgumentError) do
          Dialects.convert(@messages, dialect: :unknown)
        end

        assert_match(/Unknown dialect/, error.message)
        assert_match(/:unknown/, error.message)
      end

      def test_accepts_string_dialect
        result = Dialects.convert(@messages, dialect: "openai")

        assert_kind_of Array, result
      end

      # --- Integration with Plan ---

      def test_plan_to_messages_uses_dialects
        blocks = [
          Block.new(role: :system, content: "System prompt."),
          Block.new(role: :user, content: "Hello!"),
        ]
        plan = Plan.new(blocks: blocks)

        openai_result = plan.to_messages(dialect: :openai)
        anthropic_result = plan.to_messages(dialect: :anthropic)
        text_result = plan.to_messages(dialect: :text)

        assert_kind_of Array, openai_result
        assert_kind_of Hash, anthropic_result
        assert_kind_of Hash, text_result
        assert text_result.key?(:prompt)
        assert text_result.key?(:stop_sequences)
      end

      def test_plan_to_messages_defaults_to_openai
        blocks = [
          Block.new(role: :system, content: "System prompt."),
        ]
        plan = Plan.new(blocks: blocks)

        result = plan.to_messages

        assert_kind_of Array, result
        assert_equal({ role: "system", content: "System prompt." }, result[0])
      end

      def test_plan_to_messages_still_works
        blocks = [
          Block.new(role: :system, content: "System prompt."),
        ]
        plan = Plan.new(blocks: blocks)

        result = plan.to_messages

        assert_kind_of Array, result
        assert_equal({ role: "system", content: "System prompt." }, result[0])
      end

      def test_plan_to_messages_squashes_consecutive_system_messages_for_openai
        blocks = [
          Block.new(role: :system, content: "S1"),
          Block.new(role: :system, content: "S2"),
          Block.new(role: :user, content: "U1"),
          Block.new(role: :system, content: "S3"),
        ]
        plan = Plan.new(blocks: blocks)

        result = plan.to_messages(dialect: :openai, squash_system_messages: true)

        assert_equal 3, result.length
        assert_equal "system", result[0][:role]
        assert_equal "S1\nS2", result[0][:content]
        assert_equal "user", result[1][:role]
        assert_equal "U1", result[1][:content]
        assert_equal "S3", result[2][:content]
      end

      def test_plan_to_messages_squash_does_not_merge_named_system_messages
        blocks = [
          Block.new(role: :system, content: "S1"),
          Block.new(role: :system, content: "NAMED", name: "example_user"),
          Block.new(role: :system, content: "S2"),
        ]
        plan = Plan.new(blocks: blocks)

        result = plan.to_messages(dialect: :openai, squash_system_messages: true)
        system_contents = result.select { |m| m[:role] == "system" }.map { |m| m[:content] }

        assert_equal ["S1", "NAMED", "S2"], system_contents
        assert_equal "example_user", result[1][:name]
      end

      def test_plan_to_messages_squash_excludes_new_chat_and_new_example_chat_slots
        blocks = [
          Block.new(role: :system, content: "NEW_CHAT", slot: :new_chat_prompt),
          Block.new(role: :system, content: "MAIN", slot: :main_prompt),
          Block.new(role: :system, content: "PERSONA", slot: :persona),
          Block.new(role: :system, content: "EXAMPLE", slot: :new_example_chat),
        ]
        plan = Plan.new(blocks: blocks)

        result = plan.to_messages(dialect: :openai, squash_system_messages: true)
        contents = result.map { |m| m[:content] }

        # new_chat_prompt should not be merged with MAIN
        assert_equal "NEW_CHAT", contents[0]
        # new_example_chat should remain separate
        assert_includes contents, "EXAMPLE"
        # MAIN and PERSONA should squash (adjacent squashable system messages)
        assert_includes contents, "MAIN\nPERSONA"
      end

      def test_plan_to_messages_squash_drops_empty_system_messages
        blocks = [
          Block.new(role: :system, content: ""),
          Block.new(role: :system, content: "S1"),
        ]
        plan = Plan.new(blocks: blocks)

        result = plan.to_messages(dialect: :openai, squash_system_messages: true)

        assert_equal 1, result.length
        assert_equal "S1", result[0][:content]
      end
    end
  end
end
