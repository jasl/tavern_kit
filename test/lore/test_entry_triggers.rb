# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Lore
    class TestEntryTriggers < Minitest::Test
      def test_triggers_default_to_empty_array
        entry = Entry.new(uid: "test", keys: ["key"], content: "content")

        assert_equal [], entry.triggers
      end

      def test_triggers_normalized_to_symbols
        entry = Entry.from_hash(
          {
            uid: "test",
            keys: ["key"],
            content: "content",
            triggers: ["normal", "continue", "IMPERSONATE"],
          }
        )

        assert_equal %i[normal continue impersonate], entry.triggers
      end

      def test_triggers_filters_invalid_values
        # Invalid trigger values are silently filtered out
        entry = Entry.from_hash(
          {
            uid: "test",
            keys: ["key"],
            content: "content",
            triggers: ["normal", "invalid_type", "continue", "", "unknown"],
          }
        )
        # Only valid triggers remain
        assert_equal %i[normal continue], entry.triggers
      end

      def test_triggered_by_returns_true_for_empty_triggers
        entry = Entry.new(uid: "test", keys: ["key"], content: "content", triggers: [])

        assert entry.triggered_by?(:normal)
        assert entry.triggered_by?(:continue)
        assert entry.triggered_by?(:impersonate)
        assert entry.triggered_by?(:swipe)
        assert entry.triggered_by?(:regenerate)
        assert entry.triggered_by?(:quiet)
      end

      def test_triggered_by_returns_true_for_matching_type
        entry = Entry.new(
          uid: "test",
          keys: ["key"],
          content: "content",
          triggers: [:normal, :continue]
        )

        assert entry.triggered_by?(:normal)
        assert entry.triggered_by?(:continue)
        refute entry.triggered_by?(:impersonate)
        refute entry.triggered_by?(:swipe)
      end

      def test_triggered_by_accepts_string_input
        entry = Entry.new(
          uid: "test",
          keys: ["key"],
          content: "content",
          triggers: [:normal]
        )

        # Strings are automatically coerced to symbols
        assert entry.triggered_by?("normal")
        assert entry.triggered_by?("NORMAL")
        refute entry.triggered_by?("continue")
      end

      def test_triggered_by_treats_nil_as_normal
        entry = Entry.new(
          uid: "test",
          keys: ["key"],
          content: "content",
          triggers: [:normal]
        )

        assert entry.triggered_by?(nil)

        entry_no_normal = Entry.new(
          uid: "test2",
          keys: ["key"],
          content: "content",
          triggers: [:continue]
        )

        refute entry_no_normal.triggered_by?(nil)
      end

      def test_from_hash_parses_triggers
        hash = {
          uid: "test",
          keys: ["key"],
          content: "content",
          triggers: ["normal", "swipe"],
        }

        entry = Entry.from_hash(hash)

        assert_equal %i[normal swipe], entry.triggers
      end

      def test_from_hash_parses_triggers_from_extensions
        hash = {
          uid: "test",
          keys: ["key"],
          content: "content",
          extensions: {
            triggers: ["continue", "regenerate"],
          },
        }

        entry = Entry.from_hash(hash)

        assert_equal %i[continue regenerate], entry.triggers
      end

      def test_from_hash_prefers_direct_triggers_over_extensions
        hash = {
          uid: "test",
          keys: ["key"],
          content: "content",
          triggers: ["normal"],
          extensions: {
            triggers: ["continue"],
          },
        }

        entry = Entry.from_hash(hash)

        assert_equal %i[normal], entry.triggers
      end

      def test_to_h_includes_triggers
        entry = Entry.new(
          uid: "test",
          keys: ["key"],
          content: "content",
          triggers: [:normal, :continue]
        )

        hash = entry.to_h

        assert_equal %i[normal continue], hash[:triggers]
      end

      def test_all_generation_types
        entry = Entry.new(
          uid: "test",
          keys: ["key"],
          content: "content",
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
