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
      # Convert Schema to Hash with string keys for export
      # Use JSON round-trip to properly serialize nested Schema objects
      data_hash = character.data.present? ? JSON.parse(character.data.to_json) : {}

      # Merge embedded character_book with primary linked lorebook
      merged_book = build_merged_character_book
      if merged_book
        data_hash["character_book"] = merged_book
      else
        # Remove empty character_book if no content
        data_hash.delete("character_book") if data_hash["character_book"].blank?
      end

      # Include assets from character_assets if present (if not already in data)
      if character.character_assets.any? && data_hash["assets"].blank?
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
        "name" => data&.name,
        "description" => data&.description || "",
        "personality" => data&.personality || "",
        "scenario" => data&.scenario || "",
        "first_mes" => data&.first_mes || "",
        "mes_example" => data&.mes_example || "",
        "creator_notes" => data&.creator_notes || "",
        "system_prompt" => data&.system_prompt || "",
        "post_history_instructions" => data&.post_history_instructions || "",
        "alternate_greetings" => data&.alternate_greetings || [],
        "tags" => data&.tags || [],
        "creator" => data&.creator || "",
        "character_version" => data&.character_version || "",
        "extensions" => data&.extensions || {},
      }

      # Merge embedded character_book with primary linked lorebook
      merged_book = build_merged_character_book
      data_hash["character_book"] = merged_book if merged_book

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

    # Build the merged character_book for export.
    # Combines embedded character_book with primary linked lorebook (if any).
    # This matches SillyTavern's behavior: primary lorebook is merged into
    # character_book for export.
    #
    # @return [Hash, nil] merged character_book or nil if none
    def build_merged_character_book
      embedded_book = character.data&.character_book
      primary_link = character.character_lorebooks.primary.enabled.first
      world_lorebook = primary_link ? nil : find_lorebook_for_world_name(character.data&.world_name)

      # No books to merge
      return nil unless embedded_book || primary_link || world_lorebook

      # Convert embedded book to hash
      embedded_hash = embedded_book ? JSON.parse(embedded_book.to_json) : nil

      # Convert primary linked lorebook to hash
      primary_hash =
        if primary_link
          primary_link.lorebook.export_to_json.deep_stringify_keys
        elsif world_lorebook
          world_lorebook.export_to_json.deep_stringify_keys
        end

      # Only one source - return it directly
      return embedded_hash if embedded_hash && !primary_hash
      return primary_hash if primary_hash && !embedded_hash

      # Both exist - merge them
      merge_character_books(embedded_hash, primary_hash)
    end

    # Merge two character_book hashes.
    # The primary lorebook entries are appended to embedded entries.
    #
    # @param embedded [Hash] embedded character_book hash
    # @param primary [Hash] primary lorebook export hash
    # @return [Hash] merged character_book
    def merge_character_books(embedded, primary)
      merged = embedded.deep_dup

      # Use the embedded name, or fall back to primary
      merged["name"] ||= primary["name"]

      # Merge entries: convert hash entries to array if needed
      embedded_entries = normalize_entries(embedded["entries"])
      primary_entries = normalize_entries(primary["entries"])

      # Combine entries, avoiding UID conflicts
      existing_uids = Set.new(embedded_entries.map { |e| e["uid"] || e[:uid] })
      primary_entries.each do |entry|
        entry_uid = entry["uid"] || entry[:uid]
        # Skip if UID already exists, otherwise add with new UID
        if existing_uids.include?(entry_uid)
          entry = entry.merge("uid" => "#{entry_uid}_primary")
        end
        embedded_entries << entry
      end

      merged["entries"] = embedded_entries
      merged
    end

    def find_lorebook_for_world_name(name)
      world_name = name.to_s.strip
      return nil if world_name.empty?

      scope = Lorebook.accessible_to_system_or_owned(character.user).where(name: world_name)

      # Prefer owned lorebooks; fall back to system public if none exist.
      if character.user_id
        owned = scope.where(user_id: character.user_id).order(updated_at: :desc, id: :desc).first
        return owned if owned
      end

      scope.where(user_id: nil, visibility: "public").order(updated_at: :desc, id: :desc).first
    end

    # Normalize entries from either array or hash format to array.
    #
    # @param entries [Array, Hash, nil] entries in various formats
    # @return [Array<Hash>]
    def normalize_entries(entries)
      case entries
      when Array
        entries.map { |e| e.is_a?(Hash) ? e : {} }
      when Hash
        entries.map { |uid, data| data.merge("uid" => uid.to_s) }
      else
        []
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
