# frozen_string_literal: true

# Namespace for character card import services.
#
# Supports importing from multiple formats:
# - JSON: Plain JSON character card files
# - PNG: PNG images with embedded character data (tEXt chunk)
# - CharX: ZIP archives with card.json and assets
#
# Defines shared types used across importers:
# - ImportResult: Result object for import operations
# - InvalidCardError: Raised when character card format is invalid
# - UnsupportedFormatError: Raised when file format is not supported
#
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

  # Error raised when character card format is invalid.
  class InvalidCardError < StandardError; end

  # Error raised when file format is not supported.
  class UnsupportedFormatError < StandardError; end
end
