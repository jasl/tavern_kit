# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Resumes a paused active round (preserving speaker order).
    #
    # This schedules the current speaker's run again using the persisted round
    # + participant queue.
    #
    # If the current speaker is no longer schedulable (muted/removed/Auto disabled),
    # this will skip forward until a schedulable participant is found.
    class ResumeRound
      # New GitLab-style API: return a structured `ServiceResponse`.
      def self.execute(conversation:, reason: "resume_round")
        new(conversation, reason).execute
      end

      def initialize(conversation, reason)
        @conversation = conversation
        @space = conversation.space
        @reason = reason.to_s
      end

      # @return [ServiceResponse]
      def execute
        response =
          @conversation.with_lock do
            active_round = @conversation.conversation_rounds.find_by(status: "active")
            unless active_round
              next ::ServiceResponse.success(reason: :no_active_round, payload: { resumed: false })
            end
            unless active_round.scheduling_state == "paused"
              next ::ServiceResponse.success(reason: :noop_not_paused, payload: { resumed: false, round_id: active_round.id })
            end

            cancel_queued_run_for_round(active_round)

            # If any run is active, do not attempt to resume. This avoids
            # setting round state to ai_generating without actually scheduling.
            if ConversationRun.active.exists?(conversation_id: @conversation.id)
              next ::ServiceResponse.success(reason: :blocked_active_run, payload: { resumed: false, round_id: active_round.id })
            end

            result = schedule_next_speaker(active_round)
            if result == :scheduled
              next ::ServiceResponse.success(reason: :resumed, payload: { resumed: true, round_id: active_round.id })
            end
            if result == :blocked
              next ::ServiceResponse.success(reason: :blocked_queue_slot, payload: { resumed: false, round_id: active_round.id })
            end

            # No eligible speakers remain: finish this round and (optionally) start a new one.
            started_new_round = handle_round_complete(active_round)
            ::ServiceResponse.success(
              reason: :round_complete,
              payload: {
                resumed: true,
                round_id: active_round.id,
                started_new_round: started_new_round,
              }
            )
          end

        Broadcasts.queue_updated(@conversation) if response.payload[:resumed]
        response
      end

      private

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

      # @return [Symbol] :scheduled, :no_eligible_speakers, :blocked
      def schedule_next_speaker(active_round)
        participants = active_round.participants.order(:position).to_a
        idx = active_round.current_position.to_i

        now = Time.current
        unschedulable = []

        while idx < participants.length
          participant = participants[idx]
          membership_id = participant.space_membership_id

          # If our pointer drifted (shouldn't happen), advance to the next pending entry.
          if participant.spoken? || participant.skipped?
            idx += 1
            next
          end

          candidate = @space.space_memberships.find_by(id: membership_id)
          if candidate&.can_be_scheduled?
            response =
              ScheduleSpeaker.execute(
                conversation: @conversation,
                speaker: candidate,
                conversation_round: active_round,
                include_auto_without_human_delay: false
              )
            run = response.payload[:run]

            # If we couldn't schedule (e.g., queued slot taken), keep paused.
            return :blocked unless run

            mark_round_resumed(active_round, at: now, idx: idx)
            mark_participants_skipped!(unschedulable, at: now)
            return :scheduled
          end

          unschedulable << participant
          idx += 1
        end

        mark_participants_skipped!(unschedulable, at: now)
        :no_eligible_speakers
      end

      def mark_participants_skipped!(participants, at:)
        participants.each do |participant|
          next if participant.spoken? || participant.skipped?

          participant.update!(
            status: "skipped",
            skipped_at: at,
            skip_reason: "not_schedulable"
          )

          ConversationEvents::Emitter.emit(
            event_name: "turn_scheduler.participant_skipped",
            conversation: @conversation,
            space: @space,
            conversation_round_id: participant.conversation_round_id,
            speaker_space_membership_id: participant.space_membership_id,
            reason: "not_schedulable",
            payload: {
              position: participant.position,
            }
          )
        end
      end

      def mark_round_resumed(active_round, at:, idx:)
        meta = (active_round.metadata || {}).dup
        meta["resumed_at"] = at.iso8601
        meta["resumed_reason"] = @reason

        previous_scheduling_state = active_round.scheduling_state

        active_round.update!(
          scheduling_state: "ai_generating",
          current_position: idx,
          metadata: meta,
          updated_at: at
        )

        ConversationEvents::Emitter.emit(
          event_name: "turn_scheduler.round_resumed",
          conversation: @conversation,
          space: @space,
          conversation_round_id: active_round.id,
          trigger_message_id: active_round.trigger_message_id,
          reason: @reason,
          payload: {
            previous_scheduling_state: previous_scheduling_state,
            current_position: idx,
          }
        )
      end

      def handle_round_complete(active_round)
        @conversation.decrement_auto_without_human_rounds! if @conversation.auto_without_human_enabled?

        finish_round(active_round, ended_reason: "round_complete")

        if auto_scheduling_enabled?
          started = StartRound.execute(conversation: @conversation, is_user_input: false).payload[:started]
          return true if started
        end

        cancel_queued_runs
        true
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
            reason: "resume_round_round_complete",
            payload: {
              canceled_by: "resume_round_round_complete",
              previous_status: run.status,
            }
          )

          run.update!(
            status: "canceled",
            finished_at: Time.current,
            debug: (run.debug || {}).merge(
              "canceled_by" => "resume_round_round_complete",
              "canceled_at" => Time.current.iso8601
            )
          )
        end
      end

      def finish_round(active_round, ended_reason:)
        return unless active_round

        previous_scheduling_state = active_round.scheduling_state

        active_round.update!(
          status: "finished",
          scheduling_state: nil,
          ended_reason: ended_reason.to_s,
          finished_at: Time.current
        )

        ConversationEvents::Emitter.emit(
          event_name: "turn_scheduler.round_finished",
          conversation: @conversation,
          space: @space,
          conversation_round_id: active_round.id,
          trigger_message_id: active_round.trigger_message_id,
          reason: ended_reason.to_s,
          payload: {
            previous_scheduling_state: previous_scheduling_state,
          }
        )
      end
    end
  end
end
