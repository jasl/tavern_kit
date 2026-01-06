# frozen_string_literal: true

require "easy_talk"
require_relative "extensions_schema"

module TavernKit
  class Character
    # Schema for Character Book (Lorebook) Entry objects.
    #
    # Entries are activated during prompt generation when their keywords
    # are matched in the scan buffer. Activated entries inject their content
    # into the prompt at the configured position.
    #
    # @see https://github.com/kwaroran/character-card-spec-v3
    class CharacterBookEntrySchema
      include EasyTalk::Schema

      define_schema do
        title "Character Book Entry"
        description "A single lorebook entry for character knowledge injection"

        # Primary activation keys (required)
        property :keys, T::Array[String],
          description: "Primary activation keywords or regex patterns"

        # Content to inject when activated (required)
        property :content, String,
          description: "Content to inject into the prompt when entry is activated"

        # Extension data for app-specific storage (required, preserves unknown fields)
        property :extensions, ExtensionsSchema, optional: true,
          description: "Application-specific extension data (must preserve unknown keys)"

        # Whether the entry is active (required)
        property :enabled, T::Boolean, default: true,
          description: "Whether this entry is active"

        # Order for insertion when multiple entries match (required)
        # Lower numbers are inserted earlier
        property :insertion_order, Integer, default: 100,
          description: "Insertion order (lower = earlier)"

        # V3 REQUIRED: Whether keys are regex patterns
        property :use_regex, T::Boolean, default: false,
          description: "When true, keys are treated as regex patterns (V3 required)"

        # Whether key matching is case-sensitive (optional)
        property :case_sensitive, T.nilable(T::Boolean), optional: true,
          description: "Whether key matching is case-sensitive"

        # Whether entry is always active regardless of key matches (optional)
        property :constant, T.nilable(T::Boolean), optional: true,
          description: "Always activate regardless of key matches"

        # Entry name/memo for identification (optional, ST/Risu compatibility)
        property :name, T.nilable(String), optional: true,
          description: "Entry name or memo for identification"

        # Priority for token budget trimming (optional, AgnAI compatibility)
        property :priority, T.nilable(Integer), optional: true,
          description: "Priority for token budget trimming (higher = keep longer)"

        # Unique identifier (optional, ST/Risu compatibility)
        # Can be string or integer depending on the source
        property :id, T.nilable(String), optional: true,
          description: "Unique entry identifier"

        # Comment/memo field (optional, ST/Risu compatibility)
        property :comment, T.nilable(String), optional: true,
          description: "Entry comment or description"

        # Secondary key matching (optional)
        property :selective, T.nilable(T::Boolean), optional: true,
          description: "Enable secondary key matching"

        property :secondary_keys, T.nilable(T::Array[String]), optional: true,
          description: "Secondary activation keywords (requires selective=true)"

        # Insertion position (optional, V2 values: before_char, after_char)
        # V3 extends via @@position decorator
        property :position, T.nilable(String), optional: true,
          enum: %w[before_char after_char],
          description: "Insertion position relative to character definition"
      end

      # Check if this entry uses regex matching
      def regex?
        use_regex == true
      end

      # Check if this entry is always active
      def constant?
        constant == true
      end

      # Check if secondary key matching is enabled
      def selective?
        selective == true && secondary_keys&.any?
      end

      # Get display name (comment, name, or first key)
      def display_name
        comment.presence || name.presence || keys&.first&.truncate(50) || "Entry #{id}"
      end
    end
  end
end
