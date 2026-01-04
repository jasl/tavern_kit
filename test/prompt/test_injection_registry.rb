# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Prompt
    class TestInjectionRegistry < Minitest::Test
      def setup
        @user = User.new(name: "Bob", persona: "Persona")
        @character = CharacterCard.load(
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
            },
          }
        )
      end

      def test_overlapping_id_replaces_previous_injection
        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "")
        registry = InjectionRegistry.new
        registry.register(id: "x", content: "FIRST", position: :after)
        registry.register(id: "x", content: "SECOND", position: :after)

        plan = TavernKit.build(
          character: @character,
          user: @user,
          preset: preset,
          injection_registry: registry,
          message: "Hello"
        )
        all = plan.to_messages.map { |m| m[:content] }.join("\n")

        assert_includes all, "SECOND"
        refute_includes all, "FIRST"
      end

      def test_before_and_after_injections_are_in_main_prompt_region_before_chat_history
        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "")
        registry = InjectionRegistry.new
        registry.register(id: "b", content: "BEFORE_INJ", position: :before, role: :user)
        registry.register(id: "a", content: "AFTER_INJ", position: :after, role: :assistant)

        plan = TavernKit.build(
          character: @character,
          user: @user,
          preset: preset,
          injection_registry: registry,
          message: "Hello"
        )
        blocks = plan.blocks

        before_idx = blocks.index { |b| b.metadata[:injection_id] == "b" }
        after_idx = blocks.index { |b| b.metadata[:injection_id] == "a" }
        user_msg_idx = blocks.index { |b| b.slot == :user_message && b.content == "Hello" }

        refute_nil before_idx
        refute_nil after_idx
        refute_nil user_msg_idx

        assert_equal 0, before_idx, "BEFORE_PROMPT injection should be placed at the start of the plan"
        assert after_idx < user_msg_idx, "IN_PROMPT injection should be placed before chat history"
        assert_equal :user, blocks[before_idx].role
        assert_equal :assistant, blocks[after_idx].role
      end

      def test_chat_injection_inserts_at_depth_with_role
        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "")
        history = ChatHistory.wrap([
          Message.new(role: :user, content: "U1"),
          Message.new(role: :assistant, content: "A1"),
        ])
        registry = InjectionRegistry.new
        registry.register(id: "c", content: "CHAT_INJ", position: :chat, depth: 1, role: :user)

        plan = TavernKit.build(
          character: @character,
          user: @user,
          preset: preset,
          history: history,
          injection_registry: registry,
          message: "U2"
        )
        blocks = plan.blocks

        inj_idx = blocks.index { |b| b.metadata[:injection_id] == "c" && b.in_chat? }
        user_msg_idx = blocks.index { |b| b.slot == :user_message && b.content == "U2" }

        refute_nil inj_idx
        refute_nil user_msg_idx

        assert_equal :user, blocks[inj_idx].role
        assert_equal 1, blocks[inj_idx].depth
        assert inj_idx < user_msg_idx, "depth=1 should insert before the most recent message (current user message)"
      end

      def test_scan_true_can_trigger_world_info_even_when_position_none
        keyword = "scan_keyword_123"
        card = CharacterCard.load(
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
              "character_book" => {
                "scan_depth" => 10,
                "token_budget" => 1000,
                "entries" => [
                  {
                    "uid" => "wi1",
                    "keys" => [keyword],
                    "content" => "WI_TRIGGERED",
                    "enabled" => true,
                    "position" => "after_char_defs",
                  },
                ],
              },
            },
          }
        )

        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "")
        registry = InjectionRegistry.new
        registry.register(id: "scan", content: keyword, position: :none, scan: true)

        plan = TavernKit.build(
          character: card,
          user: @user,
          preset: preset,
          injection_registry: registry,
          message: "hello there"
        )
        all = plan.to_messages.map { |m| m[:content] }.join("\n")

        assert_includes all, "WI_TRIGGERED"
        refute_includes all, keyword, "hidden scan injection should not be emitted into the prompt"
      end

      def test_filter_skips_injection_for_both_prompt_and_scan
        keyword = "scan_keyword_456"
        card = CharacterCard.load(
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
              "character_book" => {
                "scan_depth" => 10,
                "token_budget" => 1000,
                "entries" => [
                  {
                    "uid" => "wi2",
                    "keys" => [keyword],
                    "content" => "WI_SHOULD_NOT_TRIGGER",
                    "enabled" => true,
                    "position" => "after_char_defs",
                  },
                ],
              },
            },
          }
        )

        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "")
        registry = InjectionRegistry.new
        registry.register(
          id: "f",
          content: keyword,
          position: :after,
          scan: true,
          filter: ->(_ctx) { false },
        )

        plan = TavernKit.build(
          character: card,
          user: @user,
          preset: preset,
          injection_registry: registry,
          message: "hello there"
        )
        all = plan.to_messages.map { |m| m[:content] }.join("\n")

        refute_includes all, keyword
        refute_includes all, "WI_SHOULD_NOT_TRIGGER"
      end

      def test_ephemeral_injection_is_removed_after_build
        preset = Preset.new(main_prompt: "MAIN", post_history_instructions: "")
        registry = InjectionRegistry.new
        registry.register(id: "e", content: "EPH", position: :after, ephemeral: true)

        plan = TavernKit.build(
          character: @character,
          user: @user,
          preset: preset,
          injection_registry: registry,
          message: "Hello"
        )
        all = plan.to_messages.map { |m| m[:content] }.join("\n")

        assert_includes all, "EPH"
        assert_nil registry["e"], "ephemeral injection should be pruned after build"
      end
    end
  end
end
