# frozen_string_literal: true

module PromptBuilding
  module WorldInfoBookOverrides
    # Apply world-info-related overrides to a SillyTavern-style world info book.
    #
    # Today we only override recursive scanning behavior, but keeping this in one
    # place ensures PromptBuilder and LoreBooksResolver stay consistent.
    #
    # @param book [Hash, TavernKit::Lore::Book] book hash or object
    # @param space [Space] space that provides prompt_settings.world_info
    # @return [Hash, TavernKit::Lore::Book, nil] same type as input, or nil if unchanged
    def self.apply(book, space:)
      return nil if book.nil?

      wi_settings = space.prompt_settings&.world_info
      recursive = wi_settings ? wi_settings.recursive != false : true

      case book
      when Hash
        # Match TavernKit::Lore::Book.from_hash's ST-export detection:
        # - ST World Info JSON exports use camelCase keys
        # - Character-card embedded character_book uses snake_case keys
        st_style = book.key?("scanDepth") || book.key?("tokenBudget") || book.key?("recursiveScanning")
        key = st_style ? "recursiveScanning" : "recursive_scanning"

        return nil if book[key] == recursive

        dup = book.deep_dup
        dup[key] = recursive
        dup
      when ::TavernKit::Lore::Book
        return nil if book.recursive_scanning == recursive

        ::TavernKit::Lore::Book.new(
          name: book.name,
          description: book.description,
          scan_depth: book.scan_depth,
          token_budget: book.token_budget,
          recursive_scanning: recursive,
          entries: book.entries,
          extensions: book.extensions,
          source: book.source,
          raw: book.raw
        )
      else
        nil
      end
    end
  end
end
