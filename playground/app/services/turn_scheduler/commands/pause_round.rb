# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Pauses the active scheduling round without ending it.
    #
    # This is a stronger form of "stop": it cancels any queued run for the active
    # round but keeps the persisted round + participant queue intact so it can be
    # resumed later (preserving speaker order).
    #
    # Notes:
    # - This is intended for "between turns" pauses (e.g., auto_without_human_delay_ms window),
    #   but can optionally request cancellation of an in-flight run for robustness.
    # - Paused rounds must not be auto-advanced until ResumeRound is called.
    class PauseRound
      def self.call(conversation:, reason: "pause_round", cancel_running: false)
        new(conversation, reason, cancel_running).call
      end

      def initialize(conversation, reason, cancel_running)
        @conversation = conversation
        @space = conversation.space
        @reason = reason.to_s
        @cancel_running = cancel_running
      end

      # @return [Boolean] true if the round is paused (or was already paused)
      def call
        paused =
          @conversation.with_lock do
            active_round = @conversation.conversation_rounds.find_by(status: "active")
            next false unless active_round

            # Failed rounds are explicitly recovered via Retry/Stop/Skip (don't add another mode).
            next false if active_round.scheduling_state == "failed"

            next true if active_round.scheduling_state == "paused"

            mark_round_paused(active_round)

            cancel_queued_run_for_round(active_round)
            request_cancel_running_run_for_round(active_round) if @cancel_running

            true
          end

        Broadcasts.queue_updated(@conversation) if paused
        paused
      end

      private

      def mark_round_paused(active_round)
        now = Time.current
        meta = (active_round.metadata || {}).dup
        meta["paused_at"] = now.iso8601
        meta["paused_reason"] = @reason

        active_round.update!(
          scheduling_state: "paused",
          metadata: meta,
          updated_at: now
        )
      end

      def cancel_queued_run_for_round(active_round)
        run =
          ConversationRun.find_by(
            conversation_id: @conversation.id,
            conversation_round_id: active_round.id,
            status: "queued"
          )
        return unless run

        now = Time.current

        debug = (run.debug || {}).merge(
          "canceled_by" => @reason.to_s,
          "canceled_at" => now.iso8601
        )

        # Guard against races with RunClaimer (queued → running).
        ConversationRun
          .where(id: run.id, status: "queued")
          .update_all(
            status: "canceled",
            finished_at: now,
            debug: debug,
            updated_at: now
          )
      end

      def request_cancel_running_run_for_round(active_round)
        run = ConversationRun.running.find_by(conversation_id: @conversation.id, conversation_round_id: active_round.id)
        return unless run

        now = Time.current
        run.request_cancel!(at: now)

        # Immediate UX feedback (same pattern as ConversationsController#stop).
        ConversationChannel.broadcast_stream_complete(@conversation, space_membership_id: run.speaker_space_membership_id)

        membership = @space.space_memberships.find_by(id: run.speaker_space_membership_id)
        ConversationChannel.broadcast_typing(@conversation, membership: membership, active: false) if membership
      end
    end
  end
end
