# frozen_string_literal: true

module CharacterImport
  # Extracts and stores character assets using ActiveStorage.
  #
  # Handles asset deduplication via content SHA256 hashing, reusing
  # existing blobs when possible to save storage space.
  #
  # @example Attach an asset
  #   extractor = AssetExtractor.new
  #   extractor.attach_asset(
  #     character,
  #     content: image_data,
  #     name: "happy",
  #     kind: "emotion",
  #     ext: "png"
  #   )
  #
  class AssetExtractor
    # Content type mappings by extension
    CONTENT_TYPES = {
      "png" => "image/png",
      "jpg" => "image/jpeg",
      "jpeg" => "image/jpeg",
      "gif" => "image/gif",
      "webp" => "image/webp",
      "avif" => "image/avif",
      "mp3" => "audio/mpeg",
      "wav" => "audio/wav",
      "ogg" => "audio/ogg",
      "mp4" => "video/mp4",
      "webm" => "video/webm",
    }.freeze

    # Attach an asset to a character.
    #
    # @param character [Character] the character
    # @param content [String] binary content
    # @param name [String] asset name (unique per character)
    # @param kind [String] asset kind (icon, emotion, etc.)
    # @param ext [String] file extension
    # @return [CharacterAsset] the created asset record
    def attach_asset(character, content:, name:, kind:, ext:)
      return nil if content.blank?

      content_sha256 = Digest::SHA256.hexdigest(content)

      # Try to reuse existing blob with same content
      blob = find_or_create_blob(content, name, ext, content_sha256)

      sanitized_name = sanitize_name(name)

      # Check for existing asset with same name
      existing = character.character_assets.find_by(name: sanitized_name)
      if existing
        # If content has changed, update the blob reference
        if existing.content_sha256 != content_sha256
          existing.update!(blob: blob, content_sha256: content_sha256, ext: ext)
        end
        return existing
      end

      # Create the asset record
      CharacterAsset.create!(
        character: character,
        blob: blob,
        name: sanitized_name,
        kind: normalize_kind(kind),
        ext: ext,
        content_sha256: content_sha256
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # Asset with this name already exists for character
      Rails.logger.info("Asset '#{name}' already exists for character #{character.id}: #{e.message}")
      character.character_assets.find_by(name: sanitized_name)
    end

    # Attach multiple assets from an array of definitions.
    #
    # @param character [Character] the character
    # @param assets [Array<Hash>] array of asset definitions
    # @param content_resolver [Proc] proc to resolve content from URI
    # @return [Array<CharacterAsset>] created asset records
    def attach_assets(character, assets, &content_resolver)
      return [] unless assets.is_a?(Array)

      assets.filter_map do |asset_def|
        uri = asset_def["uri"]
        next if uri.blank?

        content = content_resolver.call(uri)
        next unless content

        attach_asset(
          character,
          content: content,
          name: asset_def["name"] || "unnamed",
          kind: asset_def["type"] || "other",
          ext: asset_def["ext"] || detect_extension(content)
        )
      end
    end

    private

    # Find existing blob or create new one.
    #
    # @param content [String] binary content
    # @param name [String] filename base
    # @param ext [String] file extension
    # @param content_sha256 [String] content hash
    # @return [ActiveStorage::Blob]
    def find_or_create_blob(content, name, ext, content_sha256)
      # Compute ActiveStorage-compatible checksum
      checksum = Digest::MD5.base64digest(content)

      # Try to find existing blob with same checksum and size
      existing = ActiveStorage::Blob.find_by(
        checksum: checksum,
        byte_size: content.bytesize
      )

      return existing if existing

      # Create new blob
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(content),
        filename: sanitize_filename("#{name}.#{ext}"),
        content_type: content_type_for(ext)
      )
    end

    # Get content type for extension.
    #
    # @param ext [String] file extension
    # @return [String] MIME type
    def content_type_for(ext)
      CONTENT_TYPES[ext.to_s.downcase] || "application/octet-stream"
    end

    # Sanitize asset name.
    #
    # @param name [String]
    # @return [String]
    def sanitize_name(name)
      name.to_s.strip.gsub(/[^\w.\-]/, "_").slice(0, 255)
    end

    # Sanitize filename for storage.
    #
    # @param filename [String]
    # @return [String]
    def sanitize_filename(filename)
      filename.to_s.gsub(/[^\w.\-]/, "_").slice(0, 255)
    end

    # Normalize asset kind to supported values.
    #
    # @param kind [String]
    # @return [String]
    def normalize_kind(kind)
      normalized = kind.to_s.downcase
      CharacterAsset::KINDS.include?(normalized) ? normalized : "other"
    end

    # Detect extension from content magic bytes.
    #
    # @param content [String]
    # @return [String]
    def detect_extension(content)
      return "bin" if content.nil? || content.empty?

      header = content[0, 16].to_s

      if header.start_with?("\x89PNG")
        "png"
      elsif header.start_with?("\xFF\xD8\xFF")
        "jpg"
      elsif header.start_with?("GIF8")
        "gif"
      elsif header.start_with?("RIFF") && content[8, 4] == "WEBP"
        "webp"
      else
        "bin"
      end
    end
  end
end
