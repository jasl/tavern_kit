# frozen_string_literal: true

require "test_helper"

module CharacterImport
  class BaseTest < ActiveSupport::TestCase
    # Use a concrete subclass for testing protected methods
    class TestableImporter < Base
      def call(io, filename:)
        content = read_and_rewind(io)
        card_hash = parse_json(content)
        validate_card!(card_hash)
        create_character(card_hash, file_sha256: compute_sha256(content))
      end

      # Expose protected methods for testing
      public :parse_json, :validate_card!, :detect_spec_version,
             :compute_sha256, :read_and_rewind, :create_character
    end

    setup do
      @importer = TestableImporter.new
    end

    # === ImportResult ===

    test "ImportResult.success creates success result" do
      character = characters(:ready_v2)
      result = ImportResult.success(character)

      assert result.success?
      assert_not result.failure?
      assert_not result.duplicate?
      assert_equal character, result.character
      assert_nil result.error
    end

    test "ImportResult.failure creates failure result" do
      result = ImportResult.failure("Test error")

      assert result.failure?
      assert_not result.success?
      assert_not result.duplicate?
      assert_nil result.character
      assert_equal "Test error", result.error
    end

    test "ImportResult.duplicate creates duplicate result" do
      character = characters(:ready_v2)
      result = ImportResult.duplicate(character)

      assert result.duplicate?
      assert_not result.success?
      assert_not result.failure?
      assert_equal character, result.character
    end

    # === JSON Parsing ===

    test "parse_json parses valid JSON string" do
      json = '{"name": "test", "value": 123}'
      result = @importer.parse_json(json)

      assert_equal({ "name" => "test", "value" => 123 }, result)
    end

    test "parse_json parses from IO" do
      io = StringIO.new('{"key": "value"}')
      result = @importer.parse_json(io)

      assert_equal({ "key" => "value" }, result)
    end

    test "parse_json raises InvalidCardError for invalid JSON" do
      assert_raises(InvalidCardError) do
        @importer.parse_json("not valid json {")
      end
    end

    # === Card Validation ===

    test "validate_card! accepts valid v2 card" do
      card = {
        "spec" => "chara_card_v2",
        "data" => { "name" => "Test" },
      }

      assert_nothing_raised { @importer.validate_card!(card) }
    end

    test "validate_card! accepts valid v3 card" do
      card = {
        "spec" => "chara_card_v3",
        "data" => { "name" => "Test" },
      }

      assert_nothing_raised { @importer.validate_card!(card) }
    end

    test "validate_card! raises for non-hash" do
      assert_raises(InvalidCardError) { @importer.validate_card!("string") }
      assert_raises(InvalidCardError) { @importer.validate_card!([]) }
      assert_raises(InvalidCardError) { @importer.validate_card!(nil) }
    end

    test "validate_card! raises for missing spec" do
      card = { "data" => { "name" => "Test" } }

      error = assert_raises(InvalidCardError) { @importer.validate_card!(card) }
      assert_includes error.message, "Missing spec"
    end

    test "validate_card! raises for missing data" do
      card = { "spec" => "chara_card_v2" }

      error = assert_raises(InvalidCardError) { @importer.validate_card!(card) }
      assert_includes error.message, "Missing data"
    end

    test "validate_card! raises for missing name" do
      card = { "spec" => "chara_card_v2", "data" => { "description" => "No name" } }

      error = assert_raises(InvalidCardError) { @importer.validate_card!(card) }
      assert_includes error.message, "Missing name"
    end

    # === Spec Version Detection ===

    test "detect_spec_version returns 2 for v2 spec" do
      card = { "spec" => "chara_card_v2" }
      assert_equal 2, @importer.detect_spec_version(card)
    end

    test "detect_spec_version returns 3 for v3 spec" do
      card = { "spec" => "chara_card_v3" }
      assert_equal 3, @importer.detect_spec_version(card)
    end

    test "detect_spec_version raises for unknown spec" do
      card = { "spec" => "unknown_spec" }

      error = assert_raises(InvalidCardError) { @importer.detect_spec_version(card) }
      assert_includes error.message, "Unknown spec"
    end

    # === Utility Methods ===

    test "compute_sha256 returns consistent hash" do
      content = "test content for hashing"
      expected = Digest::SHA256.hexdigest(content)

      assert_equal expected, @importer.compute_sha256(content)
    end

    test "read_and_rewind reads content and rewinds" do
      content = "test content"
      io = StringIO.new(content)

      result = @importer.read_and_rewind(io)

      assert_equal content, result
      assert_equal 0, io.pos # Should be rewound
    end

    # === Character Creation ===

    test "create_character creates v2 character" do
      card = {
        "spec" => "chara_card_v2",
        "data" => {
          "name" => "Created Character",
          "description" => "Test description",
        },
      }

      character = @importer.create_character(card, file_sha256: "abc123")

      assert_instance_of Character, character
      assert character.persisted?
      assert_equal "Created Character", character.name
      assert_equal 2, character.spec_version
      assert_equal "ready", character.status
      assert_equal "abc123", character.file_sha256
    end

    test "create_character creates v3 character with all fields" do
      card = {
        "spec" => "chara_card_v3",
        "data" => {
          "name" => "V3 Character",
          "nickname" => "V3Nick",
          "personality" => "Friendly",
          "tags" => ["v3", "test"],
        },
      }

      character = @importer.create_character(card)

      assert_equal 3, character.spec_version
      assert_equal "V3Nick", character.nickname
      assert_equal %w[v3 test], character.tags
    end
  end
end
