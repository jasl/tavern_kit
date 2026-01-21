# frozen_string_literal: true

require "test_helper"

module CharacterExport
  class PngExporterTest < ActiveSupport::TestCase
    setup do
      @fixtures_path = Rails.root.join("test/fixtures/files/characters")
      @portrait_path = @fixtures_path.join("test_character.png")

      @character = Character.create!(
        name: "Test Character",
        spec_version: 3,
        status: "ready",
        data: {
          "name" => "Test Character",
          "description" => "A test character for PNG export",
          "personality" => "Friendly",
          "first_mes" => "Hello from PNG!",
          "tags" => ["test", "png"],
          "creator" => "TavernKit Test",
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

    test "exports character to PNG binary data" do
      exporter = PngExporter.new(@character)

      png_data = exporter.execute

      assert png_data.is_a?(String)
      assert png_data.start_with?("\x89PNG".b)
    end

    test "exported PNG contains embedded character data" do
      exporter = PngExporter.new(@character)

      png_data = exporter.execute

      # Parse the exported PNG and check for tEXt chunks
      chunks = parse_png_chunks(png_data)
      text_chunks = chunks.select { |c| c[:type] == "tEXt" }

      # Should have both chara and ccv3 chunks by default
      keywords = text_chunks.map { |c| extract_keyword(c[:data]) }
      assert_includes keywords, "chara"
      assert_includes keywords, "ccv3"
    end

    # === Export Formats ===

    test "exports with both V2 and V3 by default" do
      exporter = PngExporter.new(@character)

      png_data = exporter.execute
      chunks = parse_png_chunks(png_data)
      keywords = chunks.select { |c| c[:type] == "tEXt" }.map { |c| extract_keyword(c[:data]) }

      assert_includes keywords, "chara"
      assert_includes keywords, "ccv3"
    end

    test "exports V2 only when format is v2_only" do
      exporter = PngExporter.new(@character, format: :v2_only)

      png_data = exporter.execute
      chunks = parse_png_chunks(png_data)
      keywords = chunks.select { |c| c[:type] == "tEXt" }.map { |c| extract_keyword(c[:data]) }

      assert_includes keywords, "chara"
      refute_includes keywords, "ccv3"
    end

    test "exports V3 only when format is v3_only" do
      exporter = PngExporter.new(@character, format: :v3_only)

      png_data = exporter.execute
      chunks = parse_png_chunks(png_data)
      keywords = chunks.select { |c| c[:type] == "tEXt" }.map { |c| extract_keyword(c[:data]) }

      refute_includes keywords, "chara"
      assert_includes keywords, "ccv3"
    end

    # === Error Handling ===

    test "raises ExportError when no portrait attached" do
      @character.portrait.purge
      exporter = PngExporter.new(@character)

      error = assert_raises(ExportError) { exporter.execute }
      assert_match(/portrait.*attached/i, error.message)
    end

    test "raises ExportError when portrait is not a valid PNG" do
      @character.portrait.attach(
        io: StringIO.new("not a png file"),
        filename: "fake.png",
        content_type: "image/png",
      )
      exporter = PngExporter.new(@character)

      error = assert_raises(ExportError) { exporter.execute }
      assert_match(/not a valid PNG/i, error.message)
    end

    # === File Export ===

    test "exports to file" do
      exporter = PngExporter.new(@character)
      output_path = Rails.root.join("tmp/test_export.png")

      begin
        bytes = exporter.export_to_file(output_path)

        assert bytes > 0
        assert File.exist?(output_path)

        content = File.binread(output_path)
        assert content.start_with?("\x89PNG".b)
      ensure
        File.delete(output_path) if File.exist?(output_path)
      end
    end

    # === IO Export ===

    test "exports to StringIO" do
      exporter = PngExporter.new(@character)

      io = exporter.to_io

      assert io.is_a?(StringIO)
      content = io.read
      assert content.start_with?("\x89PNG".b)
    end

    # === Metadata ===

    test "suggested_filename returns sanitized name with png extension" do
      @character.name = "Test Character! @#$%"
      exporter = PngExporter.new(@character)

      filename = exporter.suggested_filename

      assert filename.end_with?(".png")
      assert_match(/^[a-zA-Z0-9_\-]+\.png$/, filename)
    end

    test "content_type returns image/png" do
      exporter = PngExporter.new(@character)

      assert_equal "image/png", exporter.content_type
    end

    # === Data Integrity ===

    test "exported PNG preserves character data" do
      exporter = PngExporter.new(@character)

      png_data = exporter.execute

      # Extract and verify the embedded data
      chunks = parse_png_chunks(png_data)
      ccv3_chunk = chunks.find { |c| c[:type] == "tEXt" && extract_keyword(c[:data]) == "ccv3" }

      assert ccv3_chunk.present?

      # Decode the base64 content
      nul_pos = ccv3_chunk[:data].index("\x00")
      base64_content = ccv3_chunk[:data][(nul_pos + 1)..]
      json_content = Base64.decode64(base64_content)
      parsed = JSON.parse(json_content)

      assert_equal "Test Character", parsed["data"]["name"]
      assert_equal "Hello from PNG!", parsed["data"]["first_mes"]
    end

    # === Round-trip Test ===

    test "exported PNG can be re-imported" do
      exporter = PngExporter.new(@character)
      png_data = exporter.execute

      # Create temp file for import test
      temp_path = Rails.root.join("tmp/roundtrip_test.png")
      begin
        File.binwrite(temp_path, png_data)

        # Import using the PngImporter
        importer = CharacterImport::PngImporter.new
        result = importer.call(File.open(temp_path, "rb"), filename: "roundtrip_test.png")

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

    private

    # Parse PNG into chunks.
    def parse_png_chunks(bytes)
      chunks = []
      pos = 8 # Skip signature

      while pos < bytes.bytesize
        length = bytes[pos, 4].unpack1("N")
        pos += 4

        type = bytes[pos, 4]
        pos += 4

        data = bytes[pos, length]
        pos += length

        pos += 4 # Skip CRC

        chunks << { type: type, data: data }

        break if type == "IEND"
      end

      chunks
    end

    # Extract keyword from tEXt chunk data.
    def extract_keyword(data)
      nul_pos = data.index("\x00")
      return nil if nul_pos.nil?

      data[0, nul_pos]
    end
  end
end
