# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Retries the current speaker after a failed generation attempt.
    #
    # This keeps the existing round state (current_round_id/round_queue_ids/etc)
    # and only transitions scheduling_state from "failed" back to "ai_generating",
    # then enqueues a fresh run for the same speaker.
    #
    # @return [ConversationRun, nil] the created run, or nil if retry not possible
    class RetryCurrentSpeaker
      def self.call(conversation:, speaker_id:, expected_round_id: nil, reason: "retry_current_speaker")
        new(conversation, speaker_id, expected_round_id, reason).call
      end

      def initialize(conversation, speaker_id, expected_round_id, reason)
        @conversation = conversation
        @space = conversation.space
        @speaker_id = speaker_id
        @expected_round_id = expected_round_id
        @reason = reason
      end

      def call
        run = nil

        @conversation.with_lock do
          next nil unless @conversation.scheduling_state == "failed"
          next nil if @speaker_id.blank?
          next nil if @conversation.current_speaker_id != @speaker_id

          if @expected_round_id.present? && @conversation.current_round_id != @expected_round_id
            next nil
          end

          speaker = @space.space_memberships.find_by(id: @speaker_id)
          next nil unless speaker&.can_auto_respond?

          cancel_queued_runs
          @conversation.update!(scheduling_state: "ai_generating")

          run = ScheduleSpeaker.call(conversation: @conversation, speaker: speaker)
        end

        Broadcasts.queue_updated(@conversation) if run
        run
      end

      private

      def cancel_queued_runs
        @conversation.conversation_runs.queued.find_each do |queued|
          queued.update!(
            status: "canceled",
            finished_at: Time.current,
            debug: (queued.debug || {}).merge(
              "canceled_by" => @reason.to_s,
              "canceled_at" => Time.current.iso8601
            )
          )
        end
      end
    end
  end
end
