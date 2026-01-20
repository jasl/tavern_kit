# frozen_string_literal: true

module PromptBuilding
  class UserParticipantResolver
    def initialize(space:, speaker:)
      @space = space
      @speaker = speaker
    end

    # @return [TavernKit::User]
    def call
      # If the speaker is a human in Auto mode (either with character or pure human with persona),
      # use their membership for the user participant
      if speaker_is_human_auto?
        return ParticipantAdapter.to_user_participant(@speaker)
      end

      user_participant =
        @space.space_memberships.active.find { |m| m.user? && !m.auto_enabled? } ||
        @space.space_memberships.active.find(&:user?)

      return ParticipantAdapter.to_user_participant(user_participant) if user_participant

      ::TavernKit::User.new(name: "User", persona: nil)
    end

    private

    # Check if speaker is a human using Auto mode.
    # This includes:
    # - Human with persona character (auto_enabled? && character_id present)
    # - Pure human with custom persona (auto_enabled? && persona present)
    def speaker_is_human_auto?
      @speaker&.user? && @speaker&.auto_enabled?
    end
  end
end
