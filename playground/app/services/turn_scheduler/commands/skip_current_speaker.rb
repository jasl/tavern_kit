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
          next false if @conversation.scheduling_state == "idle"
          next false if @speaker_id.blank?
          next false if @conversation.current_speaker_id != @speaker_id

          if @expected_round_id.present? && @conversation.current_round_id != @expected_round_id
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

          if round_complete?
            handle_round_complete
          else
            advance_to_next_speaker
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

      def round_complete?
        ids = @conversation.round_queue_ids || []
        position = @conversation.round_position.to_i
        position + 1 >= ids.size
      end

      def handle_round_complete
        @conversation.decrement_auto_mode_rounds! if @conversation.auto_mode_enabled?

        if auto_scheduling_enabled?
          StartRound.call(conversation: @conversation, is_user_input: false)
        else
          reset_to_idle
        end
      end

      def advance_to_next_speaker
        ids = @conversation.round_queue_ids || []
        idx = @conversation.round_position.to_i + 1

        while idx < ids.length
          candidate = @space.space_memberships.find_by(id: ids[idx])
          if candidate&.can_be_scheduled?
            @conversation.update!(
              scheduling_state: determine_state_for(candidate),
              current_speaker_id: candidate.id,
              round_position: idx
            )
            ScheduleSpeaker.call(conversation: @conversation, speaker: candidate)
            return
          end

          idx += 1
        end

        handle_round_complete
      end

      def reset_to_idle
        @conversation.update!(
          scheduling_state: "idle",
          current_round_id: nil,
          current_speaker_id: nil,
          round_position: 0,
          round_spoken_ids: [],
          round_queue_ids: []
        )

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

        speaker.can_auto_respond? ? "ai_generating" : "waiting_for_speaker"
      end
    end
  end
end
