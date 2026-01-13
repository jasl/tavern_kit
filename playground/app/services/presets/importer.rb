# frozen_string_literal: true

module Presets
  # Namespace for preset import services.
  #
  # Defines shared types used across importers:
  # - ImportResult: Result object for import operations
  # - InvalidFormatError: Raised when preset format is invalid
  # - UnrecognizedFormatError: Raised when format is not recognized
  #
  module Importer
    # Result object for import operations.
    #
    # @example Successful import
    #   result = ImportResult.success(preset)
    #   result.success?  # => true
    #   result.preset    # => #<Preset ...>
    #
    # @example Failed import
    #   result = ImportResult.failure("Invalid JSON format")
    #   result.failure?  # => true
    #   result.error     # => "Invalid JSON format"
    #
    ImportResult = Data.define(:status, :preset, :error) do
      def self.success(preset)
        new(status: :success, preset: preset, error: nil)
      end

      def self.failure(error)
        new(status: :failure, preset: nil, error: error)
      end

      def success?
        status == :success
      end

      def failure?
        status == :failure
      end
    end

    # Error raised when preset format is invalid.
    class InvalidFormatError < StandardError; end

    # Error raised when format is not recognized.
    class UnrecognizedFormatError < StandardError; end
  end
end
