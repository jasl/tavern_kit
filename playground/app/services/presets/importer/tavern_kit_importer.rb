# frozen_string_literal: true

module Presets
  module Importer
    # Imports presets from TavernKit native JSON format.
    #
    # This format is produced by Presets::Exporter and contains
    # all preset settings without any transformation needed.
    #
    # @example Import a TavernKit preset
    #   importer = TavernKitImporter.new
    #   result = importer.execute(data, user: current_user, filename: "my-preset.json")
    #
    class TavernKitImporter < Base
      # Import a preset from TavernKit native format.
      #
      # @param data [Hash] parsed JSON data
      # @param user [User] the user who owns the imported preset
      # @param filename [String, nil] original filename (for name fallback)
      # @return [ImportResult] the import result
      def execute(data, user:, filename: nil)
        validate_format!(data)

        name = determine_name(data, filename)
        unique_name = ensure_unique_name(name, user)

        preset = create_preset(
          {
            name: unique_name,
            description: data["description"],
            generation_settings: data["generation_settings"] || {},
            preset_settings: data["preset_settings"] || {},
          },
          user: user
        )

        ImportResult.success(preset)
      rescue ActiveRecord::RecordInvalid => e
        ImportResult.failure("Failed to create preset: #{e.message}")
      rescue InvalidFormatError => e
        ImportResult.failure(e.message)
      end

      private

      def validate_format!(data)
        unless data.is_a?(Hash)
          raise InvalidFormatError, "Invalid TavernKit preset: expected JSON object"
        end

        unless data.key?("tavernkit_preset_version")
          raise InvalidFormatError, "Invalid TavernKit preset: missing version field"
        end

        version = data["tavernkit_preset_version"]
        unless version == "1.0"
          Rails.logger.warn("TavernKit preset version #{version} may not be fully compatible")
        end
      end
    end
  end
end
