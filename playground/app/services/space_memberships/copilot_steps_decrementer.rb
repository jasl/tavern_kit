# frozen_string_literal: true

# Atomically decrements copilot remaining steps for a full copilot user membership.
#
# This is concurrency-sensitive code: it uses conditional UPDATE statements to avoid
# double-decrement under concurrent calls.
#
module SpaceMemberships
  class CopilotStepsDecrementer
    def self.call(membership:)
      new(membership: membership).call
    end

    def initialize(membership:)
      @membership = membership
    end

    # @return [Boolean] true if successfully decremented, false if conditions not met
    def call
      return false unless membership.user? && membership.copilot_full?

      updated_count = SpaceMembership
        .where(id: membership.id)
        .where(copilot_mode: "full")
        .where("copilot_remaining_steps > 0")
        .update_all("copilot_remaining_steps = copilot_remaining_steps - 1")

      return false if updated_count == 0

      membership.reload

      if membership.copilot_remaining_steps <= 0
        disabled_count = SpaceMembership
          .where(id: membership.id, copilot_mode: "full", copilot_remaining_steps: 0)
          .update_all(copilot_mode: "none")

        if disabled_count > 0
          membership.reload
          Messages::Broadcasts.broadcast_copilot_disabled(membership, reason: "remaining_steps_exhausted")
        end
      else
        Messages::Broadcasts.broadcast_copilot_steps_updated(membership, remaining_steps: membership.copilot_remaining_steps)
      end

      true
    end

    private

    attr_reader :membership
  end
end
