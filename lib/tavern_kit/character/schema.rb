# frozen_string_literal: true

require "easy_talk"
require_relative "asset_schema"
require_relative "character_book_schema"
require_relative "extensions_schema"

module TavernKit
  class Character
    # Schema for Character Card data (V2/V3 unified).
    #
    # This schema represents the `data` object within a Character Card.
    # It supports all fields from both V2 and V3 specifications, with V3
    # being a superset of V2.
    #
    # Design principle: "strict in, strict out" - requires spec-compliant
    # input and exports spec-compliant data.
    #
    # @see https://github.com/malfoyslastname/character-card-spec-v2
    # @see https://github.com/kwaroran/character-card-spec-v3
    class Schema
      include EasyTalk::Schema

      define_schema do
        title "Character Card Data"
        description "Character Card data object (V2/V3 unified)"

        # ===== V2 Base Fields =====

        # Character name (required)
        property :name, String, min_length: 1,
          description: "Character's display name"

        # Character description/backstory
        property :description, T.nilable(String), optional: true,
          description: "Character's description and backstory"

        # Character personality traits
        property :personality, T.nilable(String), optional: true,
          description: "Character's personality traits"

        # Roleplay scenario/setting
        property :scenario, T.nilable(String), optional: true,
          description: "The roleplay scenario or setting"

        # First message (greeting)
        property :first_mes, T.nilable(String), optional: true,
          description: "First message/greeting from the character"

        # Example dialogue
        property :mes_example, T.nilable(String), optional: true,
          description: "Example dialogue in <START> block format"

        # Creator notes (visible to users)
        property :creator_notes, T.nilable(String), optional: true,
          description: "Notes from the card creator for users"

        # System prompt override
        property :system_prompt, T.nilable(String), optional: true,
          description: "Custom system prompt override"

        # Post-history instructions (jailbreak)
        property :post_history_instructions, T.nilable(String), optional: true,
          description: "Instructions inserted after chat history"

        # Alternative greetings
        property :alternate_greetings, T::Array[String], optional: true,
          description: "Alternative first messages"

        # Embedded lorebook
        property :character_book, T.nilable(CharacterBookSchema), optional: true,
          description: "Embedded character-specific lorebook"

        # Tags for categorization
        property :tags, T::Array[String], optional: true,
          description: "Tags for categorization"

        # Card creator name
        property :creator, T.nilable(String), optional: true,
          description: "Card creator's name"

        # Character version string
        property :character_version, T.nilable(String), optional: true,
          description: "Version string for the character"

        # Extension data (must preserve unknown keys)
        # Note: EasyTalk doesn't support arbitrary Hash types at runtime,
        # so we store this as raw data and handle it manually
        property :extensions, T.nilable(T::Hash[Symbol, T.untyped]), optional: true,
          description: "Application-specific extension data"

        # ===== V3 Additions =====

        # Greetings only shown in group chats (V3 required field)
        property :group_only_greetings, T::Array[String],
          description: "Greetings used only in group chat contexts"

        # Asset references (images, audio, etc.)
        property :assets, T.nilable(T::Array[AssetSchema]), optional: true,
          description: "Embedded or referenced assets"

        # Character nickname (used in {{char}} macro when present)
        property :nickname, T.nilable(String), optional: true,
          description: "Character nickname (replaces name in {{char}} macro)"

        # Multilingual creator notes (keys are ISO 639-1 language codes)
        # Note: EasyTalk doesn't support arbitrary Hash types at runtime,
        # so we store this as raw data and handle it manually
        property :creator_notes_multilingual, T.nilable(T::Hash[Symbol, String]), optional: true,
          description: "Localized creator notes by ISO 639-1 language code"

        # Source URLs/references
        property :source, T.nilable(T::Array[String]), optional: true,
          description: "Source URLs or IDs for the character card"

        # Creation timestamp (Unix seconds)
        property :creation_date, T.nilable(Integer), optional: true,
          description: "Creation date as Unix timestamp (seconds)"

        # Modification timestamp (Unix seconds)
        property :modification_date, T.nilable(Integer), optional: true,
          description: "Last modification date as Unix timestamp (seconds)"
      end

      # Get the display name (nickname if present, otherwise name)
      # This matches CCv3 {{char}} macro behavior
      def display_name
        nickname.presence || name
      end

      # Check if this card has a nickname set
      def nickname?
        nickname.present?
      end

      # Check if this card has an embedded lorebook
      def character_book?
        character_book.present? && !character_book.empty?
      end

      # Check if this card has assets
      def assets?
        assets.present? && assets.any?
      end

      # Get the main icon asset
      def main_icon
        assets&.find(&:main_icon?)
      end

      # Get the main background asset
      def main_background
        assets&.find(&:main_background?)
      end

      # Get all greetings (first_mes + alternates + group_only)
      def all_greetings
        greetings = []
        greetings << first_mes if first_mes.present?
        greetings.concat(alternate_greetings) if alternate_greetings&.any?
        greetings
      end

      # Get group-specific greetings
      def group_greetings
        all_greetings + (group_only_greetings || [])
      end

      # Get creator notes for a specific language
      # Falls back to English or default creator_notes
      def creator_notes_for(lang = "en")
        return creator_notes unless creator_notes_multilingual.present?

        creator_notes_multilingual[lang] ||
          creator_notes_multilingual["en"] ||
          creator_notes
      end

      # Check if this is a V3 card (has V3-only fields)
      def v3_features?
        assets.present? ||
          nickname.present? ||
          creator_notes_multilingual.present? ||
          source.present? ||
          creation_date.present? ||
          modification_date.present?
      end

      # =====================
      # SillyTavern Extensions
      # =====================

      # Check if `extensions.talkativeness` is present (key exists).
      #
      # SillyTavern stores this under `data.extensions.talkativeness` and uses it
      # as a per-character probability (0.0-1.0) for group chat activation.
      #
      # @return [Boolean]
      def talkativeness?
        extension_key?(:talkativeness)
      end

      # Coerce `extensions.talkativeness` to a Float using SillyTavern semantics.
      #
      # ST uses:
      #   talk = isNaN(character.talkativeness) ? talkativeness_default : Number(character.talkativeness)
      #
      # Notes:
      # - If the key is missing, returns `default`.
      # - If the key exists but value is `nil` (JSON `null`), returns `0.0`.
      # - Non-numeric strings (e.g. "abc") fall back to `default`.
      #
      # @param default [Float] fallback when talkativeness is unset or invalid
      # @return [Float]
      def talkativeness_factor(default: 0.5)
        return default unless talkativeness?

        raw = extension_value(:talkativeness)
        number = coerce_js_number(raw)
        number.nan? ? default : number
      end

      # Get the character-bound primary World Info / lorebook name.
      #
      # SillyTavern stores this under `data.extensions.world` (string). When
      # set, it indicates a "primary" world info book linked to the character.
      #
      # @return [String, nil]
      def world_name
        raw = extension_value(:world)
        name = raw.to_s.strip
        name.empty? ? nil : name
      end

      # Get additional World Info / lorebook names linked to the character.
      #
      # TavernKit uses `data.extensions.extra_worlds` as an optional list of
      # additional lorebooks to activate alongside the primary `world` link.
      #
      # @return [Array<String>]
      def extra_world_names
        raw = extension_value(:extra_worlds)
        return [] unless raw.is_a?(Array)

        raw.map { |w| w.to_s.strip }.reject(&:empty?)
      end

      private

      def extension_key?(key)
        ext = extensions
        return false unless ext.is_a?(Hash)

        ext.key?(key.to_s) || ext.key?(key.to_sym)
      end

      def extension_value(key)
        ext = extensions
        return nil unless ext.is_a?(Hash)

        string_key = key.to_s
        return ext[string_key] if ext.key?(string_key)

        symbol_key = key.to_sym
        return ext[symbol_key] if ext.key?(symbol_key)

        nil
      end

      # Coerce a Ruby value using JavaScript `Number()`-like behavior.
      #
      # @return [Float] may be NaN
      def coerce_js_number(value)
        case value
        when nil
          0.0
        when true
          1.0
        when false
          0.0
        when Numeric
          value.to_f
        when String
          s = value.strip
          return 0.0 if s.empty?

          Float(s)
        else
          s = value.to_s.strip
          return 0.0 if s.empty?

          Float(s)
        end
      rescue ArgumentError, TypeError
        Float::NAN
      end
    end
  end
end
