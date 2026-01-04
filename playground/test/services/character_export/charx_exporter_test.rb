# frozen_string_literal: true

require "test_helper"
require "zip"

module CharacterExport
  class CharxExporterTest < ActiveSupport::TestCase
    setup do
      @fixtures_path = Rails.root.join("test/fixtures/files/characters")
      @portrait_path = @fixtures_path.join("test_character.png")

      @character = Character.create!(
        name: "Test Character",
        spec_version: 3,
        status: "ready",
        data: {
          "name" => "Test Character",
          "description" => "A test character for CharX export",
          "personality" => "Friendly",
          "first_mes" => "Hello from CharX!",
          "tags" => ["test", "charx"],
          "creator" => "TavernKit Test",
          "character_book" => {
            "name" => "Test Lorebook",
            "entries" => [
              { "keys" => ["test"], "content" => "Test lore entry" },
            ],
          },
        },
      )

      # Attach portrait
      @character.portrait.attach(
        io: File.open(@portrait_path, "rb"),
        filename: "portrait.png",
        content_type: "image/png",
      )
    end

    teardown do
      @character.destroy! if @character.persisted?
    end

    # === Basic Export ===

    test "exports character to CharX (ZIP) binary data" do
      exporter = CharxExporter.new(@character)

      charx_data = exporter.call

      assert charx_data.is_a?(String)
      # ZIP magic bytes
      assert charx_data.start_with?("PK\x03\x04".b)
    end

    test "exported CharX contains card.json" do
      exporter = CharxExporter.new(@character)

      charx_data = exporter.call

      # Open as ZIP and check for card.json
      Zip::File.open_buffer(charx_data) do |zip|
        assert zip.find_entry("card.json").present?

        card_json = JSON.parse(zip.read("card.json"))
        assert_equal "chara_card_v3", card_json["spec"]
        assert_equal "Test Character", card_json["data"]["name"]
      end
    end

    test "exported CharX contains main portrait" do
      exporter = CharxExporter.new(@character)

      charx_data = exporter.call

      Zip::File.open_buffer(charx_data) do |zip|
        main_entry = zip.find_entry("assets/icon/image/main.png")
        assert main_entry.present?

        content = zip.read("assets/icon/image/main.png")
        assert content.start_with?("\x89PNG".b)
      end
    end

    # === Assets Export ===

    test "exported CharX contains character assets" do
      # Add some assets
      blob1 = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("emotion1 content"),
        filename: "happy.png",
        content_type: "image/png",
      )
      @character.character_assets.create!(
        name: "happy",
        kind: "emotion",
        ext: "png",
        blob: blob1,
        content_sha256: Digest::SHA256.hexdigest("emotion1 content"),
      )

      blob2 = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("emotion2 content"),
        filename: "sad.png",
        content_type: "image/png",
      )
      @character.character_assets.create!(
        name: "sad",
        kind: "emotion",
        ext: "png",
        blob: blob2,
        content_sha256: Digest::SHA256.hexdigest("emotion2 content"),
      )

      exporter = CharxExporter.new(@character)
      charx_data = exporter.call

      Zip::File.open_buffer(charx_data) do |zip|
        assert zip.find_entry("assets/emotion/image/happy.png").present?
        assert zip.find_entry("assets/emotion/image/sad.png").present?

        assert_equal "emotion1 content", zip.read("assets/emotion/image/happy.png")
        assert_equal "emotion2 content", zip.read("assets/emotion/image/sad.png")
      end
    end

    test "card.json includes assets array with charx URIs" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("asset content"),
        filename: "happy.png",
        content_type: "image/png",
      )
      @character.character_assets.create!(
        name: "happy",
        kind: "emotion",
        ext: "png",
        blob: blob,
        content_sha256: Digest::SHA256.hexdigest("asset content"),
      )

      exporter = CharxExporter.new(@character)
      charx_data = exporter.call

      Zip::File.open_buffer(charx_data) do |zip|
        card_json = JSON.parse(zip.read("card.json"))

        assets = card_json["data"]["assets"]
        assert assets.present?

        # Should have main icon + happy emotion
        assert assets.size >= 2

        icon_asset = assets.find { |a| a["name"] == "main" }
        assert icon_asset.present?
        assert_equal "embeded://assets/icon/image/main.png", icon_asset["uri"]

        emotion_asset = assets.find { |a| a["name"] == "happy" }
        assert emotion_asset.present?
        assert_equal "embeded://assets/emotion/image/happy.png", emotion_asset["uri"]
        assert_equal "emotion", emotion_asset["type"]
      end
    end

    # === Without Avatar ===

    test "exports without main portrait when not attached" do
      @character.portrait.purge
      exporter = CharxExporter.new(@character)

      charx_data = exporter.call

      Zip::File.open_buffer(charx_data) do |zip|
        assert zip.find_entry("card.json").present?
        assert_nil zip.find_entry("assets/icon/image/main.png")
      end
    end

    # === File Export ===

    test "exports to file" do
      exporter = CharxExporter.new(@character)
      output_path = Rails.root.join("tmp/test_export.charx")

      begin
        bytes = exporter.export_to_file(output_path)

        assert bytes > 0
        assert File.exist?(output_path)

        content = File.binread(output_path)
        assert content.start_with?("PK\x03\x04".b)
      ensure
        File.delete(output_path) if File.exist?(output_path)
      end
    end

    # === IO Export ===

    test "exports to StringIO" do
      exporter = CharxExporter.new(@character)

      io = exporter.to_io

      assert io.is_a?(StringIO)
      content = io.read
      assert content.start_with?("PK\x03\x04".b)
    end

    # === Metadata ===

    test "suggested_filename returns sanitized name with charx extension" do
      @character.name = "Test Character! @#$%"
      exporter = CharxExporter.new(@character)

      filename = exporter.suggested_filename

      assert filename.end_with?(".charx")
      assert_match(/^[a-zA-Z0-9_\-]+\.charx$/, filename)
    end

    test "content_type returns application/zip" do
      exporter = CharxExporter.new(@character)

      assert_equal "application/zip", exporter.content_type
    end

    # === Data Integrity ===

    test "exported CharX preserves character book" do
      exporter = CharxExporter.new(@character)
      charx_data = exporter.call

      Zip::File.open_buffer(charx_data) do |zip|
        card_json = JSON.parse(zip.read("card.json"))

        book = card_json["data"]["character_book"]
        assert book.present?
        assert_equal "Test Lorebook", book["name"]
        assert_equal 1, book["entries"].size
        assert_equal ["test"], book["entries"][0]["keys"]
      end
    end

    test "exported CharX has modification_date" do
      exporter = CharxExporter.new(@character)
      charx_data = exporter.call

      Zip::File.open_buffer(charx_data) do |zip|
        card_json = JSON.parse(zip.read("card.json"))

        assert card_json["data"]["modification_date"].present?
        assert_kind_of Integer, card_json["data"]["modification_date"]
      end
    end

    # === Round-trip Test ===

    test "exported CharX can be re-imported" do
      asset_bytes = File.binread(@portrait_path)

      # Add an asset
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(asset_bytes),
        filename: "happy.png",
        content_type: "image/png",
      )
      @character.character_assets.create!(
        name: "happy",
        kind: "emotion",
        ext: "png",
        blob: blob,
        content_sha256: Digest::SHA256.hexdigest(asset_bytes),
      )

      exporter = CharxExporter.new(@character)
      charx_data = exporter.call

      # Create temp file for import test
      temp_path = Rails.root.join("tmp/roundtrip_test.charx")
      begin
        File.binwrite(temp_path, charx_data)

        # Import using the CharxImporter
        importer = CharacterImport::CharxImporter.new
        result = importer.call(File.open(temp_path, "rb"), filename: "roundtrip_test.charx")

        assert result.success?, "Import should succeed: #{result.error}"
        imported = result.character

        assert_equal @character.name, imported.name
        assert_equal @character.data["description"], imported.data["description"]
        assert_equal @character.data["first_mes"], imported.data["first_mes"]

        # Check character_book
        assert_equal @character.data["character_book"]["name"],
                     imported.data["character_book"]["name"]

        # Check assets were imported (at least the happy emotion)
        assert imported.character_assets.any?
      ensure
        File.delete(temp_path) if File.exist?(temp_path)
        imported&.destroy if imported&.persisted?
      end
    end
  end
end
