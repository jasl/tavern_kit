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
    # IMPORTANT: Uses persisted round_queue_ids to avoid recalculating queue
    # mid-round, which could cause ordering issues if members change.
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
        # Use with_lock for concurrency safety (consistent with AdvanceTurn)
        @conversation.with_lock do
          perform_skip
        end
      end

      private

      def perform_skip
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

        # Use persisted queue - don't recalculate
        queue_ids = @conversation.round_queue_ids || []
        new_position = @conversation.round_position + 1

        if new_position >= queue_ids.size
          handle_round_complete
        else
          advance_to_next_speaker(queue_ids, new_position)
        end

        Broadcasts.queue_updated(@conversation)
        true
      end

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

      def advance_to_next_speaker(queue_ids, new_position)
        # Find next speaker from persisted queue
        next_speaker_id = queue_ids[new_position]
        next_speaker = next_speaker_id ? @space.space_memberships.find_by(id: next_speaker_id) : nil

        # Skip to next if this speaker can no longer auto-respond
        while next_speaker && !next_speaker.can_auto_respond? && new_position < queue_ids.size - 1
          new_position += 1
          next_speaker_id = queue_ids[new_position]
          next_speaker = next_speaker_id ? @space.space_memberships.find_by(id: next_speaker_id) : nil
        end

        # If we've exhausted the queue or no valid speaker found, complete the round
        if next_speaker.nil? || !next_speaker.can_auto_respond?
          handle_round_complete
          return
        end

        @conversation.update!(
          scheduling_state: determine_state_for(next_speaker),
          current_speaker_id: next_speaker.id,
          round_position: new_position
        )

        ScheduleSpeaker.call(conversation: @conversation, speaker: next_speaker)
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
      end

      def auto_scheduling_enabled?
        @conversation.auto_mode_enabled? || any_copilot_active?
      end

      def any_copilot_active?
        @space.space_memberships.active.any? { |m| m.copilot_full? && m.can_auto_respond? }
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
