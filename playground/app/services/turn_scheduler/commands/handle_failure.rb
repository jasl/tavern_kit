# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Marks the current round as failed (without clearing round state).
    #
    # This is used for "unexpected/exception" failures (LLM/provider/network/etc).
    # It pauses the scheduler so a human can decide what to do (Retry/Stop/Skip).
    #
    # Note: UI error surfaces are handled by RunExecutor (run_failed toast) and
    # RunFollowups (run_error_alert). This command only mutates scheduling state
    # and emits a queue update broadcast.
    class HandleFailure
      def self.call(conversation:, run:, error: nil)
        new(conversation, run, error).call
      end

      def initialize(conversation, run, error)
        @conversation = conversation
        @run = run
        @error = error
      end

      # @return [Boolean] true if handled successfully
      def call
        handled = false

        @conversation.with_lock do
          next false if @conversation.scheduling_state == "idle"
          next false unless @run
          next false unless @run.debug&.dig("scheduled_by") == "turn_scheduler"
          next false if @conversation.current_speaker_id != @run.speaker_space_membership_id

          run_round_id = @run.debug&.dig("round_id")
          if run_round_id.present? && @conversation.current_round_id != run_round_id
            next false
          end

          cancel_queued_runs
          @conversation.update!(scheduling_state: "failed")
          handled = true
        end

        Broadcasts.queue_updated(@conversation) if handled
        handled
      end

      private

      def cancel_queued_runs
        @conversation.conversation_runs.queued.find_each do |queued|
          queued.update!(
            status: "canceled",
            finished_at: Time.current,
            debug: (queued.debug || {}).merge(
              "canceled_by" => "handle_failure",
              "canceled_at" => Time.current.iso8601
            )
          )
        end
      end
    end
  end
end
