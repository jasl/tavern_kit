# frozen_string_literal: true

require "test_helper"

class TestEntryMatchFlags < Minitest::Test
  # Test default values
  def test_default_match_flags_are_false
    entry = TavernKit::Lore::Entry.new(
      uid: "test",
      keys: ["hello"],
      content: "World"
    )

    refute entry.match_persona_description?
    refute entry.match_character_description?
    refute entry.match_character_personality?
    refute entry.match_character_depth_prompt?
    refute entry.match_scenario?
    refute entry.match_creator_notes?
    refute entry.has_match_flags?
  end

  def test_match_flags_can_be_set_via_constructor
    entry = TavernKit::Lore::Entry.new(
      uid: "test",
      keys: ["hello"],
      content: "World",
      match_persona_description: true,
      match_character_description: true,
      match_character_personality: true,
      match_character_depth_prompt: true,
      match_scenario: true,
      match_creator_notes: true
    )

    assert entry.match_persona_description?
    assert entry.match_character_description?
    assert entry.match_character_personality?
    assert entry.match_character_depth_prompt?
    assert entry.match_scenario?
    assert entry.match_creator_notes?
    assert entry.has_match_flags?
  end

  def test_has_match_flags_with_single_flag
    entry = TavernKit::Lore::Entry.new(
      uid: "test",
      keys: ["hello"],
      content: "World",
      match_scenario: true
    )

    assert entry.has_match_flags?
  end

  # Test parsing from camelCase (ST format)
  def test_from_hash_parses_camel_case_match_flags
    hash = {
      "uid" => "test-1",
      "keys" => "dragon",
      "content" => "A mighty creature",
      "matchPersonaDescription" => true,
      "matchCharacterDescription" => true,
      "matchCharacterPersonality" => true,
      "matchCharacterDepthPrompt" => true,
      "matchScenario" => true,
      "matchCreatorNotes" => true,
    }

    entry = TavernKit::Lore::Entry.from_hash(hash)

    assert entry.match_persona_description?
    assert entry.match_character_description?
    assert entry.match_character_personality?
    assert entry.match_character_depth_prompt?
    assert entry.match_scenario?
    assert entry.match_creator_notes?
  end

  # Test parsing from snake_case
  def test_from_hash_parses_snake_case_match_flags
    hash = {
      uid: "test-2",
      keys: "elf",
      content: "A graceful being",
      match_persona_description: true,
      match_character_description: true,
      match_character_personality: false,
      match_character_depth_prompt: false,
      match_scenario: true,
      match_creator_notes: false,
    }

    entry = TavernKit::Lore::Entry.from_hash(hash)

    assert entry.match_persona_description?
    assert entry.match_character_description?
    refute entry.match_character_personality?
    refute entry.match_character_depth_prompt?
    assert entry.match_scenario?
    refute entry.match_creator_notes?
  end

  # Test parsing from extensions path (ST export format)
  def test_from_hash_parses_extensions_format
    hash = {
      "uid" => "test-3",
      "keys" => "wizard",
      "content" => "A magic user",
      "extensions" => {
        "match_persona_description" => true,
        "match_character_description" => false,
        "match_scenario" => true,
      },
    }

    entry = TavernKit::Lore::Entry.from_hash(hash)

    assert entry.match_persona_description?
    refute entry.match_character_description?
    assert entry.match_scenario?
  end

  # Test direct keys take precedence over extensions
  def test_direct_keys_override_extensions
    hash = {
      "uid" => "test-4",
      "keys" => "knight",
      "content" => "A brave warrior",
      "matchPersonaDescription" => true,
      "extensions" => {
        "match_persona_description" => false,
      },
    }

    entry = TavernKit::Lore::Entry.from_hash(hash)

    # Direct key should take precedence
    assert entry.match_persona_description?
  end

  # Test to_h includes match_* flags
  def test_to_h_includes_match_flags
    entry = TavernKit::Lore::Entry.new(
      uid: "test",
      keys: ["hello"],
      content: "World",
      match_persona_description: true,
      match_scenario: true
    )

    h = entry.to_h

    assert h.key?(:match_persona_description)
    assert h.key?(:match_character_description)
    assert h.key?(:match_character_personality)
    assert h.key?(:match_character_depth_prompt)
    assert h.key?(:match_scenario)
    assert h.key?(:match_creator_notes)

    assert_equal true, h[:match_persona_description]
    assert_equal false, h[:match_character_description]
    assert_equal true, h[:match_scenario]
  end

  # Test booleanish conversion
  def test_match_flags_handle_string_values
    hash = {
      "uid" => "test-5",
      "keys" => "cat",
      "content" => "Meow",
      "matchPersonaDescription" => "true",
      "matchCharacterDescription" => "false",
      "matchScenario" => "1",
      "matchCreatorNotes" => "0",
    }

    entry = TavernKit::Lore::Entry.from_hash(hash)

    assert entry.match_persona_description?
    refute entry.match_character_description?
    assert entry.match_scenario?
    refute entry.match_creator_notes?
  end

  # Test with mixed symbol/string keys
  def test_from_hash_with_symbol_keys
    hash = {
      uid: "test-6",
      keys: "dog",
      content: "Woof",
      matchPersonaDescription: true,
      matchScenario: true,
    }

    entry = TavernKit::Lore::Entry.from_hash(hash)

    assert entry.match_persona_description?
    assert entry.match_scenario?
  end
end
