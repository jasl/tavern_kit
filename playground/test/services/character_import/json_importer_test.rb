# frozen_string_literal: true

require "test_helper"

module CharacterImport
  class JsonImporterTest < ActiveSupport::TestCase
    setup do
      @importer = JsonImporter.new
    end

    # === Successful Import ===

    test "imports minimal v2 JSON" do
      fixture_path = file_fixture("characters/minimal_v2.json")
      io = File.open(fixture_path, "rb")

      result = @importer.execute(io, filename: "minimal_v2.json")
      io.close

      assert result.success?
      assert_instance_of Character, result.character

      character = result.character
      assert_equal "Test Character V2", character.name
      assert_equal 2, character.spec_version
      assert_equal "ready", character.status
      assert_equal "Helpful and friendly", character.personality
      assert_includes character.tags, "test"
      assert_not_nil character.file_sha256
    end

    test "imports minimal v3 JSON" do
      fixture_path = file_fixture("characters/minimal_v3.json")
      io = File.open(fixture_path, "rb")

      result = @importer.execute(io, filename: "minimal_v3.json")
      io.close

      assert result.success?

      character = result.character
      assert_equal "Test Character V3", character.name
      assert_equal 3, character.spec_version
      assert_equal "TestBot", character.nickname
      assert_equal %w[en ja], character.supported_languages
      assert character.v3?
    end

    test "imports character with lorebook" do
      fixture_path = file_fixture("characters/with_lorebook.json")
      io = File.open(fixture_path, "rb")

      result = @importer.execute(io, filename: "with_lorebook.json")
      io.close

      assert result.success?

      character = result.character
      assert_not_nil character.character_book
      assert_equal "Test Lorebook", character.character_book.name
      assert_equal 2, character.character_book.entries.size
    end

    test "attaches default portrait for JSON imports" do
      fixture_path = file_fixture("characters/minimal_v2.json")
      io = File.open(fixture_path, "rb")

      result = @importer.execute(io, filename: "minimal_v2.json")
      io.close

      assert result.success?
      assert result.character.portrait.attached?, "Default portrait should be attached"
      assert_equal "default_portrait.png", result.character.portrait.filename.to_s
    end

    test "sets file_sha256 for deduplication" do
      fixture_path = file_fixture("characters/minimal_v2.json")
      content = File.read(fixture_path)
      expected_sha = Digest::SHA256.hexdigest(content)

      io = StringIO.new(content)
      result = @importer.execute(io, filename: "test.json")

      assert_equal expected_sha, result.character.file_sha256
    end

    # === Duplicate Detection ===

    test "returns duplicate result for same file" do
      fixture_path = file_fixture("characters/minimal_v2.json")

      # First import
      io1 = File.open(fixture_path, "rb")
      result1 = @importer.execute(io1, filename: "first.json")
      io1.close

      assert result1.success?

      # Second import of same content
      io2 = File.open(fixture_path, "rb")
      result2 = @importer.execute(io2, filename: "second.json")
      io2.close

      assert result2.duplicate?
      assert_equal result1.character.id, result2.character.id
    end

    # === Import from Hash ===

    test "import_from_hash creates character from hash" do
      card_hash = {
        "spec" => "chara_card_v2",
        "spec_version" => "2.0",
        "data" => {
          "name" => "Hash Character",
          "description" => "Created from hash",
        },
      }

      character = @importer.import_from_hash(card_hash)

      assert_instance_of Character, character
      assert_equal "Hash Character", character.name
      assert_equal 2, character.spec_version
    end

    test "import_from_hash accepts JSON string" do
      json = '{"spec":"chara_card_v2","spec_version":"2.0","data":{"name":"JSON String Char"}}'

      character = @importer.import_from_hash(json)

      assert_equal "JSON String Char", character.name
    end

    test "import_from_hash attaches default portrait by default" do
      card_hash = {
        "spec" => "chara_card_v2",
        "spec_version" => "2.0",
        "data" => { "name" => "Portrait Test" },
      }

      character = @importer.import_from_hash(card_hash)

      assert character.portrait.attached?, "Default portrait should be attached"
    end

    test "import_from_hash can skip default portrait" do
      card_hash = {
        "spec" => "chara_card_v2",
        "spec_version" => "2.0",
        "data" => { "name" => "No Portrait" },
      }

      character = @importer.import_from_hash(card_hash, attach_portrait: false)

      assert_not character.portrait.attached?, "Portrait should not be attached"
    end

    # === Validation Errors ===

    test "returns failure for missing name" do
      fixture_path = file_fixture("characters/invalid_missing_name.json")
      io = File.open(fixture_path, "rb")

      result = @importer.execute(io, filename: "invalid.json")
      io.close

      assert result.failure?
      assert_includes result.error, "Missing name"
    end

    test "returns failure for missing spec" do
      fixture_path = file_fixture("characters/invalid_missing_spec.json")
      io = File.open(fixture_path, "rb")

      result = @importer.execute(io, filename: "invalid.json")
      io.close

      assert result.failure?
      assert_includes result.error, "Missing spec"
    end

    test "returns failure for invalid JSON" do
      io = StringIO.new("{ invalid json }")

      result = @importer.execute(io, filename: "invalid.json")

      assert result.failure?
      assert_includes result.error, "Invalid JSON"
    end

    test "returns failure for unknown spec version" do
      json = '{"spec":"chara_card_v99","spec_version":"99.0","data":{"name":"Future"}}'
      io = StringIO.new(json)

      result = @importer.execute(io, filename: "future.json")

      assert result.failure?
      assert_includes result.error, "Unknown spec"
    end

    test "returns failure for non-object data" do
      json = '{"spec":"chara_card_v2","spec_version":"2.0","data":"not an object"}'
      io = StringIO.new(json)

      result = @importer.execute(io, filename: "bad.json")

      assert result.failure?
      assert_includes result.error, "Missing data"
    end
  end
end
