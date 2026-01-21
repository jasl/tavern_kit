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
      # New GitLab-style API: return a structured `ServiceResponse`.
      def self.execute(conversation:, run:, error: nil)
        new(conversation, run, error).execute
      end

      def initialize(conversation, run, error)
        @conversation = conversation
        @space = conversation.space
        @run = run
        @error = error
      end

      # @return [ServiceResponse]
      def execute
        disabled_auto_memberships = []

        response =
          @conversation.with_lock do
            active_round = @conversation.conversation_rounds.find_by(status: "active")
            unless active_round
              next ::ServiceResponse.success(reason: :no_active_round, payload: { handled: false })
            end

            unless @run
              next ::ServiceResponse.error(message: "Missing run", reason: :missing_run, payload: { handled: false, round_id: active_round.id })
            end

            unless @run.debug&.dig("scheduled_by") == "turn_scheduler"
              next ::ServiceResponse.success(
                reason: :noop_not_scheduler_run,
                payload: { handled: false, round_id: active_round.id, run_id: @run.id }
              )
            end

            if current_speaker_id(active_round) != @run.speaker_space_membership_id
              next ::ServiceResponse.success(
                reason: :noop_not_current_speaker,
                payload: { handled: false, round_id: active_round.id, run_id: @run.id }
              )
            end

            run_round_id = @run.conversation_round_id
            if run_round_id.blank?
              next ::ServiceResponse.success(
                reason: :noop_missing_round_id,
                payload: { handled: false, round_id: active_round.id, run_id: @run.id }
              )
            end
            if active_round.id != run_round_id
              next ::ServiceResponse.success(
                reason: :noop_stale_round,
                payload: { handled: false, round_id: active_round.id, run_round_id: run_round_id, run_id: @run.id }
              )
            end

            cancel_queued_runs
            stop_automations!(disabled_auto_memberships)

            previous_scheduling_state = active_round.scheduling_state
            active_round.update!(scheduling_state: "failed")

            ConversationEvents::Emitter.emit(
              event_name: "turn_scheduler.round_failed",
              conversation: @conversation,
              space: @space,
              conversation_round_id: active_round.id,
              conversation_run_id: @run.id,
              trigger_message_id: active_round.trigger_message_id,
              speaker_space_membership_id: @run.speaker_space_membership_id,
              reason: "run_failed",
              payload: {
                previous_scheduling_state: previous_scheduling_state,
                run_error_code: (@run.error || {})["code"],
                error_class: @error&.class&.name,
                disabled_auto_memberships_count: disabled_auto_memberships.size,
              }
            )

            ::ServiceResponse.success(
              reason: :handled,
              payload: {
                handled: true,
                round_id: active_round.id,
                run_id: @run.id,
                disabled_auto_memberships_count: disabled_auto_memberships.size,
              }
            )
          end

        disabled_auto_memberships.each do |membership|
          Messages::Broadcasts.broadcast_auto_disabled(membership, reason: "turn_failed")
        end

        Broadcasts.queue_updated(@conversation) if response.payload[:handled]
        response
      end

      private

      def cancel_queued_runs
        @conversation.conversation_runs.queued.find_each do |queued|
          ConversationEvents::Emitter.emit(
            event_name: "conversation_run.canceled",
            conversation: @conversation,
            space: @space,
            conversation_round_id: queued.conversation_round_id,
            conversation_run_id: queued.id,
            trigger_message_id: queued.debug&.dig("trigger_message_id"),
            speaker_space_membership_id: queued.speaker_space_membership_id,
            reason: "handle_failure",
            payload: {
              canceled_by: "handle_failure",
              previous_status: queued.status,
            }
          )

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

      def current_speaker_id(active_round)
        position = active_round.current_position.to_i
        active_round.participants.find_by(position: position)&.space_membership_id
      end

      def stop_automations!(disabled_auto_memberships)
        @conversation.stop_auto_without_human! if @conversation.auto_without_human_enabled?

        now = Time.current
        @space.space_memberships.where(kind: "human").where.not(auto: "none").find_each do |membership|
          # Disable Auto without triggering SpaceMembership after_commit broadcasts.
          # HandleFailure is already the single source of truth for queue_updated here.
          membership.update_columns(auto: "none", auto_remaining_steps: nil, updated_at: now)
          disabled_auto_memberships << membership
        end
      end
    end
  end
end
