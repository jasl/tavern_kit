# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Lore
    class EngineTriggersTest < Minitest::Test
      def setup
        @engine = Engine.new
      end

      def test_evaluate_filters_by_generation_type
        entry_normal = Entry.new(
          uid: "normal_only",
          keys: ["keyword"],
          content: "Normal content",
          triggers: [:normal]
        )
        entry_continue = Entry.new(
          uid: "continue_only",
          keys: ["keyword"],
          content: "Continue content",
          triggers: [:continue]
        )
        entry_all = Entry.new(
          uid: "all_types",
          keys: ["keyword"],
          content: "All types content",
          triggers: []
        )

        book = Book.new(entries: [entry_normal, entry_continue, entry_all])

        # Normal generation type
        result_normal = @engine.evaluate(
          book: book,
          scan_text: "This has the keyword",
          generation_type: :normal
        )

        selected_uids = result_normal.selected.map { |c| c.entry.uid }
        assert_includes selected_uids, "normal_only"
        refute_includes selected_uids, "continue_only"
        assert_includes selected_uids, "all_types"

        # Continue generation type
        result_continue = @engine.evaluate(
          book: book,
          scan_text: "This has the keyword",
          generation_type: :continue
        )

        selected_uids = result_continue.selected.map { |c| c.entry.uid }
        refute_includes selected_uids, "normal_only"
        assert_includes selected_uids, "continue_only"
        assert_includes selected_uids, "all_types"
      end

      def test_evaluate_default_generation_type_is_normal
        entry_normal = Entry.new(
          uid: "normal_only",
          keys: ["keyword"],
          content: "Normal content",
          triggers: [:normal]
        )
        entry_continue = Entry.new(
          uid: "continue_only",
          keys: ["keyword"],
          content: "Continue content",
          triggers: [:continue]
        )

        book = Book.new(entries: [entry_normal, entry_continue])

        # No generation_type specified should default to :normal
        result = @engine.evaluate(
          book: book,
          scan_text: "This has the keyword"
        )

        selected_uids = result.selected.map { |c| c.entry.uid }
        assert_includes selected_uids, "normal_only"
        refute_includes selected_uids, "continue_only"
      end

      def test_evaluate_accepts_string_generation_type
        entry = Entry.new(
          uid: "test",
          keys: ["keyword"],
          content: "Content",
          triggers: [:impersonate]
        )

        book = Book.new(entries: [entry])

        assert_raises(ArgumentError) do
          @engine.evaluate(
            book: book,
            scan_text: "keyword",
            generation_type: "impersonate"
          )
        end
      end

      def test_evaluate_empty_triggers_matches_all_types
        entry = Entry.new(
          uid: "universal",
          keys: ["keyword"],
          content: "Content",
          triggers: []
        )

        book = Book.new(entries: [entry])

        TavernKit::GENERATION_TYPES.each do |gen_type|
          result = @engine.evaluate(
            book: book,
            scan_text: "keyword",
            generation_type: gen_type
          )

          assert_equal 1, result.selected.size,
                       "Entry with empty triggers should match #{gen_type}"
        end
      end

      def test_evaluate_constant_entries_respect_triggers
        # Constant entries should also respect triggers
        entry_constant = Entry.new(
          uid: "constant_continue",
          keys: [],
          content: "Constant content",
          constant: true,
          triggers: [:continue]
        )

        book = Book.new(entries: [entry_constant])

        # Should be filtered out for :normal
        result_normal = @engine.evaluate(
          book: book,
          scan_text: "any text",
          generation_type: :normal
        )
        assert_empty result_normal.selected

        # Should be included for :continue
        result_continue = @engine.evaluate(
          book: book,
          scan_text: "any text",
          generation_type: :continue
        )
        assert_equal 1, result_continue.selected.size
      end
    end
  end
end
