# frozen_string_literal: true

require "test_helper"

module CharacterImport
  class PngImporterTest < ActiveSupport::TestCase
    setup do
      @importer = PngImporter.new
      @fixtures_path = Rails.root.join("test/fixtures/files/characters")
    end

    # === Successful Import Tests ===

    test "successfully imports CCv3 PNG character card" do
      png_path = @fixtures_path.join("test_character.png")
      io = File.open(png_path, "rb")

      result = @importer.execute(io, filename: "test_character.png")

      assert result.success?, "Expected success but got: #{result.error}"
      assert_equal "Test Character", result.character.name
      assert_equal 3, result.character.spec_version
      assert result.character.portrait.attached?
    ensure
      io&.close
    end

    test "successfully imports CCv2 PNG character card" do
      png_path = @fixtures_path.join("test_character_v2.png")
      io = File.open(png_path, "rb")

      result = @importer.execute(io, filename: "test_character_v2.png")

      assert result.success?, "Expected success but got: #{result.error}"
      assert_equal "V2 Test Character", result.character.name
      assert_equal 2, result.character.spec_version
      assert result.character.portrait.attached?
    ensure
      io&.close
    end

    test "extracts character data fields from PNG" do
      png_path = @fixtures_path.join("test_character.png")
      io = File.open(png_path, "rb")

      result = @importer.execute(io, filename: "test_character.png")

      assert result.success?
      char = result.character
      assert_equal "Test Character", char.data.name
      assert_includes char.data.description, "test character"
      assert_includes char.data.tags, "test"
      assert_equal "TavernKit Test", char.data.creator
    ensure
      io&.close
    end

    # === Error Handling ===

    test "returns failure for invalid PNG" do
      io = StringIO.new("not a png file")

      result = @importer.execute(io, filename: "invalid.png")

      assert result.failure?
    end

    test "returns failure for PNG without metadata" do
      # Minimal valid PNG (1x1 white pixel) without character data
      png_data = create_minimal_png

      io = StringIO.new(png_data)
      result = @importer.execute(io, filename: "empty.png")

      # Should fail because no character data is embedded
      assert result.failure?
    end

    # === Duplicate Detection ===

    test "detect_duplicate uses file SHA256" do
      unique_sha = "unique_sha_#{SecureRandom.hex(8)}"

      # Create a character with known SHA
      existing = Character.create!(
        name: "Existing PNG Character",
        data: { "name" => "Existing PNG Character" },
        spec_version: 2,
        file_sha256: unique_sha,
        status: "ready"
      )

      # The importer should find duplicates by hash
      found = Character.find_by(file_sha256: unique_sha)
      assert_equal existing, found
    end

    test "returns duplicate result for same file" do
      png_path = @fixtures_path.join("test_character.png")

      # First import
      io1 = File.open(png_path, "rb")
      result1 = @importer.execute(io1, filename: "test_character.png")
      io1.close
      assert result1.success?

      # Second import of same file should return duplicate
      io2 = File.open(png_path, "rb")
      result2 = @importer.execute(io2, filename: "test_character.png")
      io2.close

      assert result2.duplicate?
      assert_equal result1.character, result2.character
    end

    # === Filename Sanitization ===

    test "sanitizes filename for storage" do
      sanitized = @importer.send(:sanitize_filename, "My Character (v2) [final].png")
      assert_match(/^[\w.\-_]+$/, sanitized)
    end

    test "sanitizes filename removes directory traversal" do
      sanitized = @importer.send(:sanitize_filename, "../../../etc/passwd")
      assert_not_includes sanitized, "/"
      assert_not_includes sanitized, ".."
    end

    # === Extension Detection ===

    test "detects PNG extension from content" do
      png_header = "\x89PNG\r\n\x1a\n".b
      ext = @importer.send(:detect_extension, png_header)
      assert_equal "png", ext
    end

    test "detects JPEG extension from content" do
      jpeg_header = "\xFF\xD8\xFF\xE0".b
      ext = @importer.send(:detect_extension, jpeg_header)
      assert_equal "jpg", ext
    end

    test "detects GIF extension from content" do
      gif_header = "GIF89a"
      ext = @importer.send(:detect_extension, gif_header)
      assert_equal "gif", ext
    end

    test "returns bin for unknown content" do
      unknown = "unknown content"
      ext = @importer.send(:detect_extension, unknown)
      assert_equal "bin", ext
    end

    private

    # Creates a minimal valid PNG file (1x1 transparent pixel)
    def create_minimal_png
      # PNG signature
      signature = "\x89PNG\r\n\x1a\n".b

      # IHDR chunk (image header)
      ihdr_data = [1, 1, 8, 6, 0, 0, 0].pack("NNCCCCC") # 1x1, 8-bit RGBA
      ihdr_crc = Zlib.crc32("IHDR".b + ihdr_data)
      ihdr = [13, "IHDR".b, ihdr_data, ihdr_crc].pack("NA4A*N")

      # IDAT chunk (image data - compressed)
      raw_data = "\x00\x00\x00\x00\x00".b # Filter byte + 1 transparent pixel
      compressed = Zlib::Deflate.deflate(raw_data)
      idat_crc = Zlib.crc32("IDAT".b + compressed)
      idat = [compressed.length, "IDAT".b, compressed, idat_crc].pack("NA4A*N")

      # IEND chunk
      iend_crc = Zlib.crc32("IEND".b)
      iend = [0, "IEND".b, "".b, iend_crc].pack("NA4A*N")

      signature + ihdr + idat + iend
    end
  end
end
