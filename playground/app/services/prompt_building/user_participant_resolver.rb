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
        return ParticipantAdapter.to_user_participant(@speaker)
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
