# frozen_string_literal: true

require "test_helper"

module CharacterExport
  class JsonExporterTest < ActiveSupport::TestCase
    setup do
      @character = Character.create!(
        name: "Test Character",
        spec_version: 3,
        status: "ready",
        data: {
          "name" => "Test Character",
          "description" => "A test character for export",
          "personality" => "Friendly and helpful",
          "scenario" => "Testing exports",
          "first_mes" => "Hello! I'm a test character.",
          "mes_example" => "{{char}}: Hi!\n{{user}}: Hello!",
          "creator_notes" => "Created for testing",
          "system_prompt" => "You are a test character",
          "post_history_instructions" => "Be helpful",
          "alternate_greetings" => ["Hi there!", "Greetings!"],
          "tags" => ["test", "export"],
          "creator" => "TavernKit Test",
          "character_version" => "1.0",
          "group_only_greetings" => ["Group hello!"],
        },
      )
    end

    teardown do
      @character.destroy! if @character.persisted?
    end

    # === Basic Export ===

    test "exports character to JSON string" do
      exporter = JsonExporter.new(@character)

      json = exporter.execute

      assert json.is_a?(String)
      parsed = JSON.parse(json)
      assert_equal "Test Character", parsed["data"]["name"]
    end

    test "exports valid JSON format" do
      exporter = JsonExporter.new(@character)

      json = exporter.execute

      assert_nothing_raised { JSON.parse(json) }
    end

    test "exports pretty-printed JSON" do
      exporter = JsonExporter.new(@character)

      json = exporter.execute

      # Pretty-printed JSON has newlines and indentation
      assert json.include?("\n")
      assert json.include?("  ")
    end

    # === Version Export ===

    test "exports as CCv3 by default for v3 character" do
      exporter = JsonExporter.new(@character)

      json = exporter.execute
      parsed = JSON.parse(json)

      assert_equal "chara_card_v3", parsed["spec"]
      assert_equal "3.0", parsed["spec_version"]
    end

    test "exports as CCv2 when version option is 2" do
      exporter = JsonExporter.new(@character, version: 2)

      json = exporter.execute
      parsed = JSON.parse(json)

      assert_equal "chara_card_v2", parsed["spec"]
      assert_equal "2.0", parsed["spec_version"]
    end

    test "CCv2 export respects spec constraints" do
      exporter = JsonExporter.new(@character, version: 2)

      json = exporter.execute
      parsed = JSON.parse(json)

      # V2 should not have V3-only fields
      # But the data should still have standard fields
      assert parsed["data"]["name"].present?
      assert parsed["data"]["description"].present?
    end

    # === Field Preservation ===

    test "preserves all standard fields in export" do
      exporter = JsonExporter.new(@character)

      json = exporter.execute
      data = JSON.parse(json)["data"]

      assert_equal "Test Character", data["name"]
      assert_equal "A test character for export", data["description"]
      assert_equal "Friendly and helpful", data["personality"]
      assert_equal "Testing exports", data["scenario"]
      assert_equal "Hello! I'm a test character.", data["first_mes"]
      assert_equal ["Hi there!", "Greetings!"], data["alternate_greetings"]
      assert_equal ["test", "export"], data["tags"]
      assert_equal "TavernKit Test", data["creator"]
    end

    test "preserves character_book if present" do
      # Convert data to hash, merge, and create new Schema
      current_data_hash = JSON.parse(@character.data.to_json)
      current_data_hash["character_book"] = {
        "name" => "My Lorebook",
        "entries" => [
          { "keys" => ["test"], "content" => "Test entry" },
        ],
      }
      @character.data = TavernKit::Character::Schema.new(current_data_hash.deep_symbolize_keys)
      exporter = JsonExporter.new(@character)

      json = exporter.execute
      data = JSON.parse(json)["data"]

      assert data["character_book"].present?
      assert_equal "My Lorebook", data["character_book"]["name"]
      assert_equal 1, data["character_book"]["entries"].size
    end

    # === File Export ===

    test "exports to file" do
      exporter = JsonExporter.new(@character)
      output_path = Rails.root.join("tmp/test_export.json")

      begin
        bytes = exporter.export_to_file(output_path)

        assert bytes > 0
        assert File.exist?(output_path)

        content = File.read(output_path)
        parsed = JSON.parse(content)
        assert_equal "Test Character", parsed["data"]["name"]
      ensure
        File.delete(output_path) if File.exist?(output_path)
      end
    end

    # === IO Export ===

    test "exports to StringIO" do
      exporter = JsonExporter.new(@character)

      io = exporter.to_io

      assert io.is_a?(StringIO)
      parsed = JSON.parse(io.read)
      assert_equal "Test Character", parsed["data"]["name"]
    end

    # === Metadata ===

    test "suggested_filename returns sanitized name with json extension" do
      @character.name = "Test Character! @#$%"
      exporter = JsonExporter.new(@character)

      filename = exporter.suggested_filename

      assert filename.end_with?(".json")
      assert_match(/^[a-zA-Z0-9_\-]+\.json$/, filename)
    end

    test "content_type returns application/json" do
      exporter = JsonExporter.new(@character)

      assert_equal "application/json", exporter.content_type
    end

    # === Round-trip Test ===

    test "exported JSON can be re-imported" do
      exporter = JsonExporter.new(@character)
      json = exporter.execute

      # Create temp file for import test
      temp_path = Rails.root.join("tmp/roundtrip_test.json")
      begin
        File.write(temp_path, json)

        # Import using the JsonImporter
        importer = CharacterImport::JsonImporter.new
        result = importer.call(File.open(temp_path, "rb"), filename: "roundtrip_test.json")

        assert result.success?, "Import should succeed: #{result.error}"
        imported = result.character

        assert_equal @character.name, imported.name
        assert_equal @character.data.description, imported.data.description
        assert_equal @character.data.first_mes, imported.data.first_mes
      ensure
        File.delete(temp_path) if File.exist?(temp_path)
        imported&.destroy if imported&.persisted?
      end
    end
  end
end
