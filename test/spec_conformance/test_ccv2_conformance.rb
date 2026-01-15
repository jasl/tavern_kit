# frozen_string_literal: true

require "test_helper"
require "json"

module TavernKit
  module SpecConformance
    # CCv2 conformance tests based on docs/CONFORMANCE_RULES.yml
    #
    # These tests verify that TavernKit correctly implements Character Card V2
    # parsing and export rules for interoperability.
    class TestCcv2Conformance < Minitest::Test
      FIXTURES_PATH = File.expand_path("../../docs/fixtures", __dir__)

      def fixture_path(name)
        File.join(FIXTURES_PATH, name)
      end

      def load_fixture(name)
        JSON.parse(File.read(fixture_path(name)))
      end

      # --- Identification ---

      def test_detects_ccv2_by_spec_field
        hash = load_fixture("ccv2_min.json")
        version = CharacterCard.detect_version(hash)

        assert_equal :v2, version
      end

      def test_accepts_spec_version_starting_with_2
        hash = load_fixture("ccv2_min.json")
        character = CharacterCard.load(hash)

        assert character.v2?
        assert_equal :v2, character.source_version
      end

      # --- Data Location ---

      def test_reads_fields_from_data_object
        hash = load_fixture("ccv2_min.json")
        character = CharacterCard.load(hash)

        assert_equal "Alice", character.data.name
        assert_equal "A friendly assistant.", character.data.description
        assert_equal "Helpful and kind.", character.data.personality
        assert_equal "You are chatting with Alice.", character.data.scenario
      end

      def test_requires_data_object
        # CCv2 spec requires the data object - TavernKit enforces this
        hash = {
          "spec" => "chara_card_v2",
          "spec_version" => "2.0",
          "name" => "Fallback",
          "description" => "Root-level description",
        }

        assert_raises(InvalidCardError) do
          CharacterCard.load(hash)
        end
      end

      # --- Field Parsing ---

      def test_parses_core_fields
        hash = load_fixture("ccv2_min.json")
        character = CharacterCard.load(hash)

        assert_equal "Alice", character.data.name
        assert_equal "A friendly assistant.", character.data.description
        assert_equal "Helpful and kind.", character.data.personality
        assert_equal "You are chatting with Alice.", character.data.scenario
        assert_equal "Hello! How can I help you today?", character.data.first_mes
        assert_includes character.data.mes_example, "{{user}}: Hi there."
      end

      def test_parses_prompt_override_fields
        hash = load_fixture("ccv2_with_overrides.json")
        character = CharacterCard.load(hash)

        assert_equal "You are {{char}}. {{original}}", character.data.system_prompt
        assert_equal "Remember to stay mysterious. {{original}}", character.data.post_history_instructions
      end

      def test_parses_alternate_greetings
        hash = load_fixture("ccv2_with_overrides.json")
        character = CharacterCard.load(hash)

        assert_kind_of Array, character.data.alternate_greetings
        assert_equal 2, character.data.alternate_greetings.size
        assert_includes character.data.alternate_greetings, "Ah, another soul seeking answers."
      end

      def test_parses_metadata_fields
        hash = load_fixture("ccv2_min.json")
        character = CharacterCard.load(hash)

        assert_equal ["test", "minimal"], character.data.tags
        assert_equal "TavernKit", character.data.creator
        assert_equal "1.0.0", character.data.character_version
      end

      # --- Extensions ---

      def test_preserves_extensions_on_load
        hash = load_fixture("ccv2_min.json")
        character = CharacterCard.load(hash)

        assert_kind_of Hash, character.data.extensions
        assert_equal({ "key" => "value" }, character.data.extensions["custom_app_data"])
      end

      def test_preserves_extensions_on_roundtrip
        hash = load_fixture("ccv2_min.json")
        character = CharacterCard.load(hash)
        exported = CharacterCard.export_v2(character)

        assert_equal({ "key" => "value" }, exported["data"]["extensions"]["custom_app_data"])
      end

      # --- Character Book ---

      def test_parses_character_book_entries
        hash = load_fixture("ccv2_with_overrides.json")
        character = CharacterCard.load(hash)

        assert_kind_of Hash, character.data.character_book
        entries = character.data.character_book["entries"]
        assert_kind_of Array, entries
        assert_equal 2, entries.size

        first_entry = entries.first
        assert_equal ["magic", "spell"], first_entry["keys"]
        assert_includes first_entry["content"], "ancient magic"
      end

      def test_preserves_character_book_unknown_fields
        hash = load_fixture("ccv2_with_overrides.json")
        hash["data"]["character_book"]["custom_field"] = "preserved"

        character = CharacterCard.load(hash)
        exported = CharacterCard.export_v2(character)

        assert_equal "preserved", exported["data"]["character_book"]["custom_field"]
      end

      # --- Export ---

      def test_export_v2_writes_correct_spec
        hash = load_fixture("ccv2_min.json")
        character = CharacterCard.load(hash)
        exported = CharacterCard.export_v2(character)

        assert_equal "chara_card_v2", exported["spec"]
        assert_equal "2.0", exported["spec_version"]
      end

      def test_export_v2_writes_data_object
        hash = load_fixture("ccv2_min.json")
        character = CharacterCard.load(hash)
        exported = CharacterCard.export_v2(character)

        assert_kind_of Hash, exported["data"]
        assert_equal "Alice", exported["data"]["name"]
      end

      def test_export_v2_data_contains_all_required_fields
        hash = load_fixture("ccv2_min.json")
        character = CharacterCard.load(hash)
        exported = CharacterCard.export_v2(character)

        data = exported["data"]

        # All CCv2 fields should be present in data
        assert_equal "Alice", data["name"]
        assert_equal "A friendly assistant.", data["description"]
        assert_equal "Helpful and kind.", data["personality"]
        assert_equal "You are chatting with Alice.", data["scenario"]
        assert data.key?("first_mes")
        assert data.key?("mes_example")
        assert data.key?("tags")
        assert data.key?("creator")
        assert data.key?("character_version")
        assert data.key?("extensions")
      end

      def test_export_v2_preserves_v3_fields_in_extensions
        # Load a V3 card and export as V2
        hash = load_fixture("ccv3_st_export_like.json")
        character = CharacterCard.load(hash)
        exported = CharacterCard.export_v2(character)

        # V3-only fields should be preserved in extensions
        assert_kind_of Hash, exported["data"]["extensions"]
        v3_extras = exported["data"]["extensions"]["cc_extractor/v3"]

        assert_kind_of Hash, v3_extras, "V3 extras should be preserved under cc_extractor/v3 key"

        # Check V3-specific fields are preserved
        assert_equal ["Warriors, we stand together!", "My allies, the battle begins."],
                     v3_extras["group_only_greetings"]
        assert_equal "Princess D", v3_extras["nickname"]
      end
    end
  end
end
