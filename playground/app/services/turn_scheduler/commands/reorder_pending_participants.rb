# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Reorders the pending portion of the active round queue.
    #
    # Rules:
    # - Only affects the "editable" portion of the queue:
    #   - paused: editable starts at current_position
    #   - ai_generating: editable starts at current_position + 1
    # - Only pending participants are reorderable.
    # - Uses a two-phase position update to respect unique (round_id, position).
    #
    # @return [ServiceResponse] payload includes:
    # - `ok` [Boolean]
    class ReorderPendingParticipants
      def self.execute(conversation:, participant_ids:, expected_round_id: nil, reason: "reorder_pending_participants")
        new(conversation, participant_ids, expected_round_id, reason).execute
      end

      def initialize(conversation, participant_ids, expected_round_id, reason)
        @conversation = conversation
        @space = conversation.space
        @participant_ids = Array(participant_ids)
        @expected_round_id = expected_round_id
        @reason = reason.to_s
      end

      def execute
        ok = false

        @conversation.with_lock do
          active_round = @conversation.conversation_rounds.find_by(status: "active")
          next false unless active_round

          if @expected_round_id.present? && active_round.id != @expected_round_id.to_s
            next false
          end

          editable_from = editable_from(active_round)

          reorderables = active_round.participants.where("position >= ?", editable_from).order(:position).to_a
          next true if reorderables.empty?
          next false unless reorderables.all?(&:pending?)

          desired_ids = normalize_ids(@participant_ids)
          current_ids = reorderables.map(&:id)
          next false if desired_ids.length != current_ids.length
          next false if desired_ids.sort != current_ids.sort

          max_position = active_round.participants.maximum(:position).to_i
          temp_base = max_position + 1000

          reorderables.each_with_index do |participant, idx|
            participant.update!(position: temp_base + idx)
          end

          by_id = reorderables.index_by(&:id)
          desired_ids.each_with_index do |id, idx|
            by_id.fetch(id).update!(position: editable_from + idx)
          end

          annotate_round!(active_round)
          ok = true
        end

        Broadcasts.queue_updated(@conversation) if ok

        ::ServiceResponse.success(
          reason: ok ? :reordered : :not_reordered,
          payload: { ok: ok }
        )
      end

      private

      def normalize_ids(raw)
        raw.map { |v| Integer(v) rescue nil }.compact
      end

      def editable_from(active_round)
        current = active_round.current_position.to_i
        paused = active_round.scheduling_state == "paused"
        current + (paused ? 0 : 1)
      end

      def annotate_round!(active_round)
        now = Time.current
        meta = (active_round.metadata || {}).dup
        meta["reordered_at"] = now.iso8601
        meta["reordered_reason"] = @reason
        active_round.update!(metadata: meta, updated_at: now)
      end
    end
  end
end
