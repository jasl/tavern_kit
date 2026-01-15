# frozen_string_literal: true

module PromptBuilding
  class UserParticipantResolver
    def initialize(space:, speaker:)
      @space = space
      @speaker = speaker
    end

    # @return [TavernKit::User]
    def call
      # If the speaker is a human in copilot mode (either with character or pure human with persona),
      # use their membership for the user participant
      if speaker_is_human_copilot?
        return ParticipantAdapter.to_user_participant(@speaker)
      end

      user_participant =
        @space.space_memberships.active.find { |m| m.user? && !m.copilot_full? } ||
        @space.space_memberships.active.find(&:user?)

      return ParticipantAdapter.to_user_participant(user_participant) if user_participant

      ::TavernKit::User.new(name: "User", persona: nil)
    end

    private

    # Check if speaker is a human using copilot mode.
    # This includes:
    # - Human with persona character (copilot_full? && character_id present)
    # - Pure human with custom persona (copilot_full? && persona present)
    def speaker_is_human_copilot?
      @speaker&.user? && @speaker&.copilot_full?
    end
  end
end
