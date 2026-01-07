# frozen_string_literal: true

module PromptBuilding
  module WorldInfoBookOverrides
    # Apply world-info-related overrides to a SillyTavern-style "character_book" hash.
    #
    # Today we only override recursive scanning behavior, but keeping this in one
    # place ensures PromptBuilder and LoreBooksResolver stay consistent.
    #
    # @param book_hash [Hash] character_book hash
    # @param space [Space] space that provides prompt_settings.world_info
    # @return [Hash, nil]
    def self.apply(book_hash, space:)
      return nil unless book_hash.is_a?(Hash)

      wi_settings = space.prompt_settings&.world_info
      recursive = wi_settings ? wi_settings.recursive != false : true

      dup = book_hash.deep_dup
      dup["recursiveScanning"] = recursive
      dup["recursive_scanning"] = recursive
      dup
    end
  end
end
