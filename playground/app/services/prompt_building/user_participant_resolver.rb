# frozen_string_literal: true

module PromptBuilding
  class UserParticipantResolver
    def initialize(space:, speaker:)
      @space = space
      @speaker = speaker
    end

    # @return [TavernKit::User]
    def call
      if speaker_is_user_with_persona?
        ai_membership = @space.space_memberships.participating.ai_characters.by_position.first
        if ai_membership
          return ::TavernKit::User.new(
            name: ai_membership.display_name,
            persona: ai_membership.character&.personality
          )
        end
      end

      user_participant =
        @space.space_memberships.active.find { |m| m.user? && !m.copilot_full? } ||
        @space.space_memberships.active.find(&:user?)

            return ParticipantAdapter.to_user_participant(user_participant) if user_participant

      ::TavernKit::User.new(name: "User", persona: nil)
    end

    private

    def speaker_is_user_with_persona?
      @speaker&.user? && @speaker&.character?
    end
  end
end
