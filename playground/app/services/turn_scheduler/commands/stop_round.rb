# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Stops the current scheduling and clears round state.
    #
    # Use this for user-initiated interruption/recovery flows (stop auto-mode,
    # user message priority reset, stuck run recovery).
    #
    class StopRound
      def self.call(conversation:)
        new(conversation).call
      end

      def initialize(conversation)
        @conversation = conversation
        @space = conversation.space
      end

      # @return [Boolean] true if stopped successfully
      def call
        @conversation.with_lock do
          cancel_queued_runs

          @conversation.reset_scheduling!
        end

        Broadcasts.queue_updated(@conversation)
        true
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
    end
  end
end
