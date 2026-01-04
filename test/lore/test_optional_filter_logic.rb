# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Lore
    class TestOptionalFilterLogic < Minitest::Test
      def build_book(entry_hash)
        Book.from_hash({ "entries" => [entry_hash] })
      end

      def evaluate(entry_hash, scan_text)
        engine = Engine.new(token_estimator: TokenEstimator::CharDiv4.new)
        book = build_book(entry_hash)
        engine.evaluate(book: book, scan_text: scan_text, token_budget: 10_000)
      end

      def test_and_any
        result = evaluate(
          {
            "uid" => 1,
            "key" => ["key"],
            "keysecondary" => ["a", "b"],
            "selective" => true,
            "selectiveLogic" => 0,
          },
          "key a"
        )

        assert_equal [1], result.selected_entries.map(&:uid)

        result2 = evaluate(
          {
            "uid" => 1,
            "key" => ["key"],
            "keysecondary" => ["a", "b"],
            "selective" => true,
            "selectiveLogic" => 0,
          },
          "key"
        )
        assert_empty result2.selected_entries
      end

      def test_and_all
        result = evaluate(
          {
            "uid" => 2,
            "key" => ["key"],
            "keysecondary" => ["a", "b"],
            "selective" => true,
            "selectiveLogic" => 3,
          },
          "key a b"
        )
        assert_equal [2], result.selected_entries.map(&:uid)

        result2 = evaluate(
          {
            "uid" => 2,
            "key" => ["key"],
            "keysecondary" => ["a", "b"],
            "selective" => true,
            "selectiveLogic" => 3,
          },
          "key a"
        )
        assert_empty result2.selected_entries
      end

      def test_not_any
        result = evaluate(
          {
            "uid" => 3,
            "key" => ["key"],
            "keysecondary" => ["a", "b"],
            "selective" => true,
            "selectiveLogic" => 2,
          },
          "key"
        )
        assert_equal [3], result.selected_entries.map(&:uid)

        result2 = evaluate(
          {
            "uid" => 3,
            "key" => ["key"],
            "keysecondary" => ["a", "b"],
            "selective" => true,
            "selectiveLogic" => 2,
          },
          "key a"
        )
        assert_empty result2.selected_entries
      end

      def test_not_all
        # NOT ALL passes if at least one optional key is missing.
        result = evaluate(
          {
            "uid" => 4,
            "key" => ["key"],
            "keysecondary" => ["a", "b"],
            "selective" => true,
            "selectiveLogic" => 1,
          },
          "key a"
        )
        assert_equal [4], result.selected_entries.map(&:uid)

        # But fails when *all* optional keys are present.
        result2 = evaluate(
          {
            "uid" => 4,
            "key" => ["key"],
            "keysecondary" => ["a", "b"],
            "selective" => true,
            "selectiveLogic" => 1,
          },
          "key a b"
        )
        assert_empty result2.selected_entries
      end

      def test_selective_false_ignores_optional_filter
        result = evaluate(
          {
            "uid" => 5,
            "key" => ["key"],
            "keysecondary" => ["a", "b"],
            "selective" => false,
            "selectiveLogic" => 3,
          },
          "key"
        )

        assert_equal [5], result.selected_entries.map(&:uid)
      end
    end
  end
end
