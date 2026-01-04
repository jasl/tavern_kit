# frozen_string_literal: true

require "test_helper"

class LoreEngineMinActivationsTest < Minitest::Test
  def test_min_activations_increases_depth_until_satisfied
    book = TavernKit::Lore::Book.from_hash(
      {
        "name" => "Test",
        "token_budget" => 10_000,
        "scan_depth" => 1,
        "entries" => [
          { "uid" => "a", "keys" => ["alpha"], "content" => "A", "insertion_order" => 100, "position" => "before_char_defs" },
          { "uid" => "b", "keys" => ["beta"], "content" => "B", "insertion_order" => 90, "position" => "before_char_defs" },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new(token_estimator: TavernKit::TokenEstimator::CharDiv4.new)

    # Newest-first scan messages. Depth=1 sees only "alpha".
    scan_messages = ["alpha", "beta", "gamma"]

    result = engine.evaluate(
      book: book,
      scan_messages: scan_messages,
      scan_depth: 1,
      min_activations: 2,
      min_activations_depth_max: 0
    )

    assert_equal %w[a b].sort, result.selected_entries.map(&:uid).sort
  end

  def test_min_activations_respects_depth_max
    book = TavernKit::Lore::Book.from_hash(
      {
        "name" => "Test",
        "token_budget" => 10_000,
        "scan_depth" => 1,
        "entries" => [
          { "uid" => "a", "keys" => ["alpha"], "content" => "A", "insertion_order" => 100, "position" => "before_char_defs" },
          { "uid" => "b", "keys" => ["beta"], "content" => "B", "insertion_order" => 90, "position" => "before_char_defs" },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new(token_estimator: TavernKit::TokenEstimator::CharDiv4.new)

    scan_messages = ["alpha", "beta", "gamma"]

    result = engine.evaluate(
      book: book,
      scan_messages: scan_messages,
      scan_depth: 1,
      min_activations: 2,
      min_activations_depth_max: 1
    )

    assert_equal ["a"], result.selected_entries.map(&:uid)
  end
end
