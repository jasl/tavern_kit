# frozen_string_literal: true

# Atomically decrements auto remaining steps for an auto-enabled human membership.
#
# This is concurrency-sensitive code: it uses conditional UPDATE statements to avoid
# double-decrement under concurrent calls.
#
module SpaceMemberships
  class AutoStepsDecrementer
    def self.execute(membership:)
      new(membership: membership).execute
    end

    def initialize(membership:)
      @membership = membership
    end

    def execute
      call
    end

    # @return [Boolean] true if successfully decremented, false if conditions not met
    def call
      return false unless membership.user? && membership.auto_enabled?

      updated_count = SpaceMembership
        .where(id: membership.id)
        .where(auto: "auto")
        .where("auto_remaining_steps > 0")
        .update_all("auto_remaining_steps = auto_remaining_steps - 1")

      return false if updated_count == 0

      membership.reload

      if membership.auto_remaining_steps.to_i <= 0
        disabled_count = SpaceMembership
          .where(id: membership.id, auto: "auto", auto_remaining_steps: 0)
          .update_all(auto: "none", auto_remaining_steps: nil)

        if disabled_count > 0
          membership.reload
          Messages::Broadcasts.broadcast_auto_disabled(membership, reason: "remaining_steps_exhausted")
        end
      else
        Messages::Broadcasts.broadcast_auto_steps_updated(membership, remaining_steps: membership.auto_remaining_steps)
      end

      true
    end

    private :call

    private

    attr_reader :membership
  end
end
