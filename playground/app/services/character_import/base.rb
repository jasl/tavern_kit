# frozen_string_literal: true

module CharacterImport
  # Result object for import operations.
  #
  # @example Successful import
  #   result = ImportResult.success(character)
  #   result.success?  # => true
  #   result.character # => #<Character ...>
  #
  # @example Duplicate detection
  #   result = ImportResult.duplicate(existing_character)
  #   result.duplicate?  # => true
  #
  # @example Failed import
  #   result = ImportResult.failure("Invalid card format")
  #   result.failure?  # => true
  #   result.error     # => "Invalid card format"
  #
  ImportResult = Data.define(:status, :character, :error) do
    def self.success(character)
      new(status: :success, character: character, error: nil)
    end

    def self.duplicate(character)
      new(status: :duplicate, character: character, error: nil)
    end

    def self.failure(error)
      new(status: :failure, character: nil, error: error)
    end

    def success?
      status == :success
    end

    def duplicate?
      status == :duplicate
    end

    def failure?
      status == :failure
    end
  end

  # Base class for character importers.
  #
  # Provides common interface and utilities for importing character cards
  # from various formats (JSON, PNG, CharX).
  #
  # @abstract Subclass and implement {#call} to create an importer.
  #
  # @example Implementing an importer
  #   class MyImporter < Base
  #     def call(io, filename:)
  #       # Parse the file
  #       data = parse(io)
  #       # Create character
  #       create_character(data)
  #     end
  #   end
  #
  class Base
    # Import a character from the given IO.
    #
    # @param io [IO, StringIO, Tempfile] the input to import from
    # @param filename [String] original filename (for format detection)
    # @param character [Character, nil] optional existing character to update (placeholder)
    # @return [ImportResult] the import result
    def call(io, filename:, character: nil)
      raise NotImplementedError, "Subclasses must implement #call"
    end

    protected

    # Create or update a Character record from parsed card data.
    #
    # If a character is provided (placeholder), it will be updated with the parsed data.
    # Otherwise, a new character will be created.
    #
    # @param card_hash [Hash] parsed character card hash
    # @param file_sha256 [String, nil] SHA256 of source file for deduplication
    # @param character [Character, nil] optional existing character to update
    # @return [Character] the created or updated character
    def create_or_update_character(card_hash, file_sha256: nil, character: nil)
      spec_version = detect_spec_version(card_hash)
      data = card_hash["data"]

      raise InvalidCardError, "Missing data object in card" unless data.is_a?(Hash)
      raise InvalidCardError, "Missing name in card data" if data["name"].blank?

      if character
        # Update existing placeholder character
        character.update!(
          name: data["name"],
          data: data,
          spec_version: spec_version,
          file_sha256: file_sha256,
          status: "ready"
        )
        character
      else
        # Create new character (backward compatibility)
        Character.create!(
          name: data["name"],
          data: data,
          spec_version: spec_version,
          file_sha256: file_sha256,
          status: "ready"
        )
      end
    end

    # Create a Character record from parsed card data.
    # @deprecated Use {#create_or_update_character} instead
    #
    # @param card_hash [Hash] parsed character card hash
    # @param file_sha256 [String, nil] SHA256 of source file for deduplication
    # @return [Character] the created character
    def create_character(card_hash, file_sha256: nil)
      create_or_update_character(card_hash, file_sha256: file_sha256, character: nil)
    end

    # Detect the spec version from a card hash.
    #
    # @param card_hash [Hash] the card hash
    # @return [Integer] 2 or 3
    # @raise [InvalidCardError] if spec is not recognized
    def detect_spec_version(card_hash)
      spec = card_hash["spec"]

      case spec
      when "chara_card_v2"
        2
      when "chara_card_v3"
        3
      else
        raise InvalidCardError, "Unknown spec: #{spec.inspect}. Expected 'chara_card_v2' or 'chara_card_v3'."
      end
    end

    # Validate that the card hash has required structure.
    #
    # @param card_hash [Hash] the card hash
    # @raise [InvalidCardError] if validation fails
    def validate_card!(card_hash)
      raise InvalidCardError, "Card must be a Hash" unless card_hash.is_a?(Hash)
      raise InvalidCardError, "Missing spec field" if card_hash["spec"].blank?
      raise InvalidCardError, "Missing data field" unless card_hash["data"].is_a?(Hash)
      raise InvalidCardError, "Missing name in data" if card_hash.dig("data", "name").blank?
    end

    # Parse JSON from string or IO.
    #
    # @param input [String, IO] JSON string or IO
    # @return [Hash] parsed JSON
    # @raise [InvalidCardError] if JSON is invalid
    def parse_json(input)
      json_string = input.respond_to?(:read) ? input.read : input
      JSON.parse(json_string)
    rescue JSON::ParserError => e
      raise InvalidCardError, "Invalid JSON: #{e.message}"
    end

    # Compute SHA256 hash of content.
    #
    # @param content [String] binary content
    # @return [String] hex-encoded SHA256
    def compute_sha256(content)
      Digest::SHA256.hexdigest(content)
    end

    # Find an existing character with the same file hash.
    #
    # @param file_sha256 [String] the file hash
    # @return [Character, nil]
    def find_duplicate(file_sha256)
      return nil if file_sha256.blank?

      Character.find_by(file_sha256: file_sha256)
    end

    # Read entire IO content and rewind.
    #
    # @param io [IO] the IO to read
    # @return [String] binary content
    def read_and_rewind(io)
      content = io.read
      io.rewind if io.respond_to?(:rewind)
      content
    end

    # Attach the default portrait to a character if no portrait is attached.
    #
    # @param character [Character] the character to attach portrait to
    # @return [void]
    def attach_default_portrait(character)
      return if character.portrait.attached?

      default_path = Rails.root.join("app/assets/images/default_portrait.png")
      return unless File.exist?(default_path)

      character.portrait.attach(
        io: StringIO.new(File.binread(default_path)),
        filename: "default_portrait.png",
        content_type: "image/png"
      )
    end
  end

  # Error raised when character card format is invalid.
  class InvalidCardError < StandardError; end

  # Error raised when file format is not supported.
  class UnsupportedFormatError < StandardError; end
end
