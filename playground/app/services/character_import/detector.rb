# frozen_string_literal: true

module CharacterImport
  # Detects character card file formats and routes to appropriate importer.
  #
  # Supports:
  # - JSON files (.json)
  # - PNG files with embedded metadata (.png, .apng)
  # - CharX archives (.charx)
  # - JPEG files with embedded CharX data (.jpg, .jpeg)
  #
  # @example Import any supported format
  #   result = CharacterImport::Detector.import(file, filename: "card.png")
  #   if result.success?
  #     character = result.character
  #   end
  #
  # @example Detect format without importing
  #   format = CharacterImport::Detector.detect(filename: "card.charx")
  #   # => :charx
  #
  class Detector
    # File signatures for format detection
    PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
    ZIP_SIGNATURE = "PK".b.freeze
    JPEG_SIGNATURES = ["\xFF\xD8\xFF".b].freeze

    class << self
      # Import a character from any supported format.
      #
      # @param io [IO, StringIO, Tempfile, ActionDispatch::Http::UploadedFile] the file to import
      # @param filename [String] original filename for format detection
      # @param character [Character, nil] optional existing character to update (placeholder)
      # @return [ImportResult] the import result
      def import(io, filename:, character: nil)
        format = detect(io: io, filename: filename)
        importer = importer_for(format)
        importer.execute(io, filename: filename, character: character)
      end

      # Detect file format from filename and/or content.
      #
      # @param io [IO, nil] optional IO for content-based detection
      # @param filename [String] filename for extension-based detection
      # @return [Symbol] :json, :png, :charx, :jpeg, or :unknown
      def detect(io: nil, filename:)
        # First try extension-based detection
        format = detect_by_extension(filename)
        return format if format != :unknown && io.nil?

        # For ambiguous cases, use content-based detection
        return format if io.nil?

        detect_by_content(io, fallback: format)
      end

      # Get the appropriate importer for a format.
      #
      # @param format [Symbol] :json, :png, :charx, or :jpeg
      # @return [Base] importer instance
      # @raise [UnsupportedFormatError] if format is not supported
      def importer_for(format)
        case format
        when :json
          JsonImporter.new
        when :png
          PngImporter.new
        when :charx, :jpeg
          CharxImporter.new
        else
          raise UnsupportedFormatError, "Unsupported format: #{format}"
        end
      end

      # Check if a filename has a supported extension.
      #
      # @param filename [String] the filename to check
      # @return [Boolean]
      def supported?(filename)
        detect_by_extension(filename) != :unknown
      end

      private

      # Detect format by file extension.
      #
      # @param filename [String] the filename
      # @return [Symbol] detected format or :unknown
      def detect_by_extension(filename)
        return :unknown if filename.blank?

        ext = File.extname(filename.to_s).downcase

        case ext
        when ".json"
          :json
        when ".png", ".apng"
          :png
        when ".charx"
          :charx
        when ".jpg", ".jpeg"
          :jpeg
        else
          :unknown
        end
      end

      # Detect format by file content (magic bytes).
      #
      # @param io [IO] the IO to read from
      # @param fallback [Symbol] fallback format if detection fails
      # @return [Symbol] detected format
      def detect_by_content(io, fallback: :unknown)
        # Read first few bytes for signature detection
        header = read_header(io, 16)
        return fallback if header.nil? || header.empty?

        if header.start_with?(PNG_SIGNATURE)
          :png
        elsif header.start_with?(ZIP_SIGNATURE)
          :charx
        elsif JPEG_SIGNATURES.any? { |sig| header.start_with?(sig) }
          # JPEG might be a CharX with embedded JPEG header (RisuAI format)
          # or a regular JPEG with PNG chunks - treat as CharX importer which handles both
          :jpeg
        elsif looks_like_json?(header)
          :json
        else
          fallback
        end
      end

      # Read header bytes from IO without consuming it.
      #
      # @param io [IO] the IO to read from
      # @param bytes [Integer] number of bytes to read
      # @return [String, nil] header bytes
      def read_header(io, bytes)
        return nil unless io.respond_to?(:read)

        # Handle ActionDispatch::Http::UploadedFile
        actual_io = io.respond_to?(:tempfile) ? io.tempfile : io

        header = actual_io.read(bytes)
        actual_io.rewind if actual_io.respond_to?(:rewind)
        header
      end

      # Check if content looks like JSON.
      #
      # @param header [String] first bytes of content
      # @return [Boolean]
      def looks_like_json?(header)
        # JSON typically starts with { or [ (possibly with whitespace/BOM)
        stripped = header.to_s.lstrip
        stripped.start_with?("{") || stripped.start_with?("[")
      end
    end
  end
end
