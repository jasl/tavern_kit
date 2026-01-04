# frozen_string_literal: true

require "test_helper"

class LoreEngineForcedActivationsTest < Minitest::Test
  def test_forced_activation_selects_entry_without_key_match_and_can_override_content
    book = TavernKit::Lore::Book.from_hash(
      {
        "name" => "Test",
        "token_budget" => 10_000,
        "scan_depth" => 1,
        "entries" => [
          {
            "uid" => "x",
            "keys" => ["dragon"],
            "content" => "ORIGINAL",
            "insertion_order" => 100,
            "position" => "before_char_defs",
          },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new(token_estimator: TavernKit::TokenEstimator::CharDiv4.new)

    result = engine.evaluate(
      book: book,
      scan_messages: ["no match"],
      scan_depth: 1,
      forced_activations: [{ "world" => "Test", "uid" => "x", "content" => "FORCED" }]
    )

    assert_equal ["x"], result.selected_entries.map(&:uid)
    assert_equal "FORCED", result.selected_entries.first.content
  end
end
