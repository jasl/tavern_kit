# frozen_string_literal: true

require "test_helper"
require "zip"

module CharacterImport
  class CharxImporterTest < ActiveSupport::TestCase
    setup do
      @importer = CharxImporter.new
      @fixtures_path = Rails.root.join("test/fixtures/files/characters")
    end

    # === Real Fixture Tests ===

    test "imports real CharX fixture file" do
      charx_path = @fixtures_path.join("test_character.charx")
      io = File.open(charx_path, "rb")

      result = @importer.call(io, filename: "test_character.charx")

      assert result.success?, "Expected success but got: #{result.error}"
      assert_equal "Test Character", result.character.name
      assert_equal 3, result.character.spec_version
      assert result.character.portrait.attached?
    ensure
      io&.close
    end

    test "imports CharX with embedded assets" do
      charx_path = @fixtures_path.join("test_character.charx")
      io = File.open(charx_path, "rb")

      result = @importer.call(io, filename: "test_character.charx")

      assert result.success?
      character = result.character

      # Should have character assets extracted
      assert character.character_assets.count >= 1
    ensure
      io&.close
    end

    test "imports CharX with lorebook" do
      charx_path = @fixtures_path.join("test_character_with_lorebook.charx")
      io = File.open(charx_path, "rb")

      result = @importer.call(io, filename: "test_character_with_lorebook.charx")

      assert result.success?, "Expected success but got: #{result.error}"
      character = result.character
      assert_equal "Lorebook Test Character", character.name

      # Check lorebook data
      assert character.data["character_book"].present?
      lorebook = character.data["character_book"]
      assert_equal "Test Lorebook", lorebook["name"]
      assert_equal 2, lorebook["entries"].length
    ensure
      io&.close
    end

    test "detects duplicate CharX import" do
      charx_path = @fixtures_path.join("test_character.charx")

      # First import
      io1 = File.open(charx_path, "rb")
      result1 = @importer.call(io1, filename: "test_character.charx")
      io1.close
      assert result1.success?

      # Second import should return duplicate
      io2 = File.open(charx_path, "rb")
      result2 = @importer.call(io2, filename: "test_character.charx")
      io2.close

      assert result2.duplicate?
      assert_equal result1.character, result2.character
    end

    # === CharX Archive Creation Helper ===

    def create_charx_archive(card_data, assets: {})
      buffer = StringIO.new
      buffer.set_encoding("ASCII-8BIT")

      Zip::OutputStream.write_buffer(buffer) do |zos|
        # Write card.json
        zos.put_next_entry("card.json")
        zos.write(card_data.to_json)

        # Write assets
        assets.each do |path, content|
          zos.put_next_entry(path)
          zos.write(content)
        end
      end

      buffer.rewind
      buffer.string
    end

    # === Successful Import ===

    test "imports valid CharX archive" do
      card_data = {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => {
          "name" => "CharX Character",
          "description" => "A character from CharX format",
        },
      }

      charx_content = create_charx_archive(card_data)
      io = StringIO.new(charx_content)

      result = @importer.call(io, filename: "test.charx")

      assert result.success?
      assert_equal "CharX Character", result.character.name
      assert_equal 3, result.character.spec_version
    end

    test "extracts assets from CharX" do
      png_content = "\x89PNG\r\n\x1a\n" + ("x" * 100)

      card_data = {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => {
          "name" => "Character with Assets",
          "assets" => [
            {
              "type" => "icon",
              "name" => "main",
              "uri" => "embeded://assets/icon/main.png",
              "ext" => "png",
            },
          ],
        },
      }

      charx_content = create_charx_archive(
        card_data,
        assets: { "assets/icon/main.png" => png_content }
      )
      io = StringIO.new(charx_content)

      result = @importer.call(io, filename: "test.charx")

      assert result.success?
      character = result.character

      # Should have portrait attached
      assert character.portrait.attached?

      # Should have character asset record
      assert_equal 1, character.character_assets.count
      asset = character.character_assets.first
      assert_equal "main", asset.name
      assert_equal "icon", asset.kind
    end

    test "handles multiple asset types" do
      png_content = "\x89PNG\r\n\x1a\n" + ("x" * 50)
      jpg_content = "\xFF\xD8\xFF\xE0" + ("y" * 50)

      card_data = {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => {
          "name" => "Multi-Asset Character",
          "assets" => [
            { "type" => "icon", "name" => "main", "uri" => "embeded://assets/icon/main.png", "ext" => "png" },
            { "type" => "emotion", "name" => "happy", "uri" => "embeded://assets/emotions/happy.jpg", "ext" => "jpg" },
            { "type" => "background", "name" => "default", "uri" => "embeded://assets/background/default.png", "ext" => "png" },
          ],
        },
      }

      charx_content = create_charx_archive(
        card_data,
        assets: {
          "assets/icon/main.png" => png_content,
          "assets/emotions/happy.jpg" => jpg_content,
          "assets/background/default.png" => png_content,
        }
      )
      io = StringIO.new(charx_content)

      result = @importer.call(io, filename: "test.charx")

      assert result.success?
      character = result.character

      assert_equal 3, character.character_assets.count
      assert character.character_assets.icons.exists?(name: "main")
      assert character.character_assets.emotions.exists?(name: "happy")
      assert character.character_assets.backgrounds.exists?(name: "default")
    end

    # === Duplicate Detection ===

    test "returns duplicate for same CharX file" do
      card_data = {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => { "name" => "Duplicate Test" },
      }

      charx_content = create_charx_archive(card_data)

      # First import
      io1 = StringIO.new(charx_content)
      result1 = @importer.call(io1, filename: "first.charx")
      assert result1.success?

      # Second import
      io2 = StringIO.new(charx_content)
      result2 = @importer.call(io2, filename: "second.charx")
      assert result2.duplicate?
      assert_equal result1.character.id, result2.character.id
    end

    # === Error Handling ===

    test "returns failure for missing card.json" do
      # Create empty ZIP
      buffer = StringIO.new
      buffer.set_encoding("ASCII-8BIT")
      Zip::OutputStream.write_buffer(buffer) do |zos|
        zos.put_next_entry("module.risum")
        zos.write("optional risu module")
      end
      buffer.rewind

      result = @importer.call(buffer, filename: "invalid.charx")

      assert result.failure?
      assert_includes result.error, "missing card.json"
    end

    test "returns failure for invalid JSON in card.json" do
      buffer = StringIO.new
      buffer.set_encoding("ASCII-8BIT")
      Zip::OutputStream.write_buffer(buffer) do |zos|
        zos.put_next_entry("card.json")
        zos.write("{ invalid json }")
      end
      buffer.rewind

      result = @importer.call(buffer, filename: "invalid.charx")

      assert result.failure?
      assert_includes result.error, "Invalid JSON"
    end

    test "returns failure for invalid ZIP" do
      io = StringIO.new("not a zip file")

      result = @importer.call(io, filename: "invalid.charx")

      assert result.failure?
      assert_includes result.error, "Invalid CharX"
    end

    # === Asset URI Schemes ===

    test "resolves embeded:// URIs" do
      content = "\x89PNG\r\n\x1a\n" + ("x" * 10)
      card_data = {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => {
          "name" => "Embeded URI Test",
          "assets" => [
            { "type" => "icon", "name" => "test", "uri" => "embeded://assets/path/to/asset.png", "ext" => "png" },
          ],
        },
      }

      charx_content = create_charx_archive(
        card_data,
        assets: { "assets/path/to/asset.png" => content }
      )
      io = StringIO.new(charx_content)

      result = @importer.call(io, filename: "test.charx")

      assert result.success?
      assert_equal 1, result.character.character_assets.count
    end

    test "skips ccdefault: URIs" do
      card_data = {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => {
          "name" => "Default URI Test",
          "assets" => [
            { "type" => "icon", "name" => "main", "uri" => "ccdefault:", "ext" => "png" },
          ],
        },
      }

      charx_content = create_charx_archive(card_data)
      io = StringIO.new(charx_content)

      result = @importer.call(io, filename: "test.charx")

      assert result.success?
      # ccdefault: URI should be skipped (no content to extract)
      assert_equal 0, result.character.character_assets.count
    end

    # === Fallback Icon ===

    test "attaches fallback icon from assets directory" do
      png_content = "\x89PNG\r\n\x1a\n" + ("x" * 50)

      card_data = {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => {
          "name" => "Fallback Icon Test",
          "assets" => [],
        },
      }

      charx_content = create_charx_archive(
        card_data,
        assets: { "assets/icon/default.png" => png_content }
      )
      io = StringIO.new(charx_content)

      result = @importer.call(io, filename: "test.charx")

      assert result.success?
      assert result.character.portrait.attached?
    end

    # === JPEG-Embedded CharX ===

    test "extracts CharX from JPEG wrapper" do
      card_data = {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => { "name" => "JPEG Wrapped Character" },
      }

      charx_content = create_charx_archive(card_data)

      # Create JPEG header + CharX content
      jpeg_header = "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00".b + ("x" * 50).b
      jpeg_wrapped = jpeg_header + charx_content.b

      io = StringIO.new(jpeg_wrapped)
      result = @importer.call(io, filename: "test.jpg")

      assert result.success?
      assert_equal "JPEG Wrapped Character", result.character.name
    end

    # === Security Hardening ===

    test "rejects CharX with unsafe path traversal entry" do
      card_data = {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => { "name" => "Unsafe Path" },
      }

      # Include an unsafe entry name
      buffer = StringIO.new
      buffer.set_encoding("ASCII-8BIT")
      Zip::OutputStream.write_buffer(buffer) do |zos|
        zos.put_next_entry("card.json")
        zos.write(card_data.to_json)
        zos.put_next_entry("../evil.png")
        zos.write("\x89PNG\r\n\x1a\n" + "x")
      end
      buffer.rewind

      result = @importer.call(buffer, filename: "unsafe.charx")

      assert result.failure?
      assert_includes result.error, "unsafe path"
    end

    test "rejects CharX with too many entries" do
      card_data = {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => { "name" => "Too Many" },
      }

      buffer = StringIO.new
      buffer.set_encoding("ASCII-8BIT")

      Zip::OutputStream.write_buffer(buffer) do |zos|
        zos.put_next_entry("card.json")
        zos.write(card_data.to_json)

        (CharacterImport::CharxImporter::MAX_ZIP_ENTRIES + 1).times do |i|
          zos.put_next_entry("assets/files/#{i}.png")
          zos.write("\x89PNG\r\n\x1a\n" + "x")
        end
      end
      buffer.rewind

      result = @importer.call(buffer, filename: "too_many.charx")

      assert result.failure?
      assert_includes result.error, "too many entries"
    end

    test "rejects CharX with oversized card.json" do
      padding = "x" * CharacterImport::CharxImporter::MAX_CARD_JSON_BYTES
      card_data = {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => { "name" => "Huge Card", "description" => padding },
      }

      buffer = StringIO.new
      buffer.set_encoding("ASCII-8BIT")
      Zip::OutputStream.write_buffer(buffer) do |zos|
        zos.put_next_entry("card.json")
        zos.write(card_data.to_json)
      end
      buffer.rewind

      result = @importer.call(buffer, filename: "huge_card.charx")

      assert result.failure?
      assert_includes result.error, "card.json too large"
    end
  end
end
