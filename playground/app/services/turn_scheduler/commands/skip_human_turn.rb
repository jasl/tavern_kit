# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Skips a human speaker's turn if eligible.
    #
    # Used by HumanTurnTimeoutJob to skip unresponsive humans in auto mode.
    #
    # Only skips if:
    # - Still in the same round (round_id matches)
    # - Human hasn't spoken yet
    # - Auto mode is still active
    #
    class SkipHumanTurn
      def self.call(conversation:, membership_id:, round_id:)
        new(conversation, membership_id, round_id).call
      end

      def initialize(conversation, membership_id, round_id)
        @conversation = conversation
        @space = conversation.space
        @membership_id = membership_id
        @round_id = round_id
      end

      # @return [Boolean] true if skipped, false otherwise
      def call
        state = State::RoundState.new(@conversation)

        # Validate preconditions
        return false if state.idle?
        return false if @conversation.current_round_id != @round_id
        return false unless @conversation.auto_mode_enabled?
        return false if state.has_spoken?(@membership_id)
        return false if @conversation.current_speaker_id != @membership_id

        Rails.logger.info "[TurnScheduler] Skipping human #{@membership_id} due to timeout"

        # Mark the HumanTurn run as skipped
        mark_run_as_skipped

        # Advance to next speaker
        queue = build_ordered_queue
        new_position = @conversation.round_position + 1

        if new_position >= queue.size
          handle_round_complete
        else
          advance_to_next_speaker(queue, new_position)
        end

        Broadcasts.queue_updated(@conversation)
        true
      end

      private

      def mark_run_as_skipped
        run = ConversationRun
          .where(conversation: @conversation, speaker_space_membership_id: @membership_id, kind: "human_turn")
          .queued
          .first

        run&.update!(
          status: "skipped",
          finished_at: Time.current,
          debug: run.debug.merge(
            "skipped_reason" => "timeout",
            "skipped_at" => Time.current.iso8601
          )
        )
      end

      def handle_round_complete
        @conversation.decrement_auto_mode_rounds! if @conversation.auto_mode_enabled?

        if auto_scheduling_enabled?
          StartRound.call(conversation: @conversation)
        else
          reset_to_idle
        end
      end

      def advance_to_next_speaker(queue, new_position)
        next_speaker = queue[new_position]

        @conversation.update!(
          scheduling_state: determine_state_for(next_speaker),
          current_speaker_id: next_speaker&.id,
          round_position: new_position
        )

        ScheduleSpeaker.call(conversation: @conversation, speaker: next_speaker) if next_speaker
      end

      def reset_to_idle
        @conversation.update!(
          scheduling_state: "idle",
          current_round_id: nil,
          current_speaker_id: nil,
          round_position: 0,
          round_spoken_ids: []
        )
      end

      def auto_scheduling_enabled?
        @conversation.auto_mode_enabled? || any_copilot_active?
      end

      def any_copilot_active?
        @space.space_memberships.active.any? { |m| m.copilot_full? && m.can_auto_respond? }
      end

      def build_ordered_queue
        participants = @space.space_memberships.participating.includes(:character).to_a
        participants.sort_by { |m| [-m.talkativeness_factor.to_f, m.position] }
      end

      def determine_state_for(speaker)
        return "idle" unless speaker

        if speaker.can_auto_respond?
          "ai_generating"
        elsif @conversation.auto_mode_enabled?
          "human_waiting"
        else
          "waiting_for_speaker"
        end
      end
    end
  end
end
