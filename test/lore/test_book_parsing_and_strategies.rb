# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Lore
    class TestBookParsingAndStrategies < Minitest::Test
      def test_parses_entries_hash_form
        book = Book.from_hash(
          {
            "name" => "Global",
            "scanDepth" => 2,
            "tokenBudget" => 100,
            "recursiveScanning" => true,
            "entries" => {
              "10" => { "uid" => 10, "key" => ["k10"], "content" => "ten" },
              "0" => { "uid" => 0, "key" => ["k0"], "content" => "zero" },
            },
          },
          source: :global
        )

        assert_equal "Global", book.name
        assert_equal 2, book.scan_depth
        assert_equal 100, book.token_budget
        assert_equal true, book.recursive_scanning
        assert_equal :global, book.source
        assert_equal [0, 10], book.entries.map(&:uid)
        assert_equal ["Global", "Global"], book.entries.map(&:book_name)
        assert_equal [:global, :global], book.entries.map(&:source)
      end

      def test_character_lore_insertion_strategies
        char_book = Book.from_hash(
          {
            "name" => "Character",
            "entries" => [
              { "uid" => 1, "key" => ["c"], "content" => "char", "position" => "before_char_defs", "order" => 10 },
            ],
          },
          source: :character
        )

        primary_book = Book.from_hash(
          {
            "name" => "Primary",
            "entries" => [
              { "uid" => 3, "key" => ["p"], "content" => "primary", "position" => "before_char_defs", "order" => 5 },
            ],
          },
          source: :character_primary
        )

        additional_book = Book.from_hash(
          {
            "name" => "Additional",
            "entries" => [
              { "uid" => 4, "key" => ["a"], "content" => "additional", "position" => "before_char_defs", "order" => 7 },
            ],
          },
          source: :character_additional
        )

        global_book = Book.from_hash(
          {
            "name" => "Global",
            "entries" => [
              { "uid" => 2, "key" => ["g"], "content" => "global", "position" => "before_char_defs", "order" => 1 },
            ],
          },
          source: :global
        )

        estimator = TokenEstimator::CharDiv4.new
        engine = Engine.new(token_estimator: estimator)

        result_sorted = engine.evaluate(
          books: [char_book, primary_book, additional_book, global_book],
          scan_text: "c p a g",
          token_budget: 999,
          insertion_strategy: :sorted_evenly
        )

        assert_equal [2, 3, 4, 1], result_sorted.selected_by_position[:before_char_defs].map(&:uid)

        result_char_first = engine.evaluate(
          books: [char_book, primary_book, additional_book, global_book],
          scan_text: "c p a g",
          token_budget: 999,
          insertion_strategy: :character_lore_first
        )
        assert_equal [3, 4, 1, 2], result_char_first.selected_by_position[:before_char_defs].map(&:uid)

        result_global_first = engine.evaluate(
          books: [char_book, primary_book, additional_book, global_book],
          scan_text: "c p a g",
          token_budget: 999,
          insertion_strategy: :global_lore_first
        )
        assert_equal [2, 3, 4, 1], result_global_first.selected_by_position[:before_char_defs].map(&:uid)
      end
    end
  end
end
