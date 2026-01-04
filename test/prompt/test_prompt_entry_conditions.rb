# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Prompt
    class TestPromptEntryConditions < Minitest::Test
      def setup
        @character = Character.create(name: "Alice", mes_example: "")
        @user = User.new(name: "Bob", persona: "A wandering wizard")
      end

      def test_chat_keyword_match_uses_default_depth
        history = ChatHistory.wrap([
          Message.new(role: :user, content: "Old message"),
          Message.new(role: :assistant, content: "I saw a DRAGON"),
        ])

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prefer_char_prompt: false,
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            {
              "id" => "cond_chat",
              "content" => "COND_CHAT",
              "role" => "system",
              "position" => "relative",
              "conditions" => { "chat" => { "any" => ["dragon"] } },
            },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Hi")
        contents = plan.to_messages.map { |m| m[:content] }

        assert_includes contents, "COND_CHAT"
      end

      def test_chat_keyword_match_respects_depth_override
        history = ChatHistory.wrap([
          Message.new(role: :user, content: "dragon appears"),
          Message.new(role: :assistant, content: "ok"),
          Message.new(role: :user, content: "later"),
        ])

        # Default depth (2) scans only current + last history message => should NOT see "dragon".
        preset_default_depth = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prefer_char_prompt: false,
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            {
              "id" => "cond_default_depth",
              "content" => "COND_DEFAULT_DEPTH",
              "role" => "system",
              "position" => "relative",
              "conditions" => { "chat" => { "any" => ["dragon"] } },
            },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| PromptEntry.from_hash(h) },
        )

        plan1 = TavernKit.build(character: @character, user: @user, preset: preset_default_depth, history: history, message: "now")
        contents1 = plan1.to_messages.map { |m| m[:content] }
        refute_includes contents1, "COND_DEFAULT_DEPTH"

        # Depth override (4) includes the older message containing "dragon".
        preset_depth_4 = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prefer_char_prompt: false,
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            {
              "id" => "cond_depth_4",
              "content" => "COND_DEPTH_4",
              "role" => "system",
              "position" => "relative",
              "conditions" => { "chat" => { "any" => ["dragon"], "depth" => 4 } },
            },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| PromptEntry.from_hash(h) },
        )

        plan2 = TavernKit.build(character: @character, user: @user, preset: preset_depth_4, history: history, message: "now")
        contents2 = plan2.to_messages.map { |m| m[:content] }
        assert_includes contents2, "COND_DEPTH_4"
      end

      def test_chat_js_regex_literal_matches
        history = ChatHistory.wrap([
          Message.new(role: :assistant, content: "DRAGONS everywhere"),
        ])

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prefer_char_prompt: false,
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            {
              "id" => "cond_regex",
              "content" => "COND_REGEX",
              "role" => "system",
              "position" => "relative",
              "conditions" => { "chat" => { "any" => ["/dragons/i"] } },
            },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "hi")
        contents = plan.to_messages.map { |m| m[:content] }
        assert_includes contents, "COND_REGEX"
      end

      def test_turn_count_conditions
        history = ChatHistory.wrap([
          Message.new(role: :user, content: "U1"),
          Message.new(role: :assistant, content: "A1"),
          Message.new(role: :user, content: "U2"),
          Message.new(role: :assistant, content: "A2"),
        ])

        # turn_count = 2 (history user msgs) + 1 (current) = 3
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prefer_char_prompt: false,
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            {
              "id" => "cond_turns_min",
              "content" => "COND_TURNS_MIN",
              "role" => "system",
              "position" => "relative",
              "conditions" => { "turns" => { "min" => 3 } },
            },
            {
              "id" => "cond_turns_every",
              "content" => "COND_TURNS_EVERY",
              "role" => "system",
              "position" => "relative",
              "conditions" => { "turns" => { "every" => 2 } },
            },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "U3")
        contents = plan.to_messages.map { |m| m[:content] }

        assert_includes contents, "COND_TURNS_MIN"
        refute_includes contents, "COND_TURNS_EVERY"
      end

      def test_user_and_character_attribute_conditions
        character = Character.create(name: "Alice", mes_example: "", tags: ["Magic", "Elf"])

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prefer_char_prompt: false,
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            {
              "id" => "cond_attrs",
              "content" => "COND_ATTRS",
              "role" => "system",
              "position" => "relative",
              "conditions" => {
                "character" => { "tags_any" => ["magic"] },
                "user" => { "persona" => "wizard" },
              },
            },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset, message: "Hi")
        contents = plan.to_messages.map { |m| m[:content] }

        assert_includes contents, "COND_ATTRS"
      end

      def test_continue_does_not_append_when_chat_history_entry_is_disabled
        history = ChatHistory.wrap([
          Message.new(role: :user, content: "Hi"),
          Message.new(role: :assistant, content: "Hello"),
        ])

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prefer_char_prompt: false,
          continue_nudge_prompt: "NUDGE {{lastChatMessage}}",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true, "enabled" => false },
          ].map { |h| PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(
          character: @character,
          user: @user,
          preset: preset,
          history: history,
          generation_type: :continue,
          message: ""
        )

        contents = plan.to_messages.map { |m| m[:content] }
        refute_includes contents, "Hello"
        refute_includes contents, "NUDGE Hello"
      end
    end
  end
end
