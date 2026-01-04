# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Prompt
    class TestUnknownPinnedFallback < Minitest::Test
      def setup
        @character = Character.create(name: "TestChar")
        @user = User.new(name: "TestUser")
      end

      def test_unknown_pinned_with_content_falls_back_to_custom_without_warning
        entries = [
          PromptEntry.new(id: "main_prompt", pinned: true, role: :system),
          PromptEntry.new(
            id: "future_marker",
            pinned: true,
            role: :system,
            position: :relative,
            content: "FUTURE CONTENT",
          ),
        ]

        preset = Preset.new(
          main_prompt: "MAIN",
          prompt_entries: entries,
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")

        assert_equal [], plan.warnings

        custom_blocks = plan.blocks.select do |b|
          b.slot == :custom_prompt && b.metadata[:prompt_entry_id] == "future_marker"
        end

        assert_equal 1, custom_blocks.size
        assert_equal "FUTURE CONTENT", custom_blocks.first.content
      end

      def test_unknown_marker_only_pinned_emits_warning_and_is_ignored
        entries = [
          PromptEntry.new(id: "main_prompt", pinned: true, role: :system),
          PromptEntry.new(
            id: "future_marker",
            pinned: true,
            role: :system,
            position: :relative,
            content: nil,
          ),
        ]

        preset = Preset.new(
          main_prompt: "MAIN",
          prompt_entries: entries,
        )

        plan = nil
        assert_output(nil, /WARN: Unknown pinned prompt/) do
          plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")
        end

        refute_nil plan
        assert_equal 1, plan.warnings.size
        assert_match(/Unknown pinned prompt/, plan.warnings.first)

        refute plan.blocks.any? { |b| b.metadata[:prompt_entry_id] == "future_marker" }
      end

      def test_strict_mode_turns_unknown_marker_only_warning_into_exception
        entries = [
          PromptEntry.new(id: "main_prompt", pinned: true, role: :system),
          PromptEntry.new(id: "future_marker", pinned: true, role: :system),
        ]

        preset = Preset.new(
          main_prompt: "MAIN",
          prompt_entries: entries,
        )

        err = assert_raises(TavernKit::StrictModeError) do
          TavernKit.build(character: @character, user: @user, preset: preset, strict: true, message: "Hello")
        end

        assert_match(/Unknown pinned prompt/, err.message)
      end

      def test_resolver_provides_pinned_group_without_warning
        called = []
        resolver = lambda do |id:, **_kwargs|
          called << id
          return nil unless id == "future_marker"

          [
            Block.new(
              role: :system,
              content: "RESOLVED GROUP",
              slot: :custom_prompt,
              insertion_point: :relative,
              token_budget_group: :custom,
            ),
          ]
        end

        entries = [
          PromptEntry.new(id: "main_prompt", pinned: true, role: :system),
          PromptEntry.new(
            id: "future_marker",
            pinned: true,
            role: :assistant, # should override resolved block role
            position: :relative,
            content: nil,
          ),
        ]

        preset = Preset.new(
          main_prompt: "MAIN",
          prompt_entries: entries,
          pinned_group_resolver: resolver,
        )

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")

        assert_includes called, "future_marker"
        assert_equal [], plan.warnings

        resolved = plan.blocks.find { |b| b.content == "RESOLVED GROUP" }
        refute_nil resolved
        assert_equal :assistant, resolved.role
      end
    end
  end
end
