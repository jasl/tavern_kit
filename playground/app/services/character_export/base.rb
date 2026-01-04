# frozen_string_literal: true

module CharacterExport
  # Base class for character export services.
  #
  # Provides common functionality for exporting Character records
  # to various formats (JSON, PNG, CharX).
  #
  # @example Subclass usage
  #   class JsonExporter < Base
  #     def call
  #       export_card_hash.to_json
  #     end
  #   end
  #
  class Base
    attr_reader :character, :options

    # Initialize the exporter.
    #
    # @param character [Character] the character to export
    # @param options [Hash] export options
    def initialize(character, **options)
      @character = character
      @options = options
    end

    # Main entry point for the export service.
    # Subclasses must implement this.
    #
    # @return [String, StringIO] the exported content
    def call
      raise NotImplementedError, "Subclasses must implement the 'call' method."
    end

    private

    # Get the target spec version for export.
    #
    # @return [Integer] 2 or 3
    def target_version
      options.fetch(:version, character.spec_version)
    end

    # Build the character card hash for export.
    #
    # @return [Hash] the card hash in the target version format
    def export_card_hash
      if target_version == 3
        build_v3_hash
      else
        build_v2_hash
      end
    end

    # Build a CCv3 compliant hash.
    #
    # @return [Hash]
    def build_v3_hash
      data_hash = character.data.dup

      # Include assets from character_assets if present
      if character.character_assets.any? && !data_hash.key?("assets")
        data_hash["assets"] = build_assets_array
      end

      # Set modification date to now
      data_hash["modification_date"] = Time.current.to_i

      {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => data_hash,
      }
    end

    # Build a CCv2 compliant hash.
    #
    # @return [Hash]
    def build_v2_hash
      data = character.data

      data_hash = {
        "name" => data["name"],
        "description" => data["description"] || "",
        "personality" => data["personality"] || "",
        "scenario" => data["scenario"] || "",
        "first_mes" => data["first_mes"] || "",
        "mes_example" => data["mes_example"] || "",
        "creator_notes" => data["creator_notes"] || "",
        "system_prompt" => data["system_prompt"] || "",
        "post_history_instructions" => data["post_history_instructions"] || "",
        "alternate_greetings" => data["alternate_greetings"] || [],
        "tags" => data["tags"] || [],
        "creator" => data["creator"] || "",
        "character_version" => data["character_version"] || "",
        "extensions" => data["extensions"] || {},
      }

      # Include character_book if present
      data_hash["character_book"] = data["character_book"] if data["character_book"]

      {
        "spec" => "chara_card_v2",
        "spec_version" => "2.0",
        "data" => data_hash,
      }
    end

    # Build the assets array from character_assets.
    # Uses embeded:// URIs as per CCv3 spec.
    # Note: "embeded" (not "embedded") is the correct spelling per spec.
    #
    # @return [Array<Hash>]
    def build_assets_array
      character.character_assets.map do |asset|
        {
          "type" => asset.kind,
          "uri" => "embeded://#{asset.name}.#{asset.ext}",
          "name" => asset.name,
          "ext" => asset.ext,
        }
      end
    end

    # Get the portrait content as binary string.
    #
    # @return [String, nil] portrait binary content or nil if not attached
    def portrait_content
      return nil unless character.portrait.attached?

      character.portrait.blob.download
    end

    # Get the portrait filename.
    #
    # @return [String] filename with extension
    def portrait_filename
      if character.portrait.attached?
        character.portrait.blob.filename.to_s
      else
        "portrait.png"
      end
    end

    # Get the portrait extension.
    #
    # @return [String] extension without dot (e.g., "png")
    def portrait_extension
      if character.portrait.attached?
        File.extname(character.portrait.blob.filename.to_s).delete_prefix(".")
      else
        "png"
      end
    end

    # Get all character assets with their content.
    #
    # @return [Array<Hash>] array of {name:, ext:, kind:, content:}
    def all_assets_with_content
      character.character_assets.map do |asset|
        {
          name: asset.name,
          ext: asset.ext,
          kind: asset.kind,
          content: asset.blob.download,
        }
      end
    end
  end
end
