# frozen_string_literal: true

module CharacterImport
  # Imports character cards from PNG files with embedded metadata.
  #
  # Supports PNG files with tEXt chunks containing:
  # - "ccv3" - CCv3 card data (base64 encoded JSON)
  # - "chara" - CCv2 card data (base64 encoded JSON)
  # - "chara-ext-asset_:N" - Embedded assets (base64 encoded binary)
  #
  # Uses TavernKit::Png::Parser for metadata extraction.
  #
  # @example Import a PNG file
  #   importer = PngImporter.new
  #   result = importer.call(file, filename: "character.png")
  #
  class PngImporter < Base
    # Import a character from PNG.
    #
    # @param io [IO, StringIO, Tempfile] the PNG file
    # @param filename [String] original filename
    # @param character [Character, nil] optional existing character to update (placeholder)
    # @return [ImportResult] the import result
    def call(io, filename:, character: nil)
      content = read_and_rewind(io)
      file_sha256 = compute_sha256(content)

      # Check for duplicate
      if (existing = find_duplicate(file_sha256, character: character))
        return ImportResult.duplicate(existing)
      end

      # Write to temp file for TavernKit parsing
      temp_file = write_to_tempfile(content, filename)

      begin
        # Extract card data using TavernKit
        card_hash = extract_card_data(temp_file.path)
        validate_card!(card_hash)

        result_character = nil

        ActiveRecord::Base.transaction do
          # Create or update character
          result_character = create_or_update_character(card_hash, file_sha256: file_sha256, character: character)

          # Attach the PNG as portrait
          attach_portrait(result_character, content, filename)

          # Extract and attach embedded assets if present
          extract_embedded_assets(result_character, temp_file.path)
        end

        ImportResult.success(result_character)
      ensure
        temp_file.close
        temp_file.unlink
      end
    rescue TavernKit::Png::ParseError => e
      ImportResult.failure("PNG parse error: #{e.message}")
    rescue InvalidCardError => e
      ImportResult.failure(e.message)
    rescue StandardError => e
      Rails.logger.error("PngImporter error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      ImportResult.failure("Import failed: #{e.message}")
    end

    private

    # Extract card data from PNG using TavernKit.
    #
    # @param path [String] path to PNG file
    # @return [Hash] parsed card data
    def extract_card_data(path)
      TavernKit::Png::Parser.extract_card_payload(path)
    end

    # Write content to a temporary file.
    #
    # @param content [String] binary content
    # @param filename [String] original filename for extension
    # @return [Tempfile]
    def write_to_tempfile(content, filename)
      ext = File.extname(filename)
      temp = Tempfile.new(["character", ext], binmode: true)
      temp.write(content)
      temp.rewind
      temp
    end

    # Attach PNG as character portrait.
    #
    # @param character [Character] the character
    # @param content [String] PNG binary content
    # @param filename [String] original filename
    def attach_portrait(character, content, filename)
      character.portrait.attach(
        io: StringIO.new(content),
        filename: sanitize_filename(filename),
        content_type: "image/png"
      )
    end

    # Extract embedded assets from PNG tEXt chunks.
    #
    # Looks for chunks named "chara-ext-asset_:N" containing base64 data.
    #
    # @param character [Character] the character to attach assets to
    # @param path [String] path to PNG file
    def extract_embedded_assets(character, path)
      chunks = TavernKit::Png::Parser.extract_text_chunks(path)

      asset_chunks = chunks.select { |c| c[:keyword].to_s.start_with?("chara-ext-asset_") }
      return if asset_chunks.empty?

      extractor = AssetExtractor.new
      card_assets = character.data["assets"] || []

      asset_chunks.each do |chunk|
        # Parse asset index from keyword (e.g., "chara-ext-asset_:1" -> "1")
        index = chunk[:keyword].sub(/^chara-ext-asset_:?/, "")
        next if index.blank?

        # Decode base64 content
        begin
          content = Base64.strict_decode64(chunk[:text])
        rescue ArgumentError
          content = Base64.decode64(chunk[:text])
        end

        # Find matching asset definition in card data
        asset_def = find_asset_definition(card_assets, index)

        extractor.attach_asset(
          character,
          content: content,
          name: asset_def&.dig("name") || "asset_#{index}",
          kind: asset_def&.dig("type") || "other",
          ext: asset_def&.dig("ext") || detect_extension(content)
        )
      end
    end

    # Find asset definition by __asset:N reference.
    #
    # @param assets [Array<Hash>] asset definitions from card
    # @param index [String] asset index
    # @return [Hash, nil]
    def find_asset_definition(assets, index)
      return nil unless assets.is_a?(Array)

      assets.find { |a| a["uri"] == "__asset:#{index}" }
    end

    # Detect file extension from content.
    #
    # @param content [String] binary content
    # @return [String] extension without dot
    def detect_extension(content)
      return "bin" if content.nil? || content.empty?

      # Ensure binary encoding for comparison
      bytes = content.dup.force_encoding("ASCII-8BIT")

      # Check magic bytes
      if bytes.start_with?("\x89PNG".b)
        "png"
      elsif bytes.start_with?("\xFF\xD8\xFF".b)
        "jpg"
      elsif bytes.start_with?("GIF8".b)
        "gif"
      elsif bytes.start_with?("RIFF".b) && bytes[8, 4] == "WEBP".b
        "webp"
      else
        "bin"
      end
    end

    # Sanitize filename for storage.
    #
    # @param filename [String]
    # @return [String]
    def sanitize_filename(filename)
      File.basename(filename.to_s).gsub(/[^\w.\-]/, "_")
    end
  end
end
