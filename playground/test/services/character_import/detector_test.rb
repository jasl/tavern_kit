# frozen_string_literal: true

require "test_helper"

module CharacterImport
  class DetectorTest < ActiveSupport::TestCase
    # === Format Detection by Extension ===

    test "detects JSON by extension" do
      assert_equal :json, Detector.detect(filename: "character.json")
      assert_equal :json, Detector.detect(filename: "my card.JSON")
    end

    test "detects PNG by extension" do
      assert_equal :png, Detector.detect(filename: "portrait.png")
      assert_equal :png, Detector.detect(filename: "character.PNG")
      assert_equal :png, Detector.detect(filename: "animated.apng")
    end

    test "detects CharX by extension" do
      assert_equal :charx, Detector.detect(filename: "character.charx")
      assert_equal :charx, Detector.detect(filename: "MyChar.CHARX")
    end

    test "detects JPEG by extension" do
      assert_equal :jpeg, Detector.detect(filename: "image.jpg")
      assert_equal :jpeg, Detector.detect(filename: "photo.jpeg")
    end

    test "returns unknown for unsupported extensions" do
      assert_equal :unknown, Detector.detect(filename: "file.txt")
      assert_equal :unknown, Detector.detect(filename: "data.xml")
      assert_equal :unknown, Detector.detect(filename: "noextension")
      assert_equal :unknown, Detector.detect(filename: "")
    end

    # === Format Detection by Content ===

    test "detects PNG by magic bytes" do
      png_content = "\x89PNG\r\n\x1a\n" + ("x" * 100)
      io = StringIO.new(png_content)

      assert_equal :png, Detector.detect(io: io, filename: "unknown")
    end

    test "detects ZIP/CharX by magic bytes" do
      zip_content = "PK\x03\x04" + ("x" * 100)
      io = StringIO.new(zip_content)

      assert_equal :charx, Detector.detect(io: io, filename: "unknown")
    end

    test "detects JSON by content start" do
      json_content = '{"spec": "chara_card_v2"}'
      io = StringIO.new(json_content)

      assert_equal :json, Detector.detect(io: io, filename: "unknown")
    end

    test "detects JSON with whitespace prefix" do
      json_content = "  \n  {\"name\": \"test\"}"
      io = StringIO.new(json_content)

      assert_equal :json, Detector.detect(io: io, filename: "unknown")
    end

    # === Supported Check ===

    test "supported? returns true for valid formats" do
      assert Detector.supported?("test.json")
      assert Detector.supported?("test.png")
      assert Detector.supported?("test.charx")
      assert Detector.supported?("test.jpg")
    end

    test "supported? returns false for invalid formats" do
      assert_not Detector.supported?("test.txt")
      assert_not Detector.supported?("test.xml")
      assert_not Detector.supported?("")
    end

    # === Importer Selection ===

    test "importer_for returns JsonImporter for :json" do
      importer = Detector.importer_for(:json)
      assert_instance_of JsonImporter, importer
    end

    test "importer_for returns PngImporter for :png" do
      importer = Detector.importer_for(:png)
      assert_instance_of PngImporter, importer
    end

    test "importer_for returns CharxImporter for :charx" do
      importer = Detector.importer_for(:charx)
      assert_instance_of CharxImporter, importer
    end

    test "importer_for returns CharxImporter for :jpeg" do
      importer = Detector.importer_for(:jpeg)
      assert_instance_of CharxImporter, importer
    end

    test "importer_for raises for unknown format" do
      assert_raises(UnsupportedFormatError) do
        Detector.importer_for(:unknown)
      end
    end

    # === Full Import Flow ===

    test "import routes JSON to JsonImporter" do
      fixture_path = file_fixture("characters/minimal_v2.json")
      io = File.open(fixture_path, "rb")

      result = Detector.import(io, filename: "minimal_v2.json")
      io.close

      assert result.success?
      assert_equal "Test Character V2", result.character.name
    end

    test "import handles upload-style file objects" do
      fixture_path = file_fixture("characters/minimal_v3.json")
      io = File.open(fixture_path, "rb")

      result = Detector.import(io, filename: "test.json")
      io.close

      assert result.success?
      assert_equal "Test Character V3", result.character.name
      assert_equal 3, result.character.spec_version
    end
  end
end
