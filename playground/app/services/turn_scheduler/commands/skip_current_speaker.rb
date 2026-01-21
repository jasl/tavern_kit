# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Skips the current speaker without requiring a Message to be created.
    #
    # This is used for "environment-driven" changes that should auto-advance the round:
    # - Current speaker was removed or muted
    # - Current speaker is no longer auto-respondable (e.g., Auto disabled)
    # - A queued run was skipped before execution (speaker missing / no longer eligible)
    #
    # Important: This does NOT increment turns_count or decrement resources,
    # because no actual message was produced.
    class SkipCurrentSpeaker
      # New GitLab-style API: return a structured `ServiceResponse`.
      def self.execute(conversation:, speaker_id:, reason:, expected_round_id: nil, cancel_running: false)
        new(conversation, speaker_id, reason, expected_round_id, cancel_running).execute
      end

      def initialize(conversation, speaker_id, reason, expected_round_id, cancel_running)
        @conversation = conversation
        @space = conversation.space
        @speaker_id = speaker_id
        @reason = reason
        @expected_round_id = expected_round_id
        @cancel_running = cancel_running
      end

      # @return [ServiceResponse]
      def execute
        response =
          @conversation.with_lock do
            active_round = @conversation.conversation_rounds.find_by(status: "active")
            unless active_round
              next ::ServiceResponse.success(reason: :no_active_round, payload: { advanced: false })
            end
            if @speaker_id.blank?
              next ::ServiceResponse.success(reason: :missing_speaker_id, payload: { advanced: false, round_id: active_round.id })
            end

            if current_speaker_id(active_round) != @speaker_id
              next ::ServiceResponse.success(
                reason: :noop_not_current_speaker,
                payload: {
                  advanced: false,
                  round_id: active_round.id,
                  expected_speaker_id: @speaker_id,
                  current_speaker_id: current_speaker_id(active_round),
                }
              )
            end

            if @expected_round_id.present? && active_round.id != @expected_round_id
              next ::ServiceResponse.success(
                reason: :stale_round,
                payload: { advanced: false, round_id: active_round.id, expected_round_id: @expected_round_id }
              )
            end

            cancel_queued_run_for_current_speaker

            if running_run_for_current_speaker
              if @cancel_running
                request_cancel_running_run
              else
                # Avoid advancing the scheduling state while a run is still actively generating,
                # unless the caller explicitly opted into cancel_running.
                next ::ServiceResponse.success(reason: :blocked_running_run, payload: { advanced: false, round_id: active_round.id })
              end
            end

            current_participant = ordered_participants(active_round)[active_round.current_position.to_i]
            mark_participant_skipped(current_participant, reason: @reason)

            if round_complete?(active_round)
              handle_round_complete(active_round)
            else
              advance_to_next_speaker(active_round)
            end

            ::ServiceResponse.success(
              reason: :advanced,
              payload: { advanced: true, round_id: active_round.id, speaker_id: @speaker_id }
            )
          end

        Broadcasts.queue_updated(@conversation) if response.payload[:advanced]
        response
      end

      private

      def cancel_queued_run_for_current_speaker
        run = ConversationRun.queued.find_by(conversation_id: @conversation.id, speaker_space_membership_id: @speaker_id)
        return unless run

        ConversationEvents::Emitter.emit(
          event_name: "conversation_run.canceled",
          conversation: @conversation,
          space: @space,
          conversation_round_id: run.conversation_round_id,
          conversation_run_id: run.id,
          trigger_message_id: run.debug&.dig("trigger_message_id"),
          speaker_space_membership_id: run.speaker_space_membership_id,
          reason: @reason.to_s,
          payload: {
            canceled_by: @reason.to_s,
            previous_status: run.status,
          }
        )

        run.update!(
          status: "canceled",
          finished_at: Time.current,
          debug: (run.debug || {}).merge(
            "canceled_by" => @reason.to_s,
            "canceled_at" => Time.current.iso8601
          )
        )
      end

      def running_run_for_current_speaker
        @running_run_for_current_speaker ||= ConversationRun.running.find_by(
          conversation_id: @conversation.id,
          speaker_space_membership_id: @speaker_id
        )
      end

      def request_cancel_running_run
        run = running_run_for_current_speaker
        return unless run

        run.request_cancel!

        ConversationEvents::Emitter.emit(
          event_name: "conversation_run.cancel_requested",
          conversation: @conversation,
          space: @space,
          conversation_round_id: run.conversation_round_id,
          conversation_run_id: run.id,
          trigger_message_id: run.debug&.dig("trigger_message_id"),
          speaker_space_membership_id: run.speaker_space_membership_id,
          reason: @reason.to_s,
          payload: {
            previous_status: run.status,
          }
        )

        # Immediately clear typing indicator (same UX as ConversationsController#stop).
        ConversationChannel.broadcast_stream_complete(@conversation, space_membership_id: @speaker_id)

        membership = @space.space_memberships.find_by(id: @speaker_id)
        ConversationChannel.broadcast_typing(@conversation, membership: membership, active: false) if membership
      end

      def round_complete?(active_round)
        return true unless active_round

        position = active_round.current_position.to_i
        position + 1 >= ordered_participants(active_round).size
      end

      def handle_round_complete(active_round)
        @conversation.decrement_auto_without_human_rounds! if @conversation.auto_without_human_enabled?

        finish_round(active_round, ended_reason: "round_complete")

        if auto_scheduling_enabled?
          started = StartRound.execute(conversation: @conversation, is_user_input: false).payload[:started]
          reset_to_idle unless started
        else
          reset_to_idle
        end
      end

      def advance_to_next_speaker(active_round)
        return handle_round_complete(active_round) unless active_round

        participants = ordered_participants(active_round)
        idx = active_round.current_position.to_i + 1

        while idx < participants.length
          participant = participants[idx]
          membership_id = participant.space_membership_id
          candidate = @space.space_memberships.find_by(id: membership_id)
          if candidate&.can_be_scheduled?
            active_round.update!(
              scheduling_state: determine_state_for(candidate),
              current_position: idx
            )
            ScheduleSpeaker.execute(conversation: @conversation, speaker: candidate, conversation_round: active_round)
            return
          end

          mark_participant_skipped(participant, reason: "not_schedulable")
          idx += 1
        end

        handle_round_complete(active_round)
      end

      def reset_to_idle
        cancel_queued_runs
      end

      def cancel_queued_runs
        @conversation.conversation_runs.queued.find_each do |run|
          ConversationEvents::Emitter.emit(
            event_name: "conversation_run.canceled",
            conversation: @conversation,
            space: @space,
            conversation_round_id: run.conversation_round_id,
            conversation_run_id: run.id,
            trigger_message_id: run.debug&.dig("trigger_message_id"),
            speaker_space_membership_id: run.speaker_space_membership_id,
            reason: "skip_current_speaker_round_complete",
            payload: {
              canceled_by: "skip_current_speaker_round_complete",
              previous_status: run.status,
            }
          )

          run.update!(
            status: "canceled",
            finished_at: Time.current,
            debug: (run.debug || {}).merge(
              "canceled_by" => "skip_current_speaker_round_complete",
              "canceled_at" => Time.current.iso8601
            )
          )
        end
      end

      def auto_scheduling_enabled?
        @conversation.auto_without_human_enabled? || any_auto_active?
      end

      def any_auto_active?
        @space.space_memberships
          .active
          .where(kind: "human", auto: "auto")
          .where("auto_remaining_steps > 0")
          .exists?
      end

      def determine_state_for(speaker)
        return "idle" unless speaker

        "ai_generating"
      end

      def mark_participant_skipped(participant, reason:)
        return unless participant
        return if participant.skipped? || participant.spoken?

        participant.update!(status: "skipped", skipped_at: Time.current, skip_reason: reason.to_s)

        ConversationEvents::Emitter.emit(
          event_name: "turn_scheduler.participant_skipped",
          conversation: @conversation,
          space: @space,
          conversation_round_id: participant.conversation_round_id,
          speaker_space_membership_id: participant.space_membership_id,
          reason: reason.to_s,
          payload: {
            position: participant.position,
          }
        )
      end

      def finish_round(active_round, ended_reason:)
        return unless active_round

        previous_scheduling_state = active_round.scheduling_state

        active_round.update!(
          status: "finished",
          scheduling_state: nil,
          ended_reason: ended_reason,
          finished_at: Time.current
        )

        ConversationEvents::Emitter.emit(
          event_name: "turn_scheduler.round_finished",
          conversation: @conversation,
          space: @space,
          conversation_round_id: active_round.id,
          trigger_message_id: active_round.trigger_message_id,
          reason: ended_reason,
          payload: {
            previous_scheduling_state: previous_scheduling_state,
          }
        )
      end

      def ordered_participants(active_round)
        return [] unless active_round

        @ordered_participants ||= active_round.participants.order(:position).to_a
      end

      def current_speaker_id(active_round)
        ordered_participants(active_round)[active_round.current_position.to_i]&.space_membership_id
      end
    end
  end
end
