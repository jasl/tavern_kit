# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Prompt
    class TestHooks < Minitest::Test
      def setup
        @character = CharacterCard.load(File.expand_path("../fixtures/seraphina.v2.json", __dir__))
      end

      def test_before_build_can_modify_user_message
        user = User.new(name: "You")
        preset = Preset.new(main_prompt: "System prompt", prefer_char_prompt: false, post_history_instructions: "")

        original = "INPUT_ORIG_123"
        overridden = "INPUT_NEW_456"

        plan = TavernKit.build(character: @character, user: user, preset: preset) do
          before_build do |ctx|
            ctx.user_message = overridden
          end
          message original
        end

        contents = plan.to_messages.map { |m| m[:content] }
        assert_includes contents, overridden
        refute_includes contents, original
      end

      def test_after_build_can_insert_blocks
        user = User.new(name: "You")
        preset = Preset.new(main_prompt: "System prompt", prefer_char_prompt: false, post_history_instructions: "")

        plan = TavernKit.build(character: @character, user: user, preset: preset) do
          after_build do |ctx|
            ctx.plan.blocks.unshift(
              Block.new(
                role: :system,
                content: "HOOKED",
                slot: :custom,
                token_budget_group: :custom,
              )
            )
          end
          message "Hello"
        end

        assert_equal "HOOKED", plan.messages.first.content
      end

      def test_hooks_run_in_registration_order
        user = User.new(name: "You")
        preset = Preset.new(main_prompt: "System prompt", prefer_char_prompt: false, post_history_instructions: "")

        calls = []

        TavernKit.build(character: @character, user: user, preset: preset) do
          before_build { |_ctx| calls << :a }
          before_build { |_ctx| calls << :b }
          message "Hello"
        end

        assert_equal %i[a b], calls
      end
    end
  end
end
