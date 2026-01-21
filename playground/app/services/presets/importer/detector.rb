# frozen_string_literal: true

module Presets
  module Importer
    # Detects the format of an uploaded preset file and delegates
    # to the appropriate importer.
    #
    # Supports:
    # - TavernKit native format (has `tavernkit_preset_version` field)
    # - SillyTavern OpenAI format (has `chat_completion_source` or `prompts` array)
    #
    # @example Import a file
    #   detector = Presets::Importer::Detector.new
    #   result = detector.execute(uploaded_file, user: current_user)
    #
    class Detector
      # Import a preset file, auto-detecting the format.
      #
      # @param file [ActionDispatch::Http::UploadedFile, IO] the uploaded file
      # @param user [User] the user who owns the imported preset
      # @return [ImportResult] the import result
      def execute(file, user:)
        content = read_file(file)
        filename = extract_filename(file)
        data = parse_json(content)

        importer = detect_importer(data)
        importer.execute(data, user: user, filename: filename)
      rescue JSON::ParserError => e
        Presets::Importer::ImportResult.failure("Invalid JSON format: #{e.message}")
      rescue Presets::Importer::InvalidFormatError, Presets::Importer::UnrecognizedFormatError => e
        Presets::Importer::ImportResult.failure(e.message)
      rescue StandardError => e
        Rails.logger.error("Preset import error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        Presets::Importer::ImportResult.failure("Import failed: #{e.message}")
      end

      private

      def read_file(file)
        if file.respond_to?(:read)
          content = file.read
          file.rewind if file.respond_to?(:rewind)
          content
        else
          file.to_s
        end
      end

      def extract_filename(file)
        if file.respond_to?(:original_filename)
          file.original_filename
        elsif file.respond_to?(:path)
          File.basename(file.path)
        else
          nil
        end
      end

      def parse_json(content)
        JSON.parse(content)
      end

      def detect_importer(data)
        return TavernKitImporter.new if tavernkit_format?(data)
        return SillyTavernImporter.new if silly_tavern_format?(data)

        raise Presets::Importer::UnrecognizedFormatError, "Unrecognized preset format. Expected TavernKit or SillyTavern OpenAI format."
      end

      def tavernkit_format?(data)
        data.key?("tavernkit_preset_version")
      end

      def silly_tavern_format?(data)
        # SillyTavern OpenAI presets have chat_completion_source or prompts array
        data.key?("chat_completion_source") ||
          (data.key?("prompts") && data["prompts"].is_a?(Array)) ||
          # Also detect by presence of typical ST OpenAI fields
          (data.key?("openai_max_tokens") && data.key?("temperature"))
      end
    end
  end
end
