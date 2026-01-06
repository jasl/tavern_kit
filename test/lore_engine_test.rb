# frozen_string_literal: true

require "test_helper"

class LoreEngineTest < Minitest::Test
  def test_budget_prefers_higher_insertion_order
    book = TavernKit::Lore::Book.from_hash(
      {
        "name" => "Test",
        "token_budget" => 11,
        "scan_depth" => 10,
        "entries" => [
          {
            "uid" => "low",
            "keys" => ["apple"],
            "content" => "A" * 40, # ~= 10 tokens
            "insertion_order" => 100,
            "position" => "before_char_defs",
          },
          {
            "uid" => "mid",
            "keys" => ["banana"],
            "content" => "B" * 40, # ~= 10 tokens
            "insertion_order" => 200,
            "position" => "after_char_defs",
          },
          {
            "uid" => "high",
            "keys" => ["cherry"],
            "content" => "C" * 4, # ~= 1 token
            "insertion_order" => 300,
            "position" => "outlet",
            "outlet" => "Facts",
          },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new
    result = engine.evaluate(book: book, scan_text: "apple banana cherry")

    assert_includes result.activated_entries.map(&:uid), "low"
    assert_includes result.activated_entries.map(&:uid), "mid"
    assert_includes result.activated_entries.map(&:uid), "high"

    # Budget 11 should include the highest order (high) and then mid, and drop low.
    assert_equal ["high", "mid"].sort, result.selected_entries.map(&:uid).sort
    dropped = result.dropped_candidates.map(&:entry).map(&:uid)
    assert_equal ["low"], dropped

    # Outlet content should be aggregated.
    assert_equal({ "Facts" => "CCCC" }, result.outlets)
  end

  def test_match_whole_words
    book = TavernKit::Lore::Book.from_hash(
      {
        "token_budget" => 100,
        "scan_depth" => 10,
        "entries" => [
          { "uid" => "cat", "keys" => ["cat"], "content" => "CAT", "insertion_order" => 1, "position" => "before_char_defs" },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new(match_whole_words: true)
    result = engine.evaluate(book: book, scan_text: "concatenate")
    assert_equal [], result.activated_entries

    result2 = engine.evaluate(book: book, scan_text: "a cat sat")
    assert_equal ["cat"], result2.activated_entries.map(&:uid)
  end

  def test_js_regex_keys
    book = TavernKit::Lore::Book.from_hash(
      {
        "token_budget" => 100,
        "scan_depth" => 10,
        "entries" => [
          { "uid" => "re", "keys" => ["/appl(e|y)/i"], "content" => "RE", "insertion_order" => 1, "position" => "before_char_defs" },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new
    result = engine.evaluate(book: book, scan_text: "I will APPLY now")
    assert_equal ["re"], result.activated_entries.map(&:uid)
  end

  def test_recursive_scanning_triggers_chain
    # Entry A triggers on "dragon", content mentions "mountain"
    # Entry B triggers on "mountain", content mentions "ice king"
    # Entry C triggers on "ice king"
    # With recursive_scanning enabled, A → B → C should all activate
    book = TavernKit::Lore::Book.from_hash(
      {
        "token_budget" => 1000,
        "scan_depth" => 10,
        "recursive_scanning" => true,
        "entries" => [
          { "uid" => "dragon", "keys" => ["dragon"], "content" => "Dragons live in the mountain caves.", "insertion_order" => 1 },
          { "uid" => "mountain", "keys" => ["mountain"], "content" => "The mountains are ruled by the ice king.", "insertion_order" => 2 },
          { "uid" => "ice_king", "keys" => ["ice king"], "content" => "The Ice King is ancient.", "insertion_order" => 3 },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new(max_recursion_steps: 3)
    result = engine.evaluate(book: book, scan_text: "I see a dragon")

    # All three should be activated through recursive scanning
    activated_uids = result.activated_entries.map(&:uid).sort
    assert_equal ["dragon", "ice_king", "mountain"], activated_uids
  end

  def test_recursive_scanning_disabled_by_default
    # Same setup, but recursive_scanning is false
    book = TavernKit::Lore::Book.from_hash(
      {
        "token_budget" => 1000,
        "scan_depth" => 10,
        "recursive_scanning" => false,
        "entries" => [
          { "uid" => "dragon", "keys" => ["dragon"], "content" => "Dragons live in the mountain caves.", "insertion_order" => 1 },
          { "uid" => "mountain", "keys" => ["mountain"], "content" => "The mountains are ruled by the ice king.", "insertion_order" => 2 },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new
    result = engine.evaluate(book: book, scan_text: "I see a dragon")

    # Only dragon should be activated (no recursion)
    assert_equal ["dragon"], result.activated_entries.map(&:uid)
  end

  def test_recursive_scanning_prevents_circular_dependency
    # Entry A triggers on "foo", content has "bar"
    # Entry B triggers on "bar", content has "foo"
    # This should NOT cause infinite loop
    book = TavernKit::Lore::Book.from_hash(
      {
        "token_budget" => 1000,
        "scan_depth" => 10,
        "recursive_scanning" => true,
        "entries" => [
          { "uid" => "a", "keys" => ["foo"], "content" => "This mentions bar.", "insertion_order" => 1 },
          { "uid" => "b", "keys" => ["bar"], "content" => "This mentions foo.", "insertion_order" => 2 },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new(max_recursion_steps: 10)
    result = engine.evaluate(book: book, scan_text: "foo")

    # Both should be activated, but each only once (no duplicates)
    activated_uids = result.activated_entries.map(&:uid).sort
    assert_equal ["a", "b"], activated_uids
  end

  def test_recursive_scanning_respects_max_steps
    # Create a long chain: A → B → C → D → E
    book = TavernKit::Lore::Book.from_hash(
      {
        "token_budget" => 1000,
        "scan_depth" => 10,
        "recursive_scanning" => true,
        "entries" => [
          { "uid" => "a", "keys" => ["start"], "content" => "trigger_b", "insertion_order" => 1 },
          { "uid" => "b", "keys" => ["trigger_b"], "content" => "trigger_c", "insertion_order" => 2 },
          { "uid" => "c", "keys" => ["trigger_c"], "content" => "trigger_d", "insertion_order" => 3 },
          { "uid" => "d", "keys" => ["trigger_d"], "content" => "trigger_e", "insertion_order" => 4 },
          { "uid" => "e", "keys" => ["trigger_e"], "content" => "end", "insertion_order" => 5 },
        ],
      }
    )

    # With max_recursion_steps=2, we get 3 total scans: 1 initial + 2 recursive.
    # That means we can activate A, then B, then C — but we stop before scanning C's content,
    # so D/E should NOT activate.
    engine = TavernKit::Lore::Engine.new(max_recursion_steps: 2)
    result = engine.evaluate(book: book, scan_text: "start")

    activated_uids = result.activated_entries.map(&:uid).sort
    assert_equal ["a", "b", "c"], activated_uids
  end

  def test_recursive_scanning_caps_recurse_buffer_size
    engine_class = TavernKit::Lore::Engine
    original = engine_class.const_get(:MAX_SCAN_BUFFER_SIZE)
    engine_class.send(:remove_const, :MAX_SCAN_BUFFER_SIZE)
    engine_class.const_set(:MAX_SCAN_BUFFER_SIZE, 30)

    book = TavernKit::Lore::Book.from_hash(
      {
        "token_budget" => 1000,
        "scan_depth" => 10,
        "recursive_scanning" => true,
        "entries" => [
          { "uid" => "a", "keys" => ["start"], "content" => ("trigger_b " + ("X" * 200)), "insertion_order" => 1 },
          { "uid" => "b", "keys" => ["trigger_b"], "content" => "B", "insertion_order" => 2 },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new(max_recursion_steps: 3)
    result = engine.evaluate(book: book, scan_text: "start")

    # With a tiny recurse buffer, the trigger at the start of A's content should be truncated away.
    assert_equal ["a"], result.activated_entries.map(&:uid).sort
  ensure
    engine_class.send(:remove_const, :MAX_SCAN_BUFFER_SIZE)
    engine_class.const_set(:MAX_SCAN_BUFFER_SIZE, original)
  end

  def test_ignore_budget_entries_can_be_selected_after_budget_overflow
    book = TavernKit::Lore::Book.from_hash(
      {
        "name" => "Test",
        "token_budget" => 5,
        "scan_depth" => 10,
        "entries" => [
          {
            "uid" => "high",
            "keys" => ["a"],
            "content" => "A" * 20, # 5 tokens (CharDiv4)
            "insertion_order" => 300,
            "position" => "before_char_defs",
          },
          {
            "uid" => "mid",
            "keys" => ["b"],
            "content" => "B" * 4, # 1 token
            "insertion_order" => 200,
            "position" => "before_char_defs",
          },
          {
            "uid" => "ignore",
            "keys" => ["c"],
            "content" => "C" * 12, # 3 tokens
            "insertion_order" => 100,
            "position" => "before_char_defs",
            "ignoreBudget" => true,
          },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new(token_estimator: TavernKit::TokenEstimator::CharDiv4.new)
    result = engine.evaluate(book: book, scan_text: "a b c")

    assert_equal %w[high ignore].sort, result.selected_entries.map(&:uid).sort
    dropped = result.dropped_candidates.map(&:entry).map(&:uid)
    assert_equal ["mid"], dropped
  end

  def test_probability_can_suppress_activation
    book = TavernKit::Lore::Book.from_hash(
      {
        "name" => "Test",
        "token_budget" => 1_000,
        "scan_depth" => 10,
        "entries" => [
          {
            "uid" => "p",
            "keys" => ["dragon"],
            "content" => "DRAGON",
            "insertion_order" => 100,
            "position" => "before_char_defs",
            "useProbability" => true,
            "probability" => 50,
          },
        ],
      }
    )

    rng = Class.new do
      def rand
        0.99
      end
    end.new

    engine = TavernKit::Lore::Engine.new(token_estimator: TavernKit::TokenEstimator::CharDiv4.new)
    result = engine.evaluate(book: book, scan_text: "dragon", rng: rng)

    assert_empty result.selected_entries
    assert_equal ["p"], result.activated_entries.map(&:uid)
    assert_equal ["probability_failed"], result.dropped_candidates.map(&:dropped_reason).uniq
  end

  def test_inclusion_group_override_wins
    book = TavernKit::Lore::Book.from_hash(
      {
        "name" => "Test",
        "token_budget" => 1_000,
        "scan_depth" => 10,
        "entries" => [
          {
            "uid" => "winner",
            "keys" => ["x"],
            "content" => "WIN",
            "insertion_order" => 100,
            "position" => "before_char_defs",
            "group" => "G",
            "groupOverride" => true,
          },
          {
            "uid" => "loser",
            "keys" => ["x"],
            "content" => "LOSE",
            "insertion_order" => 200,
            "position" => "before_char_defs",
            "group" => "G",
            "groupOverride" => false,
          },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new(token_estimator: TavernKit::TokenEstimator::CharDiv4.new)
    result = engine.evaluate(book: book, scan_text: "x")

    assert_equal ["winner"], result.selected_entries.map(&:uid)
  end

  # Test prevent_recursion behavior:
  # preventRecursion controls whether an entry's content is added to the recursion buffer,
  # NOT whether the entry can be triggered by recursion.
  def test_prevent_recursion_stops_entry_from_causing_further_recursion
    # chain_start triggers -> mentions "dragon" -> chain_end triggers
    # chain_end has preventRecursion, so its content won't trigger further recursion
    book = TavernKit::Lore::Book.from_hash(
      {
        "name" => "Test",
        "token_budget" => 1_000,
        "scan_depth" => 10,
        "recursive_scanning" => true,
        "entries" => [
          {
            "uid" => "chain_start",
            "keys" => ["start"],
            "content" => "mentions dragon",
            "insertion_order" => 100,
            "position" => "before_char_defs",
          },
          {
            "uid" => "chain_end",
            "keys" => ["dragon"],
            "content" => "mentions treasure", # Would trigger treasure_entry if not prevented
            "insertion_order" => 200,
            "position" => "before_char_defs",
            "preventRecursion" => true,
          },
          {
            "uid" => "treasure",
            "keys" => ["treasure"],
            "content" => "Gold coins",
            "insertion_order" => 300,
            "position" => "before_char_defs",
          },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new(max_recursion_steps: 5)

    result = engine.evaluate(book: book, scan_text: "start")

    # chain_start triggers chain_end via recursion
    # But chain_end has preventRecursion, so its content ("mentions treasure")
    # is NOT added to recurse buffer, so treasure entry should NOT trigger
    assert_includes result.selected_entries.map(&:uid), "chain_start"
    assert_includes result.selected_entries.map(&:uid), "chain_end"
    refute_includes result.selected_entries.map(&:uid), "treasure"
  end

  # Test delay_until_recursion behavior:
  # Entry with delayUntilRecursion only activates during recursive scans at specified level.
  def test_delay_until_recursion_skips_entry_on_direct_scan
    book = TavernKit::Lore::Book.from_hash(
      {
        "name" => "Test",
        "token_budget" => 1_000,
        "scan_depth" => 10,
        "recursive_scanning" => false, # No recursion
        "entries" => [
          {
            "uid" => "normal",
            "keys" => ["dragon"],
            "content" => "Normal dragon info",
            "insertion_order" => 100,
          },
          {
            "uid" => "delayed",
            "keys" => ["dragon"],
            "content" => "Delayed dragon info",
            "insertion_order" => 200,
            "delayUntilRecursion" => 1,
          },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new

    result = engine.evaluate(book: book, scan_text: "dragon")

    # Normal entry activates, delayed entry does not (no recursion)
    assert_equal ["normal"], result.selected_entries.map(&:uid)
  end

  def test_delay_until_recursion_activates_during_recursion
    book = TavernKit::Lore::Book.from_hash(
      {
        "name" => "Test",
        "token_budget" => 1_000,
        "scan_depth" => 10,
        "recursive_scanning" => true,
        "entries" => [
          {
            "uid" => "starter",
            "keys" => ["start"],
            "content" => "mentions dragon",
            "insertion_order" => 100,
          },
          {
            "uid" => "delayed",
            "keys" => ["dragon"],
            "content" => "Delayed dragon info",
            "insertion_order" => 200,
            "delayUntilRecursion" => 1, # Activates at recursion level 1
          },
        ],
      }
    )

    engine = TavernKit::Lore::Engine.new(max_recursion_steps: 3)

    result = engine.evaluate(book: book, scan_text: "start")

    # Both should be selected:
    # - starter triggers on direct scan
    # - delayed triggers during recursion (level 1)
    assert_includes result.selected_entries.map(&:uid), "starter"
    assert_includes result.selected_entries.map(&:uid), "delayed"
  end
end
