# frozen_string_literal: true

module PromptBuilding
  # Converts Character records into TavernKit characters for prompt building.
  class CharacterAdapter
    # @param character [Character]
    # @return [TavernKit::Character]
    def self.to_tavern_kit_character(character)
      raise ArgumentError, "character is required" unless character

      ::TavernKit::CharacterCard.load_hash(character.export_card_hash)
    end
  end
end
