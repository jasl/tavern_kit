# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Skips the current speaker without requiring a Message to be created.
    #
    # This is used for "environment-driven" changes that should auto-advance the round:
    # - Current speaker was removed or muted
    # - Current speaker is no longer auto-respondable (e.g., Copilot disabled)
    # - A queued run was skipped before execution (speaker missing / no longer eligible)
    #
    # Important: This does NOT increment turns_count or decrement resources,
    # because no actual message was produced.
    class SkipCurrentSpeaker
      def self.call(conversation:, speaker_id:, reason:, expected_round_id: nil, cancel_running: false)
        new(conversation, speaker_id, reason, expected_round_id, cancel_running).call
      end

      def initialize(conversation, speaker_id, reason, expected_round_id, cancel_running)
        @conversation = conversation
        @space = conversation.space
        @speaker_id = speaker_id
        @reason = reason
        @expected_round_id = expected_round_id
        @cancel_running = cancel_running
      end

      # @return [Boolean] true if the scheduler state was advanced
      def call
        advanced = false

        @conversation.with_lock do
          active_round = @conversation.conversation_rounds.find_by(status: "active")
          next false unless active_round
          next false if @speaker_id.blank?
          next false if current_speaker_id(active_round) != @speaker_id

          if @expected_round_id.present? && active_round.id != @expected_round_id
            next false
          end

          cancel_queued_run_for_current_speaker

          if running_run_for_current_speaker
            if @cancel_running
              request_cancel_running_run
            else
              # Avoid advancing the scheduling state while a run is still actively generating,
              # unless the caller explicitly opted into cancel_running.
              next false
            end
          end

          mark_participant_skipped(active_round, membership_id: @speaker_id, reason: @reason)

          if round_complete?(active_round)
            handle_round_complete(active_round)
          else
            advance_to_next_speaker(active_round)
          end

          advanced = true
        end

        Broadcasts.queue_updated(@conversation) if advanced
        advanced
      end

      private

      def cancel_queued_run_for_current_speaker
        run = ConversationRun.queued.find_by(conversation_id: @conversation.id, speaker_space_membership_id: @speaker_id)
        return unless run

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
        @conversation.decrement_auto_mode_rounds! if @conversation.auto_mode_enabled?

        finish_round(active_round, ended_reason: "round_complete")

        if auto_scheduling_enabled?
          started = StartRound.call(conversation: @conversation, is_user_input: false)
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
          membership_id = participants[idx].space_membership_id
          candidate = @space.space_memberships.find_by(id: membership_id)
          if candidate&.can_be_scheduled?
            active_round.update!(
              scheduling_state: determine_state_for(candidate),
              current_position: idx
            )
            ScheduleSpeaker.call(conversation: @conversation, speaker: candidate, conversation_round: active_round)
            return
          end

          mark_participant_skipped(active_round, membership_id: membership_id, reason: "not_schedulable")
          idx += 1
        end

        handle_round_complete(active_round)
      end

      def reset_to_idle
        cancel_queued_runs
      end

      def cancel_queued_runs
        @conversation.conversation_runs.queued.find_each do |run|
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
        @conversation.auto_mode_enabled? || any_copilot_active?
      end

      def any_copilot_active?
        @space.space_memberships.active.any? { |m| m.copilot_full? && m.can_auto_respond? }
      end

      def determine_state_for(speaker)
        return "idle" unless speaker

        "ai_generating"
      end

      def mark_participant_skipped(active_round, membership_id:, reason:)
        return unless active_round

        participant = active_round.participants.find_by(space_membership_id: membership_id)
        return unless participant
        return if participant.skipped? || participant.spoken?

        participant.update!(status: "skipped", skipped_at: Time.current, skip_reason: reason.to_s)
      end

      def finish_round(active_round, ended_reason:)
        return unless active_round

        active_round.update!(
          status: "finished",
          scheduling_state: nil,
          ended_reason: ended_reason,
          finished_at: Time.current
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
