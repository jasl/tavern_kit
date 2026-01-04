# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Prompt
    class TestPromptEntries < Minitest::Test
      def setup
        @character = CharacterCard.load(File.expand_path("../fixtures/seraphina.v2.json", __dir__))
      end

      def test_supports_custom_relative_and_in_chat_prompt_entries
        user = User.new(name: "You")

        preset = Preset.new(
          main_prompt: "GLOBAL MAIN",
          prefer_char_prompt: false,
          post_history_instructions: "GLOBAL PHI",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "world_info_before_char_defs", "pinned" => true },
            { "id" => "persona_description", "pinned" => true },
            { "id" => "character_description", "pinned" => true },
            { "id" => "character_personality", "pinned" => true },
            { "id" => "scenario", "pinned" => true },
            { "id" => "world_info_after_char_defs", "pinned" => true },
            { "id" => "chat_examples", "pinned" => true },
            { "id" => "authors_note", "pinned" => true },
            # Custom relative prompt just before the chat history
            { "id" => "custom_rel", "content" => "RELATIVE", "role" => "system", "position" => "relative" },
            { "id" => "chat_history", "pinned" => true },
            # In-chat prompts (ignore drag order)
            { "id" => "in_chat_user", "content" => "INCHAT USER", "role" => "user", "position" => "in_chat", "depth" => 0, "order" => 10 },
            { "id" => "in_chat_system", "content" => "INCHAT SYSTEM", "role" => "system", "position" => "in_chat", "depth" => 0, "order" => 5 },
            { "id" => "post_history_instructions", "pinned" => true },
          ].map { |h| PromptEntry.from_hash(h) }
        )

        history = ChatHistory.wrap([
          Message.new(role: :user, content: "First"),
          Message.new(role: :assistant, content: "Second"),
        ])

        plan = TavernKit.build(character: @character, user: user, preset: preset, history: history, message: "Third")

        # Relative custom prompt should exist as a system message.
        assert plan.messages.any? { |m| m.role == :system && m.content == "RELATIVE" }

        # In-chat prompts should be after the last chat message ("Third") and before PHI.
        last_user_index = plan.messages.rindex { |m| m.role == :user && m.content == "Third" }
        refute_nil last_user_index

        # In-chat ordering is governed by injection_order (lower first), then role ordering within the group.
        assert_equal "INCHAT SYSTEM", plan.messages[last_user_index + 1].content
        assert_equal :system, plan.messages[last_user_index + 1].role

        assert_equal "INCHAT USER", plan.messages[last_user_index + 2].content
        assert_equal :user, plan.messages[last_user_index + 2].role

        # Card PHI is always last.
        assert_equal :system, plan.messages.last.role
        assert_equal "Stay in character as Seraphina.", plan.messages.last.content
      end
    end
  end
end
