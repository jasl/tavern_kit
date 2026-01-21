# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Stops the current scheduling and clears round state.
    #
    # Use this for user-initiated interruption/recovery flows (stop auto-mode,
    # user message priority reset, stuck run recovery).
    #
    class StopRound
      def self.execute(conversation:, ended_reason: "stop_round")
        new(conversation, ended_reason).execute
      end

      # Variant for callers that already hold `conversation.with_lock`.
      # Does NOT broadcast updates.
      def self.execute_in_lock(conversation:, ended_reason: "stop_round")
        new(conversation, ended_reason).execute_in_lock
      end

      def initialize(conversation, ended_reason)
        @conversation = conversation
        @space = conversation.space
        @ended_reason = ended_reason.to_s
      end

      # @return [Boolean] true if stopped successfully
      def execute
        @conversation.with_lock do
          execute_in_lock
        end

        Broadcasts.queue_updated(@conversation)
        true
      end

      def execute_in_lock
        cancel_queued_runs
        cancel_active_round
      end

      private

      def cancel_queued_runs
        @conversation.conversation_runs.queued.find_each do |run|
          broadcast_typing_off(run.speaker_space_membership_id)

          run.update!(
            status: "canceled",
            finished_at: Time.current,
            debug: run.debug.merge(
              "canceled_by" => "stop_round",
              "canceled_at" => Time.current.iso8601
            )
          )
        end
      end

      def broadcast_typing_off(membership_id)
        return unless membership_id

        speaker = @space.space_memberships.find_by(id: membership_id)
        ConversationChannel.broadcast_typing(@conversation, membership: speaker, active: false) if speaker
      end

      def cancel_active_round
        active = @conversation.conversation_rounds.find_by(status: "active")
        return unless active

        now = Time.current
        active.update!(
          status: "canceled",
          scheduling_state: nil,
          ended_reason: @ended_reason,
          finished_at: now,
          updated_at: now
        )
      end
    end
  end
end
