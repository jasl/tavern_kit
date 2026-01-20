# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Removes a pending participant slot from the active round queue.
    #
    # Rules:
    # - Only pending participants can be removed.
    # - Only participants in the "editable" portion can be removed:
    #   - paused: editable starts at current_position
    #   - ai_generating: editable starts at current_position + 1
    #
    # @return [Boolean] true if removed
    class RemovePendingParticipant
      def self.call(conversation:, participant_id:, expected_round_id: nil, reason: "remove_pending_participant")
        new(conversation, participant_id, expected_round_id, reason).call
      end

      def initialize(conversation, participant_id, expected_round_id, reason)
        @conversation = conversation
        @space = conversation.space
        @participant_id = participant_id
        @expected_round_id = expected_round_id
        @reason = reason.to_s
      end

      def call
        removed = false

        @conversation.with_lock do
          active_round = @conversation.conversation_rounds.find_by(status: "active")
          next false unless active_round

          if @expected_round_id.present? && active_round.id != @expected_round_id.to_s
            next false
          end

          participant = active_round.participants.find_by(id: @participant_id)
          next false unless participant
          next false unless participant.pending?

          editable_from = editable_from(active_round)
          next false if participant.position.to_i < editable_from

          removed_pos = participant.position.to_i
          participant.destroy!

          # Shift down in a single SQL statement.
          # This is safe with unique (round_id, position) because all positions shift by -1.
          now = Time.current
          active_round.participants
            .where("position > ?", removed_pos)
            .update_all(["position = position - 1, updated_at = ?", now])

          finish_round_if_empty!(active_round)
          removed = true
        end

        Broadcasts.queue_updated(@conversation) if removed
        removed
      end

      private

      def editable_from(active_round)
        current = active_round.current_position.to_i
        paused = active_round.scheduling_state == "paused"
        current + (paused ? 0 : 1)
      end

      def finish_round_if_empty!(active_round)
        count = active_round.participants.count
        return if count.positive? && active_round.current_position.to_i < count

        now = Time.current

        cancel_queued_run_for_round(active_round, now: now)

        active_round.update!(
          status: "finished",
          scheduling_state: nil,
          ended_reason: "round_queue_emptied",
          finished_at: now,
          updated_at: now
        )
      end

      def cancel_queued_run_for_round(active_round, now:)
        run = ConversationRun.queued.find_by(conversation_id: @conversation.id, conversation_round_id: active_round.id)
        return unless run

        run.update!(
          status: "canceled",
          finished_at: now,
          debug: (run.debug || {}).merge(
            "canceled_by" => @reason,
            "canceled_at" => now.iso8601
          )
        )
      end
    end
  end
end
