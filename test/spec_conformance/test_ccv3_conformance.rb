# frozen_string_literal: true

require "test_helper"
require "json"

module TavernKit
  module SpecConformance
    # CCv3 conformance tests based on docs/CONFORMANCE_RULES.yml
    #
    # These tests verify that TavernKit correctly implements Character Card V3
    # parsing and export rules for interoperability.
    class TestCcv3Conformance < Minitest::Test
      FIXTURES_PATH = File.expand_path("../../docs/fixtures", __dir__)

      def fixture_path(name)
        File.join(FIXTURES_PATH, name)
      end

      def load_fixture(name)
        JSON.parse(File.read(fixture_path(name)))
      end

      # --- Identification ---

      def test_detects_ccv3_by_spec_field
        hash = load_fixture("ccv3_min.json")
        version = CharacterCard.detect_version(hash)

        assert_equal :v3, version
      end

      def test_accepts_spec_version_starting_with_3
        hash = load_fixture("ccv3_min.json")
        character = CharacterCard.load(hash)

        assert character.v3?
        assert_equal :v3, character.source_version
      end

      # --- Data Location ---

      def test_reads_fields_from_data_object
        hash = load_fixture("ccv3_min.json")
        character = CharacterCard.load(hash)

        assert_equal "Charlie", character.data.name
        assert_equal "A futuristic AI companion.", character.data.description
      end

      # --- Field Parsing: CCv2 Fields ---

      def test_parses_all_ccv2_fields
        hash = load_fixture("ccv3_st_export_like.json")
        character = CharacterCard.load(hash)

        # Core CCv2 fields
        assert_equal "Diana", character.data.name
        assert_equal "A warrior princess from a distant kingdom.", character.data.description
        assert_equal "Brave, honorable, and compassionate.", character.data.personality
        assert_equal "You encounter Diana on her quest to save her kingdom.", character.data.scenario
        assert_equal "Halt! State your purpose, stranger.", character.data.first_mes
        assert_includes character.data.mes_example, "I mean no harm"

        # Prompt overrides
        assert_includes character.data.system_prompt, "You are {{char}}"
        assert_includes character.data.post_history_instructions, "noble duty"

        # Metadata
        assert_equal ["fantasy", "warrior", "princess", "v3"], character.data.tags
        assert_equal "TavernKit", character.data.creator
        assert_equal "2.0.0", character.data.character_version
      end

      # --- Field Parsing: CCv3 Additions ---

      def test_parses_group_only_greetings
        hash = load_fixture("ccv3_st_export_like.json")
        character = CharacterCard.load(hash)

        assert_kind_of Array, character.data.group_only_greetings
        assert_equal 2, character.data.group_only_greetings.size
        assert_includes character.data.group_only_greetings, "Warriors, we stand together!"
      end

      def test_parses_assets
        hash = load_fixture("ccv3_st_export_like.json")
        character = CharacterCard.load(hash)

        assert_kind_of Array, character.data.assets
        assert_equal 2, character.data.assets.size

        icon = character.data.assets.find { |a| a["type"] == "icon" }
        assert_equal "ccdefault:icon.png", icon["uri"]
        assert_equal "main", icon["name"]
      end

      def test_parses_nickname
        hash = load_fixture("ccv3_st_export_like.json")
        character = CharacterCard.load(hash)

        assert_equal "Princess D", character.data.nickname
      end

      def test_parses_timestamps
        hash = load_fixture("ccv3_st_export_like.json")
        character = CharacterCard.load(hash)

        assert_equal 1_703_462_400, character.data.creation_date
        assert_equal 1_703_548_800, character.data.modification_date
      end

      def test_parses_creator_notes_multilingual
        hash = load_fixture("ccv3_st_export_like.json")
        character = CharacterCard.load(hash)

        assert_kind_of Hash, character.data.creator_notes_multilingual
        assert_includes character.data.creator_notes_multilingual["en"], "SillyTavern"
        assert_includes character.data.creator_notes_multilingual["ja"], "CCv3"
      end

      def test_parses_source
        hash = load_fixture("ccv3_st_export_like.json")
        character = CharacterCard.load(hash)

        assert_kind_of Array, character.data.source
        assert_includes character.data.source, "https://example.com/diana"
      end

      # --- Forward Compatibility ---

      def test_preserves_extensions
        hash = load_fixture("ccv3_st_export_like.json")
        character = CharacterCard.load(hash)

        assert_kind_of Hash, character.data.extensions
        assert_equal true, character.data.extensions["st_specific"]["fav"]
        assert_equal 0.8, character.data.extensions["st_specific"]["talkativeness"]
      end

      # --- Export ---

      def test_export_v3_writes_correct_spec
        hash = load_fixture("ccv3_min.json")
        character = CharacterCard.load(hash)
        exported = CharacterCard.export_v3(character)

        assert_equal "chara_card_v3", exported["spec"]
        assert_equal "3.0", exported["spec_version"]
      end

      def test_export_v3_writes_data_object
        hash = load_fixture("ccv3_min.json")
        character = CharacterCard.load(hash)
        exported = CharacterCard.export_v3(character)

        assert_kind_of Hash, exported["data"]
        assert_equal "Charlie", exported["data"]["name"]
      end

      def test_export_v3_data_contains_required_fields
        hash = load_fixture("ccv3_st_export_like.json")
        character = CharacterCard.load(hash)
        exported = CharacterCard.export_v3(character)

        data = exported["data"]

        # Core fields in data
        assert_equal "Diana", data["name"]
        assert_equal "A warrior princess from a distant kingdom.", data["description"]
        assert data.key?("tags")
        assert data.key?("creator")
        assert data.key?("extensions")

        # V3-specific fields in data
        assert_equal ["Warriors, we stand together!", "My allies, the battle begins."],
                     data["group_only_greetings"]
        assert_equal "Princess D", data["nickname"]
        assert_equal 1_703_462_400, data["creation_date"]
      end

      # --- V2 → V3 Upgrade ---

      def test_upgrades_v2_to_v3_with_empty_v3_fields
        hash = load_fixture("ccv2_min.json")
        character = CharacterCard.load(hash)
        exported = CharacterCard.export_v3(character)

        # Should have V3 structure
        assert_equal "chara_card_v3", exported["spec"]

        # V3-specific fields should be empty/nil
        assert_equal [], exported["data"]["group_only_greetings"]
      end
    end
  end
end
