# frozen_string_literal: true

require "test_helper"

module CharacterImport
  class AssetExtractorTest < ActiveSupport::TestCase
    setup do
      @extractor = AssetExtractor.new
      @character = characters(:ready_v2)
    end

    # === Single Asset Attachment ===

    test "attach_asset creates asset with blob" do
      content = "test image content"

      asset = @extractor.attach_asset(
        @character,
        content: content,
        name: "test_icon",
        kind: "icon",
        ext: "png"
      )

      assert_instance_of CharacterAsset, asset
      assert asset.persisted?
      assert_equal "test_icon", asset.name
      assert_equal "icon", asset.kind
      assert_equal "png", asset.ext
      assert_equal Digest::SHA256.hexdigest(content), asset.content_sha256
      assert_not_nil asset.blob
    end

    test "attach_asset normalizes kind" do
      asset = @extractor.attach_asset(
        @character,
        content: "content",
        name: "test",
        kind: "ICON",
        ext: "png"
      )

      assert_equal "icon", asset.kind
    end

    test "attach_asset uses other for unknown kind" do
      asset = @extractor.attach_asset(
        @character,
        content: "content",
        name: "test",
        kind: "unknown_kind",
        ext: "png"
      )

      assert_equal "other", asset.kind
    end

    test "attach_asset returns nil for blank content" do
      asset = @extractor.attach_asset(
        @character,
        content: "",
        name: "empty",
        kind: "icon",
        ext: "png"
      )

      assert_nil asset
    end

    test "attach_asset handles duplicate names gracefully" do
      @extractor.attach_asset(
        @character,
        content: "first",
        name: "duplicate",
        kind: "icon",
        ext: "png"
      )

      # Second attachment with same name should return existing
      asset = @extractor.attach_asset(
        @character,
        content: "second",
        name: "duplicate",
        kind: "emotion",
        ext: "jpg"
      )

      assert_not_nil asset
      assert_equal "duplicate", asset.name
    end

    # === Blob Reuse ===

    test "attach_asset reuses blob for same content" do
      content = "identical content for both"

      asset1 = @extractor.attach_asset(
        @character,
        content: content,
        name: "first",
        kind: "icon",
        ext: "png"
      )

      other_character = characters(:ready_v3)
      asset2 = @extractor.attach_asset(
        other_character,
        content: content,
        name: "second",
        kind: "emotion",
        ext: "png"
      )

      # Same blob should be reused
      assert_equal asset1.blob_id, asset2.blob_id
    end

    # === Multiple Assets ===

    test "attach_assets from array of definitions" do
      assets_def = [
        { "uri" => "asset1", "name" => "icon1", "type" => "icon", "ext" => "png" },
        { "uri" => "asset2", "name" => "bg1", "type" => "background", "ext" => "jpg" },
      ]

      content_map = {
        "asset1" => "icon content",
        "asset2" => "background content",
      }

      assets = @extractor.attach_assets(@character, assets_def) do |uri|
        content_map[uri]
      end

      assert_equal 2, assets.size
      assert assets.all?(&:persisted?)
      assert_equal %w[icon1 bg1], assets.map(&:name)
    end

    test "attach_assets skips assets with blank uri" do
      assets_def = [
        { "uri" => "", "name" => "empty", "type" => "icon" },
        { "uri" => "valid", "name" => "valid", "type" => "icon", "ext" => "png" },
      ]

      assets = @extractor.attach_assets(@character, assets_def) do |uri|
        uri == "valid" ? "content" : nil
      end

      assert_equal 1, assets.size
      assert_equal "valid", assets.first.name
    end

    test "attach_assets skips assets with nil resolved content" do
      assets_def = [
        { "uri" => "missing", "name" => "missing", "type" => "icon", "ext" => "png" },
      ]

      assets = @extractor.attach_assets(@character, assets_def) do |_uri|
        nil # Content resolver returns nil
      end

      assert_empty assets
    end

    # === Content Type Detection ===

    test "content_type_for returns correct MIME types" do
      extractor_class = AssetExtractor.new

      assert_equal "image/png", extractor_class.send(:content_type_for, "png")
      assert_equal "image/jpeg", extractor_class.send(:content_type_for, "jpg")
      assert_equal "image/jpeg", extractor_class.send(:content_type_for, "jpeg")
      assert_equal "image/gif", extractor_class.send(:content_type_for, "gif")
      assert_equal "image/webp", extractor_class.send(:content_type_for, "webp")
      assert_equal "application/octet-stream", extractor_class.send(:content_type_for, "unknown")
    end

    # === Extension Detection ===

    test "detect_extension identifies PNG" do
      png_content = "\x89PNG\r\n\x1a\nrest of content"
      ext = @extractor.send(:detect_extension, png_content)
      assert_equal "png", ext
    end

    test "detect_extension identifies JPEG" do
      jpeg_content = "\xFF\xD8\xFF\xE0rest of content"
      ext = @extractor.send(:detect_extension, jpeg_content)
      assert_equal "jpg", ext
    end

    test "detect_extension identifies GIF" do
      gif_content = "GIF89arest of content"
      ext = @extractor.send(:detect_extension, gif_content)
      assert_equal "gif", ext
    end

    test "detect_extension returns bin for unknown" do
      unknown_content = "unknown file content"
      ext = @extractor.send(:detect_extension, unknown_content)
      assert_equal "bin", ext
    end
  end
end
