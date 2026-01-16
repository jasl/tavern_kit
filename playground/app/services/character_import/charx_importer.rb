# frozen_string_literal: true

module CharacterImport
  # Imports character cards from CharX (ZIP) format.
  #
  # CharX is the CCv3 archive format containing:
  # - card.json - Character card data (required)
  # - module.risum - RisuAI module data (optional, ignored)
  # - assets/ - Embedded asset files
  #
  # Asset URI schemes:
  # - embeded://path/to/asset.png - Reference to file in ZIP
  # - ccdefault: - Reference to default icon (from card.json)
  # - __asset:N - PNG tEXt chunk reference (from PNG-embedded cards)
  #
  # @example Import a CharX file
  #   importer = CharxImporter.new
  #   result = importer.call(file, filename: "character.charx")
  #
  # @see https://github.com/kwaroran/character-card-spec-v3/blob/main/SPEC_V3.md#charx
  #
  class CharxImporter < Base
    CARD_JSON_PATH = "card.json"

    # Security limits for untrusted ZIP uploads.
    MAX_ARCHIVE_BYTES = 100 * 1024 * 1024
    MAX_ZIP_ENTRIES = 512
    MAX_ENTRY_UNCOMPRESSED_BYTES = 25 * 1024 * 1024
    MAX_TOTAL_UNCOMPRESSED_BYTES = 200 * 1024 * 1024
    MAX_CARD_JSON_BYTES = 1 * 1024 * 1024
    MAX_DATA_URI_BYTES = 5 * 1024 * 1024

    ALLOWED_ROOT_ENTRIES = [
      CARD_JSON_PATH,
      "module.risum",
    ].freeze

    ALLOWED_ASSET_PREFIX = "assets/"

    # RisuAI extension: x_meta/ contains metadata for assets (e.g., {"type":"WEBP"})
    ALLOWED_XMETA_PREFIX = "x_meta/"

    # Import a character from CharX.
    #
    # @param io [IO, StringIO, Tempfile] the CharX file
    # @param filename [String] original filename
    # @param character [Character, nil] optional existing character to update (placeholder)
    # @return [ImportResult] the import result
    def call(io, filename:, character: nil)
      content = read_and_rewind(io)
      validate_archive_size!(content)
      file_sha256 = compute_sha256(content)

      # Check for duplicate
      if (existing = find_duplicate(file_sha256, character: character))
        return ImportResult.duplicate(existing)
      end

      # Handle JPEG-embedded CharX (RisuAI format)
      if jpeg_with_zip?(content)
        content = extract_zip_from_jpeg(content)
        validate_archive_size!(content)
      end

      # Parse CharX archive
      Zip::File.open_buffer(StringIO.new(content)) do |zip|
        validate_zip_safety!(zip)

        # Extract and parse card.json
        card_json = read_zip_entry(zip, CARD_JSON_PATH, max_bytes: MAX_CARD_JSON_BYTES, required: true)
        card_hash = parse_json(card_json)
        validate_card!(card_hash)

        result_character = nil

        ActiveRecord::Base.transaction do
          # Create or update character
          result_character = create_or_update_character(card_hash, file_sha256: file_sha256, character: character)

          # Extract and attach assets
          extract_assets(result_character, zip, card_hash)
        end

        return ImportResult.success(result_character)
      end
    rescue Zip::Error => e
      ImportResult.failure("Invalid CharX archive: #{e.message}")
    rescue InvalidCardError => e
      ImportResult.failure(e.message)
    rescue StandardError => e
      Rails.logger.error("CharxImporter error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      ImportResult.failure("Import failed: #{e.message}")
    end

    private

    # Check if content is a JPEG with embedded ZIP (RisuAI format).
    #
    # @param content [String] binary content
    # @return [Boolean]
    def jpeg_with_zip?(content)
      # JPEG starts with FF D8 FF
      return false unless content.start_with?("\xFF\xD8\xFF".b)

      # Look for ZIP signature after JPEG header
      content.include?("PK\x03\x04".b)
    end

    # Extract ZIP data from JPEG-embedded CharX.
    #
    # RisuAI embeds ZIP data after the JPEG image data.
    #
    # @param content [String] JPEG with embedded ZIP
    # @return [String] extracted ZIP content
    def extract_zip_from_jpeg(content)
      # Find ZIP local file header signature
      zip_start = content.index("PK\x03\x04".b)
      raise InvalidCardError, "No ZIP data found in JPEG" unless zip_start

      content[zip_start..]
    end

    # Extract and attach all assets from the CharX archive.
    #
    # @param character [Character] the character
    # @param zip [Zip::File] the opened ZIP file
    # @param card_hash [Hash] parsed card data
    def extract_assets(character, zip, card_hash)
      extractor = AssetExtractor.new
      assets = card_hash.dig("data", "assets") || []
      main_icon_attached = false

      assets.each do |asset_def|
        uri = asset_def["uri"]
        next if uri.blank?

        content = resolve_asset_content(zip, uri)
        next unless content

        name = asset_def["name"] || "unnamed"
        kind = normalize_asset_kind(asset_def["type"])
        declared_ext = asset_def["ext"].to_s.downcase.delete_prefix(".")
        detected_ext = detect_extension_from_content(content)

        # Use detected extension if declared extension doesn't match content
        # This handles RisuAI CharX files where assets may have mismatched extensions
        ext = if declared_ext.present? && magic_bytes_match?(content, declared_ext)
                declared_ext
        else
                detected_ext
        end

        assert_supported_asset_ext!(ext)

        # Attach as portrait if this is the main icon
        if kind == "icon" && name == "main" && !main_icon_attached
          attach_main_icon(character, content, ext)
          main_icon_attached = true
        end

        # Also create CharacterAsset record
        extractor.attach_asset(
          character,
          content: content,
          name: name,
          kind: kind,
          ext: ext
        )
      end

      # If no main icon was found in assets, try to use first available image
      unless main_icon_attached
        attach_fallback_icon(character, zip, assets, extractor)
      end
    end

    # Resolve asset content from ZIP based on URI scheme.
    #
    # @param zip [Zip::File] the ZIP file
    # @param uri [String] asset URI
    # @return [String, nil] binary content or nil if not found
    def resolve_asset_content(zip, uri)
      case uri
      when /^embeded:\/\/(.+)$/
        # embeded://path/to/file.png (note: spec uses "embeded" not "embedded")
        path = Regexp.last_match(1)
        validate_asset_path!(path)
        read_zip_entry(zip, path, max_bytes: MAX_ENTRY_UNCOMPRESSED_BYTES)
      when "ccdefault:"
        # Default icon - handled separately
        nil
      when /^__asset:(\d+)$/
        # __asset:N refers to PNG-embedded cards, not CharX
        nil
      when /^data:/
        # Data URI - extract base64 content
        extract_data_uri(uri)
      else
        # Try as direct path
        validate_asset_path!(uri)
        read_zip_entry(zip, uri, max_bytes: MAX_ENTRY_UNCOMPRESSED_BYTES)
      end
    end

    # Read content from a ZIP entry.
    #
    # @param zip [Zip::File] the ZIP file
    # @param path [String] path within ZIP
    # @param max_bytes [Integer] maximum allowed bytes to read (uncompressed)
    # @param required [Boolean] whether to raise when entry is missing
    # @return [String, nil] content or nil if not found
    def read_zip_entry(zip, path, max_bytes:, required: false)
      entry = zip.find_entry(path)

      if entry.nil?
        raise InvalidCardError, "CharX missing #{path}" if required
        return nil
      end

      validate_zip_entry_name!(entry.name)
      validate_zip_entry_allowed!(entry.name)

      declared_size = entry.size.to_i
      if declared_size.positive? && declared_size > max_bytes
        raise InvalidCardError, "CharX entry too large: #{entry.name} (#{declared_size} bytes)"
      end

      entry.get_input_stream do |stream|
        read_stream_limited(stream, max_bytes)
      end
    rescue InvalidCardError
      raise
    rescue StandardError => e
      Rails.logger.warn("Failed to read ZIP entry #{path}: #{e.message}")
      nil
    end

    # Extract binary content from data URI.
    #
    # @param uri [String] data URI
    # @return [String, nil] decoded content
    def extract_data_uri(uri)
      return nil unless uri.start_with?("data:")

      # Format: data:[<mediatype>][;base64],<data>
      match = uri.match(/^data:[^;,]*(?:;base64)?,(.+)$/i)
      return nil unless match

      encoded = match[1]
      if estimated_base64_decoded_bytes(encoded) > MAX_DATA_URI_BYTES
        raise InvalidCardError, "Data URI asset too large"
      end

      decoded = Base64.decode64(encoded)
      raise InvalidCardError, "Data URI asset too large" if decoded.bytesize > MAX_DATA_URI_BYTES

      decoded
    rescue InvalidCardError
      raise
    rescue StandardError
      nil
    end

    # Normalize asset kind to our supported values.
    #
    # @param type [String] asset type from card
    # @return [String] normalized kind
    def normalize_asset_kind(type)
      case type.to_s.downcase
      when "icon"
        "icon"
      when "emotion"
        "emotion"
      when "background"
        "background"
      when "user_icon"
        "user_icon"
      else
        "other"
      end
    end

    # Detect file extension from content magic bytes.
    #
    # @param content [String] binary content
    # @return [String] extension without dot
    def detect_extension_from_content(content)
      return "bin" if content.nil? || content.empty?

      header = content[0, 16].to_s

      if header.start_with?("\x89PNG".b)
        "png"
      elsif header.start_with?("\xFF\xD8\xFF".b)
        "jpg"
      elsif header.start_with?("GIF8")
        "gif"
      elsif header.start_with?("RIFF") && content[8, 4] == "WEBP"
        "webp"
      else
        "bin"
      end
    end

    # Attach the main icon as character portrait.
    #
    # @param character [Character] the character
    # @param content [String] image content
    # @param ext [String] file extension
    def attach_main_icon(character, content, ext)
      content_type = case ext.to_s.downcase
      when "png" then "image/png"
      when "jpg", "jpeg" then "image/jpeg"
      when "gif" then "image/gif"
      when "webp" then "image/webp"
      else "application/octet-stream"
      end

      character.portrait.attach(
        io: StringIO.new(content),
        filename: "portrait.#{ext}",
        content_type: content_type
      )
    end

    # Try to attach a fallback icon from ZIP assets.
    #
    # @param character [Character] the character
    # @param zip [Zip::File] the ZIP file
    # @param assets [Array<Hash>] asset definitions
    # @param extractor [AssetExtractor] the extractor
    def attach_fallback_icon(character, zip, assets, extractor)
      # Look for any icon type asset
      icon_asset = assets.find { |a| a["type"] == "icon" }

      if icon_asset
        content = resolve_asset_content(zip, icon_asset["uri"])
        if content
          attach_main_icon(character, content, icon_asset["ext"] || "png")
          return
        end
      end

      # Look for any image file in assets/icon/
      zip.each do |entry|
        next unless entry.name =~ %r{^assets/icon/.*\.(png|jpg|jpeg|gif|webp)$}i

        content = read_zip_entry(zip, entry.name, max_bytes: MAX_ENTRY_UNCOMPRESSED_BYTES)
        next unless content

        ext = File.extname(entry.name).delete(".")
        attach_main_icon(character, content, ext)
        return
      end
    end

    def validate_archive_size!(content)
      return if content.bytesize <= MAX_ARCHIVE_BYTES

      raise InvalidCardError, "CharX archive too large (#{content.bytesize} bytes)"
    end

    def validate_zip_safety!(zip)
      entries = zip.entries
      raise InvalidCardError, "CharX has too many entries (#{entries.size} > #{MAX_ZIP_ENTRIES})" if entries.size > MAX_ZIP_ENTRIES

      total = 0

      entries.each do |entry|
        name = entry.name.to_s
        validate_zip_entry_name!(name)
        validate_zip_entry_allowed!(name)

        next if entry.directory?

        size = entry.size.to_i

        if name == CARD_JSON_PATH && size > MAX_CARD_JSON_BYTES
          raise InvalidCardError, "CharX card.json too large (#{size} bytes)"
        end

        if size > MAX_ENTRY_UNCOMPRESSED_BYTES
          raise InvalidCardError, "CharX entry too large: #{name} (#{size} bytes)"
        end

        total += size
        if total > MAX_TOTAL_UNCOMPRESSED_BYTES
          raise InvalidCardError, "CharX total uncompressed size too large (#{total} bytes)"
        end
      end
    end

    def validate_zip_entry_name!(name)
      # Reject suspicious paths (path traversal / absolute / Windows drive / backslashes).
      if name.include?("\0") ||
          name.start_with?("/") ||
          name.match?(/\A[a-zA-Z]:/) ||
          name.include?("\\")
        raise InvalidCardError, "CharX contains unsafe path: #{name.inspect}"
      end

      parts = name.split("/")
      raise InvalidCardError, "CharX contains unsafe path: #{name.inspect}" if parts.any? { |p| p == ".." }
    end

    def validate_zip_entry_allowed!(name)
      return if name.end_with?("/") && name.start_with?(ALLOWED_ASSET_PREFIX)
      return if ALLOWED_ROOT_ENTRIES.include?(name)
      return if name.start_with?(ALLOWED_ASSET_PREFIX)
      # RisuAI extension: x_meta/ contains metadata for assets
      return if name.start_with?(ALLOWED_XMETA_PREFIX)

      raise InvalidCardError, "CharX contains unexpected entry: #{name}"
    end

    def validate_asset_path!(path)
      validate_zip_entry_name!(path)
      validate_zip_entry_allowed!(path)
    end

    def assert_supported_asset_ext!(ext)
      allowed_exts = AssetExtractor::CONTENT_TYPES.keys
      return if allowed_exts.include?(ext)

      raise InvalidCardError, "Unsupported asset extension: #{ext.inspect}"
    end

    # Check if content magic bytes match the declared extension.
    #
    # @param content [String] binary content
    # @param ext [String] declared extension
    # @return [Boolean] true if magic bytes match
    def magic_bytes_match?(content, ext)
      bytes = content.to_s.b

      case ext
      when "png"
        bytes.start_with?("\x89PNG".b)
      when "jpg", "jpeg"
        bytes.start_with?("\xFF\xD8\xFF".b)
      when "gif"
        bytes.start_with?("GIF8".b)
      when "webp"
        bytes.start_with?("RIFF".b) && bytes.bytesize >= 12 && bytes[8, 4] == "WEBP".b
      when "mp3"
        bytes.start_with?("ID3".b) || (bytes.bytesize >= 2 && bytes.getbyte(0) == 0xFF && (bytes.getbyte(1) & 0xE0) == 0xE0)
      when "wav"
        bytes.start_with?("RIFF".b) && bytes.bytesize >= 12 && bytes[8, 4] == "WAVE".b
      when "ogg"
        bytes.start_with?("OggS".b)
      when "mp4"
        bytes.bytesize >= 12 && bytes[4, 4] == "ftyp".b
      when "webm"
        bytes.start_with?("\x1A\x45\xDF\xA3".b)
      when "avif"
        bytes.bytesize >= 12 && bytes[4, 4] == "ftyp".b
      else
        # Unknown extension - assume match (will be validated by detect_extension_from_content)
        true
      end
    end

    # @deprecated Use magic_bytes_match? instead for non-throwing validation
    def validate_asset_magic_bytes!(content, ext)
      bytes = content.to_s.b

      case ext
      when "png"
        raise InvalidCardError, "Asset content does not match extension: #{ext.inspect}" unless bytes.start_with?("\x89PNG".b)
      when "jpg", "jpeg"
        raise InvalidCardError, "Asset content does not match extension: #{ext.inspect}" unless bytes.start_with?("\xFF\xD8\xFF".b)
      when "gif"
        raise InvalidCardError, "Asset content does not match extension: #{ext.inspect}" unless bytes.start_with?("GIF8".b)
      when "webp"
        valid = bytes.start_with?("RIFF".b) && bytes.bytesize >= 12 && bytes[8, 4] == "WEBP".b
        raise InvalidCardError, "Asset content does not match extension: #{ext.inspect}" unless valid
      when "mp3"
        valid = bytes.start_with?("ID3".b) || (bytes.bytesize >= 2 && bytes.getbyte(0) == 0xFF && (bytes.getbyte(1) & 0xE0) == 0xE0)
        raise InvalidCardError, "Asset content does not match extension: #{ext.inspect}" unless valid
      when "wav"
        valid = bytes.start_with?("RIFF".b) && bytes.bytesize >= 12 && bytes[8, 4] == "WAVE".b
        raise InvalidCardError, "Asset content does not match extension: #{ext.inspect}" unless valid
      when "ogg"
        raise InvalidCardError, "Asset content does not match extension: #{ext.inspect}" unless bytes.start_with?("OggS".b)
      when "mp4"
        valid = bytes.bytesize >= 12 && bytes[4, 4] == "ftyp".b
        raise InvalidCardError, "Asset content does not match extension: #{ext.inspect}" unless valid
      when "webm"
        raise InvalidCardError, "Asset content does not match extension: #{ext.inspect}" unless bytes.start_with?("\x1A\x45\xDF\xA3".b)
      when "avif"
        # AVIF is ISO BMFF based; we only do a lightweight "ftyp" check.
        valid = bytes.bytesize >= 12 && bytes[4, 4] == "ftyp".b
        raise InvalidCardError, "Asset content does not match extension: #{ext.inspect}" unless valid
      end
    end

    def estimated_base64_decoded_bytes(encoded)
      # Rough upper-bound estimate to avoid decoding huge payloads:
      # base64 inflates by ~4/3, so decoded ~= encoded * 3/4.
      (encoded.to_s.bytesize * 3) / 4
    end

    def read_stream_limited(stream, max_bytes)
      remaining = max_bytes
      output = +""

      while remaining.positive?
        chunk = stream.read([16_384, remaining].min)
        break if chunk.nil?

        output << chunk
        remaining -= chunk.bytesize
      end

      # If there's still data, we exceeded max_bytes.
      raise InvalidCardError, "CharX entry too large" unless stream.read(1).nil?

      output
    end
  end
end
