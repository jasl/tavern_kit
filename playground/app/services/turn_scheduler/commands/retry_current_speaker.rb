# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Retries the current speaker after a failed generation attempt or a user stop.
    #
    # This keeps the existing round state (current_round_id/round_queue_ids/etc)
    # and only transitions scheduling_state back to "ai_generating",
    # then enqueues a fresh run for the same speaker.
    #
    # @return [ServiceResponse] payload includes:
    # - `run` [ConversationRun, nil]
    # - `retried` [Boolean]
    class RetryCurrentSpeaker
      def self.execute(conversation:, speaker_id:, expected_round_id: nil, reason: "retry_current_speaker")
        new(conversation, speaker_id, expected_round_id, reason).execute
      end

      def initialize(conversation, speaker_id, expected_round_id, reason)
        @conversation = conversation
        @space = conversation.space
        @speaker_id = speaker_id
        @expected_round_id = expected_round_id
        @reason = reason
      end

      def execute
        run = nil
        retried = false

        @conversation.with_lock do
          active_round = @conversation.conversation_rounds.find_by(status: "active")
          next nil unless active_round&.scheduling_state.in?(%w[failed paused])
          next nil if @speaker_id.blank?
          next nil if current_speaker_id(active_round) != @speaker_id

          if @expected_round_id.present? && active_round.id != @expected_round_id
            next nil
          end

          speaker = @space.space_memberships.find_by(id: @speaker_id)
          next nil unless speaker&.can_auto_respond?

          cancel_queued_runs
          active_round.update!(scheduling_state: "ai_generating")

          response =
            ScheduleSpeaker.execute(
              conversation: @conversation,
              speaker: speaker,
              conversation_round: active_round,
              include_auto_without_human_delay: false
            )
          run = response.payload[:run]
          retried = run.present?
        end

        Broadcasts.queue_updated(@conversation) if run

        ::ServiceResponse.success(
          reason: retried ? :retried : :not_retried,
          payload: { retried: retried, run: run }
        )
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

      def current_speaker_id(active_round)
        position = active_round.current_position.to_i
        active_round.participants.find_by(position: position)&.space_membership_id
      end
    end
  end
end
