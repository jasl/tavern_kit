# frozen_string_literal: true

require "test_helper"
require "json"

class TestCharacterCard < Minitest::Test
  FIXTURES_DIR = File.expand_path("fixtures", __dir__)

  # --- Loading Tests ---

  def test_load_v2_json_file
    path = File.join(FIXTURES_DIR, "full_v2_card.json")
    character = TavernKit::CharacterCard.load(path)

    assert_instance_of TavernKit::Character, character
    assert_equal :v2, character.source_version
    assert_equal "Aurora", character.data.name
    assert_equal "Aurora is a wise oracle who lives in a crystal tower.", character.data.description
    assert_equal ["oracle", "fantasy", "mystical"], character.data.tags
    assert_equal "TavernKit Tests", character.data.creator
    # V3 fields should have defaults
    assert_equal [], character.data.group_only_greetings
    assert_nil character.data.assets
    assert_nil character.data.nickname
  end

  def test_load_v3_json_file
    path = File.join(FIXTURES_DIR, "full_v3_card.json")
    character = TavernKit::CharacterCard.load(path)

    assert_instance_of TavernKit::Character, character
    assert_equal :v3, character.source_version
    assert_equal "Nova", character.data.name
    assert_equal "Nova is a starship captain exploring the galaxy.", character.data.description
    # V3-specific fields
    assert_equal ["Crew, assemble on the bridge.", "Team, we have a mission briefing."], character.data.group_only_greetings
    assert_equal "Captain Nova", character.data.nickname
    assert_equal 1703462400, character.data.creation_date
    assert_equal 1703548800, character.data.modification_date
    assert_equal ["https://example.com/nova"], character.data.source
    assert_equal 1, character.data.assets.length
    assert_equal "icon", character.data.assets.first["type"]
  end

  def test_load_from_hash
    hash = {
      "spec" => "chara_card_v2",
      "spec_version" => "2.0",
      "data" => {
        "name" => "TestChar",
        "description" => "A test character",
      },
    }

    character = TavernKit::CharacterCard.load(hash)

    assert_instance_of TavernKit::Character, character
    assert_equal :v2, character.source_version
    assert_equal "TestChar", character.data.name
  end

  def test_load_from_json_string
    json_str = JSON.generate({
      "spec" => "chara_card_v2",
      "spec_version" => "2.0",
      "data" => {
        "name" => "JsonStringChar",
        "description" => "From JSON string",
      },
    })

    character = TavernKit::CharacterCard.load(json_str)

    assert_instance_of TavernKit::Character, character
    assert_equal "JsonStringChar", character.data.name
  end

  def test_load_invalid_card_raises_error
    assert_raises(TavernKit::InvalidCardError) do
      TavernKit::CharacterCard.load({ "invalid" => "data" })
    end
  end

  def test_load_v1_raises_unsupported_error
    v1_hash = {
      "name" => "V1Char",
      "description" => "Old format",
      "first_mes" => "Hello!",
    }

    assert_raises(TavernKit::UnsupportedVersionError) do
      TavernKit::CharacterCard.load(v1_hash)
    end
  end

  def test_load_unsupported_file_type_raises_argument_error
    assert_raises(ArgumentError) do
      TavernKit::CharacterCard.load("not valid json at all {{{")
    end
  end

  # --- Version Detection Tests ---

  def test_detect_version_v2
    hash = { "spec" => "chara_card_v2", "data" => {} }
    assert_equal :v2, TavernKit::CharacterCard.detect_version(hash)
  end

  def test_detect_version_v3
    hash = { "spec" => "chara_card_v3", "data" => {} }
    assert_equal :v3, TavernKit::CharacterCard.detect_version(hash)
  end

  def test_detect_version_v1
    hash = { "name" => "Test", "description" => "Desc", "first_mes" => "Hi" }
    assert_equal :v1, TavernKit::CharacterCard.detect_version(hash)
  end

  def test_detect_version_unknown
    hash = { "unknown" => "format" }
    assert_equal :unknown, TavernKit::CharacterCard.detect_version(hash)
  end

  # --- Export V2 Tests ---

  def test_export_v2_basic
    character = TavernKit::Character.create(
      name: "ExportTest",
      description: "Test character",
      personality: "Friendly",
      tags: ["test"],
      creator: "Tester"
    )

    v2_hash = TavernKit::CharacterCard.export_v2(character)

    assert_equal "chara_card_v2", v2_hash["spec"]
    assert_equal "2.0", v2_hash["spec_version"]
    assert_equal "ExportTest", v2_hash["data"]["name"]
    assert_equal "Test character", v2_hash["data"]["description"]
    assert_equal "Friendly", v2_hash["data"]["personality"]
    assert_equal ["test"], v2_hash["data"]["tags"]
    assert_equal "Tester", v2_hash["data"]["creator"]
  end

  def test_export_v2_preserves_v3_fields_in_extensions
    character = TavernKit::Character.create(
      name: "V3Char",
      nickname: "V3Nick",
      group_only_greetings: ["Group hello!"],
      creation_date: 1703462400
    )

    v2_hash = TavernKit::CharacterCard.export_v2(character, preserve_v3_fields: true)

    extras = v2_hash["data"]["extensions"]["cc_extractor/v3"]
    assert_equal "V3Nick", extras["nickname"]
    assert_equal ["Group hello!"], extras["group_only_greetings"]
    assert_equal 1703462400, extras["creation_date"]
  end

  def test_export_v2_without_preserving_v3_fields
    character = TavernKit::Character.create(
      name: "V3Char",
      nickname: "V3Nick",
      group_only_greetings: ["Group hello!"]
    )

    v2_hash = TavernKit::CharacterCard.export_v2(character, preserve_v3_fields: false)

    refute v2_hash["data"]["extensions"].key?("cc_extractor/v3")
    refute v2_hash["data"].key?("nickname")
    refute v2_hash["data"].key?("group_only_greetings")
  end

  # --- Export V3 Tests ---

  def test_export_v3_basic
    character = TavernKit::Character.create(
      name: "V3Export",
      description: "V3 test",
      group_only_greetings: ["Group greeting!"],
      nickname: "V3Nick",
      creation_date: 1703462400
    )

    v3_hash = TavernKit::CharacterCard.export_v3(character)

    assert_equal "chara_card_v3", v3_hash["spec"]
    assert_equal "3.0", v3_hash["spec_version"]
    assert_equal "V3Export", v3_hash["data"]["name"]
    assert_equal ["Group greeting!"], v3_hash["data"]["group_only_greetings"]
    assert_equal "V3Nick", v3_hash["data"]["nickname"]
    assert_equal 1703462400, v3_hash["data"]["creation_date"]
  end

  def test_export_v3_includes_all_v3_fields
    character = TavernKit::Character.create(
      name: "FullV3",
      group_only_greetings: ["Group!"],
      assets: [{ "type" => "icon", "uri" => "test.png" }],
      nickname: "Nick",
      creator_notes_multilingual: { "en" => "English", "ja" => "日本語" },
      source: ["https://example.com"],
      creation_date: 1703462400,
      modification_date: 1703548800
    )

    v3_hash = TavernKit::CharacterCard.export_v3(character)
    data = v3_hash["data"]

    assert_equal ["Group!"], data["group_only_greetings"]
    assert_equal [{ "type" => "icon", "uri" => "test.png" }], data["assets"]
    assert_equal "Nick", data["nickname"]
    assert_equal({ "en" => "English", "ja" => "日本語" }, data["creator_notes_multilingual"])
    assert_equal ["https://example.com"], data["source"]
    assert_equal 1703462400, data["creation_date"]
    assert_equal 1703548800, data["modification_date"]
  end

  def test_export_v3_upgrades_lorebook
    character = TavernKit::Character.create(
      name: "LoreTest",
      character_book: {
        "name" => "Test Lore",
        "entries" => [
          {
            "keys" => ["test"],
            "content" => "Test content",
            "enabled" => true,
          },
        ],
      }
    )

    v3_hash = TavernKit::CharacterCard.export_v3(character)
    entry = v3_hash["data"]["character_book"]["entries"].first

    # V3 requires use_regex boolean
    assert_equal false, entry["use_regex"]
    assert_instance_of Hash, entry["extensions"]
  end

  # --- Round-trip Tests ---

  def test_round_trip_v2
    path = File.join(FIXTURES_DIR, "full_v2_card.json")
    original = JSON.parse(File.read(path))

    character = TavernKit::CharacterCard.load(path)
    exported = TavernKit::CharacterCard.export_v2(character, preserve_v3_fields: false)

    assert_equal original["spec"], exported["spec"]
    assert_equal original["data"]["name"], exported["data"]["name"]
    assert_equal original["data"]["description"], exported["data"]["description"]
    assert_equal original["data"]["tags"], exported["data"]["tags"]
    assert_equal original["data"]["creator"], exported["data"]["creator"]
  end

  def test_round_trip_v3
    path = File.join(FIXTURES_DIR, "full_v3_card.json")
    original = JSON.parse(File.read(path))

    character = TavernKit::CharacterCard.load(path)
    exported = TavernKit::CharacterCard.export_v3(character)

    assert_equal original["spec"], exported["spec"]
    assert_equal original["data"]["name"], exported["data"]["name"]
    assert_equal original["data"]["nickname"], exported["data"]["nickname"]
    assert_equal original["data"]["group_only_greetings"], exported["data"]["group_only_greetings"]
    assert_equal original["data"]["creation_date"], exported["data"]["creation_date"]
  end

  # --- Convenience Method Test ---

  def test_load_character_convenience_method
    path = File.join(FIXTURES_DIR, "full_v2_card.json")
    character = TavernKit.load_character(path)

    assert_instance_of TavernKit::Character, character
    assert_equal "Aurora", character.data.name
  end
end
