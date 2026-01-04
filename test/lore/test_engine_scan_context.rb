# frozen_string_literal: true

require "test_helper"

class TestEngineScanContext < Minitest::Test
  def setup
    @estimator = TavernKit::TokenEstimator.char_div4
    @engine = TavernKit::Lore::Engine.new(
      token_estimator: @estimator,
      match_whole_words: true,
      case_sensitive: false
    )
  end

  # Test that scan_context is optional
  def test_evaluate_works_without_scan_context
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        { "uid" => "1", "keys" => "dragon", "content" => "A fire-breathing creature" },
      ],
    })

    result = @engine.evaluate(book: book, scan_text: "I saw a dragon")

    assert_equal 1, result.selected.count
  end

  # Test basic scan_context usage with match_persona_description
  def test_match_persona_description_flag
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "1",
          "keys" => "warrior",
          "content" => "A brave fighter",
          "matchPersonaDescription" => true,
        },
      ],
    })

    # Without scan_context, the entry should not match
    result1 = @engine.evaluate(
      book: book,
      scan_text: "Hello there"
    )
    assert_equal 0, result1.selected.count

    # With scan_context containing "warrior" in persona, the entry should match
    result2 = @engine.evaluate(
      book: book,
      scan_text: "Hello there",
      scan_context: { persona_description: "I am a warrior from the north" }
    )
    assert_equal 1, result2.selected.count
  end

  # Test match_character_description flag
  def test_match_character_description_flag
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "1",
          "keys" => "elf",
          "content" => "Pointed ears and magical abilities",
          "matchCharacterDescription" => true,
        },
      ],
    })

    result = @engine.evaluate(
      book: book,
      scan_text: "Hello friend",
      scan_context: { character_description: "An elf from the ancient forest" }
    )

    assert_equal 1, result.selected.count
  end

  # Test match_character_personality flag
  def test_match_character_personality_flag
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "1",
          "keys" => "cheerful",
          "content" => "Always happy and positive",
          "matchCharacterPersonality" => true,
        },
      ],
    })

    result = @engine.evaluate(
      book: book,
      scan_text: "Good morning",
      scan_context: { character_personality: "cheerful, optimistic, kind" }
    )

    assert_equal 1, result.selected.count
  end

  # Test match_scenario flag
  def test_match_scenario_flag
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "1",
          "keys" => "tavern",
          "content" => "A cozy place to rest",
          "matchScenario" => true,
        },
      ],
    })

    result = @engine.evaluate(
      book: book,
      scan_text: "Let's go",
      scan_context: { scenario: "You are in a medieval tavern" }
    )

    assert_equal 1, result.selected.count
  end

  # Test match_character_depth_prompt flag
  def test_match_character_depth_prompt_flag
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "1",
          "keys" => "concise",
          "content" => "Hidden information",
          "matchCharacterDepthPrompt" => true,
        },
      ],
    })

    result = @engine.evaluate(
      book: book,
      scan_text: "Tell me something",
      scan_context: { character_depth_prompt: "Be concise and direct" }
    )

    assert_equal 1, result.selected.count
  end

  # Test match_creator_notes flag
  def test_match_creator_notes_flag
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "1",
          "keys" => "author",
          "content" => "Created with love",
          "matchCreatorNotes" => true,
        },
      ],
    })

    result = @engine.evaluate(
      book: book,
      scan_text: "What is this?",
      scan_context: { creator_notes: "Written by author XYZ" }
    )

    assert_equal 1, result.selected.count
  end

  # Test multiple match flags on same entry
  def test_multiple_match_flags
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "1",
          "keys" => "magic",
          "content" => "Mystical powers",
          "matchPersonaDescription" => true,
          "matchCharacterDescription" => true,
          "matchScenario" => true,
        },
      ],
    })

    # Match should work if keyword is in any of the enabled fields
    result = @engine.evaluate(
      book: book,
      scan_text: "Hello",
      scan_context: {
        persona_description: "A normal person",
        character_description: "Has magic abilities",
        scenario: "A mundane world",
      }
    )

    assert_equal 1, result.selected.count
  end

  # Test that entry without match flags only scans base text
  def test_entry_without_match_flags_only_scans_base_text
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "1",
          "keys" => "dragon",
          "content" => "A mythical creature",
          # No match_* flags set
        },
      ],
    })

    # Should not match even if keyword is in scan_context
    result = @engine.evaluate(
      book: book,
      scan_text: "Hello",
      scan_context: { character_description: "A dragon tamer" }
    )

    assert_equal 0, result.selected.count
  end

  # Test that constant entries still work with scan_context
  def test_constant_entries_with_scan_context
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "1",
          "keys" => "ignored",
          "content" => "Always present",
          "constant" => true,
        },
      ],
    })

    result = @engine.evaluate(
      book: book,
      scan_text: "Hello",
      scan_context: { persona_description: "Test" }
    )

    assert_equal 1, result.selected.count
  end

  # Test empty scan_context field values are ignored
  def test_empty_context_fields_are_ignored
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "1",
          "keys" => "test",
          "content" => "Test content",
          "matchPersonaDescription" => true,
        },
      ],
    })

    # Empty persona should not contribute to matching
    result = @engine.evaluate(
      book: book,
      scan_text: "test",
      scan_context: { persona_description: "" }
    )

    # Should still match because "test" is in base scan text
    assert_equal 1, result.selected.count

    # Without the keyword in base text, empty context shouldn't match
    result2 = @engine.evaluate(
      book: book,
      scan_text: "Hello",
      scan_context: { persona_description: "   " }
    )

    assert_equal 0, result2.selected.count
  end

  # Test recursive scanning with scan_context
  def test_recursive_scanning_with_scan_context
    book = TavernKit::Lore::Book.from_hash({
      "entries" => [
        {
          "uid" => "first",
          "keys" => "magic",
          "content" => "The wizard uses magic. Mentions dragon.",
          "matchCharacterDescription" => true,
        },
        {
          "uid" => "second",
          "keys" => "dragon",
          "content" => "A fire-breathing dragon",
        },
      ],
      "recursive_scanning" => true,
    })

    engine = TavernKit::Lore::Engine.new(
      token_estimator: @estimator,
      max_recursion_steps: 3
    )

    result = engine.evaluate(
      book: book,
      scan_text: "Hello",
      scan_context: { character_description: "A powerful magic user" }
    )

    # First entry should match via character_description containing "magic"
    # Second entry should match via recursive scanning (first entry's content mentions "dragon")
    assert_equal 2, result.selected.count
  end
end
