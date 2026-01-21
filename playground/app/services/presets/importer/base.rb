# frozen_string_literal: true

module Presets
  module Importer
    # Base class for preset importers.
    #
    # Provides common interface and utilities for importing presets
    # from various formats (TavernKit native, SillyTavern OpenAI).
    #
    # @abstract Subclass and implement {#execute} to create an importer.
    #
    class Base
      # Import a preset from the given data.
      #
      # @param data [Hash] parsed JSON data
      # @param user [User] the user who owns the imported preset
      # @param filename [String] original filename (for name fallback)
      # @return [ImportResult] the import result
      def execute(data, user:, filename: nil)
        raise NotImplementedError, "Subclasses must implement #execute"
      end

      protected

      # Determine the preset name from data or filename.
      #
      # @param data [Hash] the parsed data
      # @param filename [String, nil] the original filename
      # @return [String] the determined name
      def determine_name(data, filename)
        name = data["name"].presence
        return name if name

        return "Imported Preset" if filename.blank?

        # Convert filename to title case: "my-preset.json" -> "My Preset"
        filename.sub(/\.json\z/i, "").tr("-_", " ").titleize
      end

      # Ensure the name is unique by adding a suffix if needed.
      #
      # @param name [String] the base name
      # @param user [User] the user to check uniqueness against
      # @return [String] a unique name
      def ensure_unique_name(name, user)
        return name unless Preset.exists?(name: name, user_id: user&.id)

        counter = 1
        loop do
          candidate = "#{name} (#{counter})"
          return candidate unless Preset.exists?(name: candidate, user_id: user&.id)

          counter += 1
          break if counter > 100 # Safety limit
        end

        "#{name} (#{SecureRandom.hex(4)})"
      end

      # Create a preset with the given attributes.
      #
      # @param attributes [Hash] preset attributes
      # @param user [User] the owner
      # @return [Preset] the created preset
      def create_preset(attributes, user:)
        Preset.create!(
          name: attributes[:name],
          description: attributes[:description],
          user: user,
          visibility: "private",
          generation_settings: attributes[:generation_settings] || {},
          preset_settings: attributes[:preset_settings] || {}
        )
      end

      # Parse JSON from string or IO.
      #
      # @param input [String, IO] JSON string or IO
      # @return [Hash] parsed JSON
      # @raise [InvalidFormatError] if JSON is invalid
      def parse_json(input)
        json_string = input.respond_to?(:read) ? input.read : input
        JSON.parse(json_string)
      rescue JSON::ParserError => e
        raise InvalidFormatError, "Invalid JSON: #{e.message}"
      end
    end
  end
end
