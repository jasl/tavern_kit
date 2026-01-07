# frozen_string_literal: true

module PromptBuilding
  class GroupContextBuilder
    def initialize(space:, speaker:)
      @space = space
      @speaker = speaker
    end

    def call
      character_memberships = @space.space_memberships.active.ai_characters.by_position
      member_names = character_memberships.select(&:participation_active?).map(&:display_name)
      non_participating_names = character_memberships.reject(&:participation_active?).map(&:display_name)
      current_character = @speaker&.display_name

      ::TavernKit::GroupContext.new(
        members: member_names,
        muted: non_participating_names,
        current_character: current_character
      )
    end
  end
end
