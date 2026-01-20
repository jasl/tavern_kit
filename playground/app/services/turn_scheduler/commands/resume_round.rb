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
      def self.call(conversation:, reason: "resume_round")
        new(conversation, reason).call
      end

      def initialize(conversation, reason)
        @conversation = conversation
        @space = conversation.space
        @reason = reason.to_s
      end

      # @return [Boolean] true if resumed (or there is nothing to resume)
      def call
        resumed =
          @conversation.with_lock do
            active_round = @conversation.conversation_rounds.find_by(status: "active")
            next false unless active_round
            next false unless active_round.scheduling_state == "paused"

            cancel_queued_run_for_round(active_round)

            # If any run is active, do not attempt to resume. This avoids
            # setting round state to ai_generating without actually scheduling.
            next false if ConversationRun.active.exists?(conversation_id: @conversation.id)

            result = schedule_next_speaker(active_round)
            next true if result == :scheduled
            next false if result == :blocked

            # No eligible speakers remain: finish this round and (optionally) start a new one.
            handle_round_complete(active_round)
          end

        Broadcasts.queue_updated(@conversation) if resumed
        resumed
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
        ConversationRun
          .where(id: run.id, status: "queued")
          .update_all(
            status: "canceled",
            finished_at: now,
            debug: debug,
            updated_at: now
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
            run = ScheduleSpeaker.call(
              conversation: @conversation,
              speaker: candidate,
              conversation_round: active_round,
              include_auto_without_human_delay: false
            )

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
        end
      end

      def mark_round_resumed(active_round, at:, idx:)
        meta = (active_round.metadata || {}).dup
        meta["resumed_at"] = at.iso8601
        meta["resumed_reason"] = @reason

        active_round.update!(
          scheduling_state: "ai_generating",
          current_position: idx,
          metadata: meta,
          updated_at: at
        )
      end

      def handle_round_complete(active_round)
        @conversation.decrement_auto_without_human_rounds! if @conversation.auto_without_human_enabled?

        finish_round(active_round, ended_reason: "round_complete")

        if auto_scheduling_enabled?
          started = StartRound.call(conversation: @conversation, is_user_input: false)
          return true if started
        end

        cancel_queued_runs
        true
      end

      def auto_scheduling_enabled?
        @conversation.auto_without_human_enabled? || any_auto_active?
      end

      def any_auto_active?
        @space.space_memberships.active.any? { |m| m.user? && m.auto_enabled? && m.can_auto_respond? }
      end

      def cancel_queued_runs
        @conversation.conversation_runs.queued.find_each do |run|
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

        active_round.update!(
          status: "finished",
          scheduling_state: nil,
          ended_reason: ended_reason.to_s,
          finished_at: Time.current
        )
      end
    end
  end
end
