# frozen_string_literal: true

module PromptBuilding
  # Converts Rails app-layer records into TavernKit prompt participants.
  #
  # This keeps AR models free of TavernKit object construction.
  #
  class ParticipantAdapter
    # @param membership [SpaceMembership]
    # @return [TavernKit::Character, TavernKit::User]
    def self.to_participant(membership)
      raise ArgumentError, "membership is required" unless membership

      return CharacterAdapter.to_tavern_kit_character(membership.character) if membership.character

      to_user_participant(membership)
    end

    # @param membership [SpaceMembership]
    # @return [TavernKit::User]
    def self.to_user_participant(membership)
      raise ArgumentError, "membership is required" unless membership

      ::TavernKit::User.new(name: membership.display_name, persona: membership.effective_persona)
    end
  end
end
