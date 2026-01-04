# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Prompt
    class TestBuilderGenerationType < Minitest::Test
      def setup
        @character = Character.create(
          name: "TestChar",
          description: "A test character"
        )
        @user = User.new(name: "TestUser")
        @preset = Preset.new(
          main_prompt: "System prompt",
          post_history_instructions: ""
        )
      end

      def test_default_generation_type_is_normal
        # Verify default generation_type is :normal by checking which entries are triggered
        preset_with_entry = Preset.new(
          main_prompt: "System",
          post_history_instructions: "",
          prompt_entries: [
            {
              id: "normal_entry",
              enabled: true,
              pinned: false,
              position: :relative,
              content: "NORMAL_ONLY_CONTENT",
              triggers: ["normal"],
            },
            {
              id: "continue_entry",
              enabled: true,
              pinned: false,
              position: :relative,
              content: "CONTINUE_ONLY_CONTENT",
              triggers: ["continue"],
            },
          ].map { |h| PromptEntry.from_hash(h) }
        )

        plan = TavernKit.build(
          character: @character,
          user: @user,
          preset: preset_with_entry,
          message: "Hello"
        )

        content = plan.blocks.map(&:content).join("\n")
        assert_includes content, "NORMAL_ONLY_CONTENT"
        refute_includes content, "CONTINUE_ONLY_CONTENT"
      end

      def test_generation_type_constructor_param
        preset_with_entry = Preset.new(
          main_prompt: "System",
          post_history_instructions: "",
          prompt_entries: [
            {
              id: "normal_entry",
              enabled: true,
              pinned: false,
              position: :relative,
              content: "NORMAL_CONTENT",
              triggers: ["normal"],
            },
            {
              id: "continue_entry",
              enabled: true,
              pinned: false,
              position: :relative,
              content: "CONTINUE_CONTENT",
              triggers: ["continue"],
            },
          ].map { |h| PromptEntry.from_hash(h) }
        )

        plan = TavernKit.build(
          character: @character,
          user: @user,
          preset: preset_with_entry,
          generation_type: :continue,
          message: "Hello"
        )

        content = plan.blocks.map(&:content).join("\n")
        refute_includes content, "NORMAL_CONTENT"
        assert_includes content, "CONTINUE_CONTENT"
      end

      def test_generation_type_dsl_style
        preset_with_entry = Preset.new(
          main_prompt: "System",
          post_history_instructions: "",
          prompt_entries: [
            {
              id: "swipe_entry",
              enabled: true,
              pinned: false,
              position: :relative,
              content: "SWIPE_CONTENT",
              triggers: ["swipe"],
            },
          ].map { |h| PromptEntry.from_hash(h) }
        )

        plan = TavernKit.build(
          character: @character,
          user: @user,
          preset: preset_with_entry,
          generation_type: :swipe,
          message: "Hello"
        )

        content = plan.blocks.map(&:content).join("\n")
        assert_includes content, "SWIPE_CONTENT"
      end

      def test_string_generation_type_is_coerced
        preset_with_entry = Preset.new(
          main_prompt: "System",
          post_history_instructions: "",
          prompt_entries: [
            {
              id: "impersonate_entry",
              enabled: true,
              pinned: false,
              position: :relative,
              content: "IMPERSONATE_CONTENT",
              triggers: ["impersonate"],
            },
          ].map { |h| PromptEntry.from_hash(h) }
        )

        # String generation types are automatically coerced to symbols
        plan = TavernKit.build(
          character: @character,
          user: @user,
          preset: preset_with_entry,
          generation_type: "impersonate",
          message: "Hello"
        )
        # Verify the plan was built successfully with the entry that triggers on impersonate
        assert plan.messages.any? { |m| m.content.include?("IMPERSONATE_CONTENT") }
      end

      def test_empty_triggers_matches_all_generation_types
        preset_with_entry = Preset.new(
          main_prompt: "System",
          post_history_instructions: "",
          prompt_entries: [
            {
              id: "universal_entry",
              enabled: true,
              pinned: false,
              position: :relative,
              content: "UNIVERSAL_CONTENT",
              triggers: [],
            },
          ].map { |h| PromptEntry.from_hash(h) }
        )

        TavernKit::GENERATION_TYPES.each do |gen_type|
          plan = TavernKit.build(
            character: @character,
            user: @user,
            preset: preset_with_entry,
            generation_type: gen_type,
            message: "Hello"
          )

          content = plan.blocks.map(&:content).join("\n")
          assert_includes content, "UNIVERSAL_CONTENT",
                         "Entry with empty triggers should be included for #{gen_type}"
        end
      end
    end
  end
end
