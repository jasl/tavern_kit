# frozen_string_literal: true

module CharacterImport
  # Imports character cards from JSON files.
  #
  # Supports both CCv2 and CCv3 JSON formats. Uses TavernKit for parsing
  # and validation when available, with fallback to direct parsing.
  #
  # @example Import a JSON file
  #   importer = JsonImporter.new
  #   result = importer.call(file, filename: "character.json")
  #
  class JsonImporter < Base
    # Import a character from JSON.
    #
    # @param io [IO, StringIO] the JSON content
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

      # Parse JSON
      card_hash = parse_json(content)

      # Validate card structure
      validate_card!(card_hash)

      result_character = nil

      ActiveRecord::Base.transaction do
        # Create or update character
        result_character = create_or_update_character(card_hash, file_sha256: file_sha256, character: character)

        # Attach default portrait since JSON files don't include images
        attach_default_portrait(result_character)
      end

      ImportResult.success(result_character)
    rescue InvalidCardError, JSON::ParserError => e
      ImportResult.failure(e.message)
    rescue StandardError => e
      Rails.logger.error("JsonImporter error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      ImportResult.failure("Import failed: #{e.message}")
    end

    # Parse and create character from a JSON string or hash.
    #
    # This is a convenience method for programmatic imports.
    #
    # @param json_or_hash [String, Hash] JSON string or parsed hash
    # @param file_sha256 [String, nil] optional SHA256 for deduplication
    # @param attach_portrait [Boolean] whether to attach default portrait
    # @return [Character] the created character
    def import_from_hash(json_or_hash, file_sha256: nil, attach_portrait: true)
      card_hash = json_or_hash.is_a?(String) ? parse_json(json_or_hash) : json_or_hash
      validate_card!(card_hash)
      character = create_character(card_hash, file_sha256: file_sha256)
      attach_default_portrait(character) if attach_portrait
      character
    end

    private
  end
end
