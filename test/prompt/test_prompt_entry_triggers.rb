# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Prompt
    class TestPromptEntryTriggers < Minitest::Test
      def test_triggers_default_to_empty_array
        entry = PromptEntry.new(id: "test")

        assert_equal [], entry.triggers
      end

      def test_triggers_normalized_to_symbols
        entry = PromptEntry.from_hash(
          id: "test",
          triggers: ["normal", "continue", "IMPERSONATE"],
        )

        assert_equal %i[normal continue impersonate], entry.triggers
      end

      def test_triggers_filters_invalid_values
        # Invalid trigger values are silently filtered out
        entry = PromptEntry.from_hash(
          id: "test",
          triggers: ["normal", "invalid_type", "continue", "", "unknown"],
        )
        # Only valid triggers remain
        assert_equal %i[normal continue], entry.triggers
      end

      def test_triggered_by_returns_true_for_empty_triggers
        entry = PromptEntry.new(id: "test", triggers: [])

        assert entry.triggered_by?(:normal)
        assert entry.triggered_by?(:continue)
        assert entry.triggered_by?(:impersonate)
        assert entry.triggered_by?(:swipe)
        assert entry.triggered_by?(:regenerate)
        assert entry.triggered_by?(:quiet)
      end

      def test_triggered_by_returns_true_for_matching_type
        entry = PromptEntry.new(
          id: "test",
          triggers: [:normal, :continue]
        )

        assert entry.triggered_by?(:normal)
        assert entry.triggered_by?(:continue)
        refute entry.triggered_by?(:impersonate)
        refute entry.triggered_by?(:swipe)
      end

      def test_triggered_by_accepts_string_input
        entry = PromptEntry.new(
          id: "test",
          triggers: [:normal]
        )

        # Strings are automatically coerced to symbols
        assert entry.triggered_by?("normal")
      end

      def test_triggered_by_treats_nil_as_normal
        entry = PromptEntry.new(
          id: "test",
          triggers: [:normal]
        )

        assert entry.triggered_by?(nil)

        entry_no_normal = PromptEntry.new(
          id: "test2",
          triggers: [:continue]
        )

        refute entry_no_normal.triggered_by?(nil)
      end

      def test_from_hash_parses_triggers
        hash = {
          id: "test",
          triggers: ["normal", "swipe"],
        }

        entry = PromptEntry.from_hash(hash)

        assert_equal %i[normal swipe], entry.triggers
      end

      def test_from_hash_parses_injection_trigger
        # SillyTavern uses injection_trigger
        hash = {
          id: "test",
          injection_trigger: ["continue", "regenerate"],
        }

        entry = PromptEntry.from_hash(hash)

        assert_equal %i[continue regenerate], entry.triggers
      end

      def test_from_hash_prefers_triggers_over_injection_trigger
        hash = {
          id: "test",
          triggers: ["normal"],
          injection_trigger: ["continue"],
        }

        entry = PromptEntry.from_hash(hash)

        assert_equal %i[normal], entry.triggers
      end

      # P0-4: ST exports injection_trigger as numeric codes
      def test_from_hash_parses_numeric_injection_trigger
        # SillyTavern exports triggers as numeric codes: 0=normal, 1=continue, etc.
        hash = {
          id: "test",
          injection_trigger: [0, 1],
        }

        entry = PromptEntry.from_hash(hash)

        assert_equal %i[normal continue], entry.triggers
      end

      def test_from_hash_parses_mixed_trigger_formats
        # Mixed numeric codes and string names
        hash = {
          id: "test",
          triggers: [0, "continue", 2, "swipe"],
        }

        entry = PromptEntry.from_hash(hash)

        # Should dedupe: 0=normal, "continue", 2=impersonate, "swipe"
        assert_equal %i[normal continue impersonate swipe], entry.triggers
      end

      def test_numeric_string_triggers
        # Numeric strings like "0", "1" should be parsed as codes
        hash = {
          id: "test",
          triggers: ["0", "1", "5"],
        }

        entry = PromptEntry.from_hash(hash)

        assert_equal %i[normal continue quiet], entry.triggers
      end

      def test_invalid_numeric_triggers_filtered
        hash = {
          id: "test",
          triggers: [0, 99, 1, -1, 100],
        }

        # Invalid numeric codes are silently filtered out
        entry = PromptEntry.from_hash(hash)
        # 0 -> :normal, 1 -> :continue are valid
        assert_equal %i[normal continue], entry.triggers
      end

      def test_to_h_includes_triggers
        entry = PromptEntry.new(
          id: "test",
          triggers: [:normal, :continue]
        )

        hash = entry.to_h

        assert_equal %i[normal continue], hash[:triggers]
      end

      def test_all_generation_types
        entry = PromptEntry.new(
          id: "test",
          triggers: TavernKit::GENERATION_TYPES
        )

        assert_equal TavernKit::GENERATION_TYPES, entry.triggers
        TavernKit::GENERATION_TYPES.each do |type|
          assert entry.triggered_by?(type)
        end
      end
    end
  end
end
