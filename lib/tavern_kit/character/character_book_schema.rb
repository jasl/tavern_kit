# frozen_string_literal: true

require "easy_talk"
require_relative "character_book_entry_schema"
require_relative "extensions_schema"

module TavernKit
  class Character
    # Schema for Character Book (Lorebook) objects.
    #
    # A character book is a collection of knowledge entries that can be
    # conditionally injected into prompts based on keyword matching.
    #
    # @see https://github.com/kwaroran/character-card-spec-v3
    class CharacterBookSchema
      include EasyTalk::Schema

      define_schema do
        title "Character Book"
        description "A lorebook containing conditional knowledge entries"

        # Book name for identification (optional)
        property :name, T.nilable(String), optional: true,
          description: "Book name for identification"

        # Book description (optional)
        property :description, T.nilable(String), optional: true,
          description: "Book description or notes"

        # How many recent messages to scan for keyword matches (optional)
        property :scan_depth, T.nilable(Integer), optional: true,
          minimum: 0,
          description: "Number of recent messages to scan for keyword matches"

        # Maximum tokens to use for lorebook content (optional)
        property :token_budget, T.nilable(Integer), optional: true,
          minimum: 0,
          description: "Maximum tokens to allocate for lorebook content"

        # Whether to scan activated entries for more keyword matches (optional)
        property :recursive_scanning, T.nilable(T::Boolean), optional: true,
          description: "Scan activated entry content for additional keyword matches"

        # Extension data for app-specific storage (required, preserves unknown fields)
        property :extensions, ExtensionsSchema, optional: true,
          description: "Application-specific extension data (must preserve unknown keys)"

        # Lorebook entries (required, can be empty)
        property :entries, T::Array[CharacterBookEntrySchema],
          description: "Array of lorebook entries"
      end

      # Check if recursive scanning is enabled
      def recursive_scanning?
        recursive_scanning == true
      end

      # Get enabled entries only
      def enabled_entries
        (entries || []).select(&:enabled)
      end

      # Get constant entries (always active)
      def constant_entries
        (entries || []).select(&:constant?)
      end

      # Check if the book is empty
      def empty?
        entries.nil? || entries.empty?
      end

      # Get entry count
      def entry_count
        (entries || []).size
      end
    end
  end
end
