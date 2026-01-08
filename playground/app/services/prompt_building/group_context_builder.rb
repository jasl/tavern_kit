# frozen_string_literal: true

module PromptBuilding
  class GroupContextBuilder
    def initialize(space:, current_character_membership:)
      @space = space
      @current_character_membership = current_character_membership
    end

    def call
      character_memberships = @space.space_memberships.active.ai_characters.by_position
      members = character_memberships.map(&:display_name)
      muted = character_memberships.reject(&:participation_active?).map(&:display_name)
      current_character = @current_character_membership&.display_name

      ::TavernKit::GroupContext.new(
        members: members,
        muted: muted,
        current_character: current_character
      )
    end
  end
end
