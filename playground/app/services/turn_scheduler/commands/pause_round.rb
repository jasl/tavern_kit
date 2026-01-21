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
      # New GitLab-style API: return a structured `ServiceResponse`.
      def self.execute(conversation:, reason: "pause_round", cancel_running: false)
        new(conversation, reason, cancel_running).execute
      end

      def initialize(conversation, reason, cancel_running)
        @conversation = conversation
        @space = conversation.space
        @reason = reason.to_s
        @cancel_running = cancel_running
      end

      # @return [ServiceResponse]
      def execute
        response =
          @conversation.with_lock do
            active_round = @conversation.conversation_rounds.find_by(status: "active")
            unless active_round
              next ::ServiceResponse.success(reason: :no_active_round, payload: { paused: false })
            end

            # Failed rounds are explicitly recovered via Retry/Stop/Skip (don't add another mode).
            if active_round.scheduling_state == "failed"
              next ::ServiceResponse.success(
                reason: :noop_failed_round,
                payload: { paused: false, round_id: active_round.id }
              )
            end

            if active_round.scheduling_state == "paused"
              next ::ServiceResponse.success(
                reason: :already_paused,
                payload: { paused: true, round_id: active_round.id }
              )
            end

            mark_round_paused(active_round)

            cancel_queued_run_for_round(active_round)
            request_cancel_running_run_for_round(active_round) if @cancel_running

            ::ServiceResponse.success(
              reason: :paused,
              payload: { paused: true, round_id: active_round.id }
            )
          end

        Broadcasts.queue_updated(@conversation) if response.payload[:paused]
        response
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

        ConversationEvents::Emitter.emit(
          event_name: "turn_scheduler.round_paused",
          conversation: @conversation,
          space: @space,
          conversation_round_id: active_round.id,
          trigger_message_id: active_round.trigger_message_id,
          reason: @reason,
          payload: {
            previous_scheduling_state: "ai_generating",
          }
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
        canceled =
          ConversationRun
          .where(id: run.id, status: "queued")
          .update_all(
            status: "canceled",
            finished_at: now,
            debug: debug,
            updated_at: now
          )

        return if canceled == 0

        ConversationEvents::Emitter.emit(
          event_name: "conversation_run.canceled",
          conversation: @conversation,
          space: @space,
          conversation_round_id: active_round.id,
          conversation_run_id: run.id,
          trigger_message_id: run.debug["trigger_message_id"],
          speaker_space_membership_id: run.speaker_space_membership_id,
          reason: @reason,
          payload: {
            canceled_by: @reason,
            previous_status: "queued",
          }
        )
      end

      def request_cancel_running_run_for_round(active_round)
        run = ConversationRun.running.find_by(conversation_id: @conversation.id, conversation_round_id: active_round.id)
        return unless run

        now = Time.current
        run.request_cancel!(at: now)

        ConversationEvents::Emitter.emit(
          event_name: "conversation_run.cancel_requested",
          conversation: @conversation,
          space: @space,
          conversation_round_id: active_round.id,
          conversation_run_id: run.id,
          trigger_message_id: run.debug["trigger_message_id"],
          speaker_space_membership_id: run.speaker_space_membership_id,
          reason: @reason,
          payload: {
            previous_status: "running",
          }
        )

        # Immediate UX feedback (same pattern as ConversationsController#stop).
        ConversationChannel.broadcast_stream_complete(@conversation, space_membership_id: run.speaker_space_membership_id)

        membership = @space.space_memberships.find_by(id: run.speaker_space_membership_id)
        ConversationChannel.broadcast_typing(@conversation, membership: membership, active: false) if membership
      end
    end
  end
end
