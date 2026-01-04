# frozen_string_literal: true

require "test_helper"

class LoreEngineTimedEffectsTest < Minitest::Test
  def setup
    @engine = TavernKit::Lore::Engine.new(token_estimator: TavernKit::TokenEstimator::CharDiv4.new)
    @vars = TavernKit::ChatVariables.new
  end

  def test_sticky_then_cooldown
    book = TavernKit::Lore::Book.from_hash(
      {
        "name" => "Test",
        "token_budget" => 10_000,
        "scan_depth" => 1,
        "entries" => [
          {
            "uid" => "wi",
            "keys" => ["dragon"],
            "content" => "DRAGONS",
            "insertion_order" => 100,
            "position" => "before_char_defs",
            "sticky" => 2,
            "cooldown" => 3,
          },
        ],
      }
    )

    # Turn 1: key match activates, sets sticky+cooldown metadata.
    r1 = @engine.evaluate(
      book: book,
      scan_messages: ["dragon"],
      scan_depth: 1,
      message_count: 1,
      variables_store: @vars
    )
    assert_equal ["wi"], r1.selected_entries.map(&:uid)

    # Turn 2: no key match, but sticky auto-activates.
    r2 = @engine.evaluate(
      book: book,
      scan_messages: ["no match"],
      scan_depth: 1,
      message_count: 2,
      variables_store: @vars
    )
    assert_equal ["wi"], r2.selected_entries.map(&:uid)

    # Turn 3: sticky ends (end=3), cooldown starts (start=3, end=6), entry is suppressed.
    r3 = @engine.evaluate(
      book: book,
      scan_messages: ["no match"],
      scan_depth: 1,
      message_count: 3,
      variables_store: @vars
    )
    assert_empty r3.selected_entries

    # Turn 6: cooldown ended, key match works again.
    r4 = @engine.evaluate(
      book: book,
      scan_messages: ["dragon"],
      scan_depth: 1,
      message_count: 6,
      variables_store: @vars
    )
    assert_equal ["wi"], r4.selected_entries.map(&:uid)
  end

  def test_delay_suppresses_until_message_count_reaches_delay
    book = TavernKit::Lore::Book.from_hash(
      {
        "name" => "Test",
        "token_budget" => 10_000,
        "scan_depth" => 1,
        "entries" => [
          {
            "uid" => "d",
            "keys" => ["dragon"],
            "content" => "DELAYED",
            "insertion_order" => 100,
            "position" => "before_char_defs",
            "delay" => 5,
          },
        ],
      }
    )

    r1 = @engine.evaluate(
      book: book,
      scan_messages: ["dragon"],
      scan_depth: 1,
      message_count: 4,
      variables_store: @vars
    )
    assert_empty r1.selected_entries

    r2 = @engine.evaluate(
      book: book,
      scan_messages: ["dragon"],
      scan_depth: 1,
      message_count: 5,
      variables_store: @vars
    )
    assert_equal ["d"], r2.selected_entries.map(&:uid)
  end
end
