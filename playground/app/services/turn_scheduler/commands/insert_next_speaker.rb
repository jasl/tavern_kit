# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Inserts a speaker as the next turn in the active round.
    #
    # This is a manual scheduling control used by the group chat toolbar:
    # - Does NOT interrupt the current generation
    # - Allows duplicate turns for the same speaker within a round
    #
    # The insertion point is `current_position + 1`.
    #
    # @return [ServiceResponse] payload includes:
    # - `participant` [ConversationRoundParticipant, nil]
    class InsertNextSpeaker
      def self.execute(conversation:, speaker_id:, expected_round_id: nil, reason: "insert_next_speaker")
        new(conversation, speaker_id, expected_round_id, reason).execute
      end

      def initialize(conversation, speaker_id, expected_round_id, reason)
        @conversation = conversation
        @space = conversation.space
        @speaker_id = speaker_id
        @expected_round_id = expected_round_id
        @reason = reason.to_s
      end

      def execute
        inserted = nil

        @conversation.with_lock do
          active_round = @conversation.conversation_rounds.find_by(status: "active")
          next nil unless active_round
          next nil if @speaker_id.blank?

          if @expected_round_id.present? && active_round.id != @expected_round_id
            next nil
          end

          speaker = @space.space_memberships.find_by(id: @speaker_id)
          next nil unless speaker&.can_be_scheduled?

          insert_pos = active_round.current_position.to_i + 1
          now = Time.current

          shift_positions!(active_round, from: insert_pos)

          inserted =
            active_round.participants.create!(
              space_membership_id: speaker.id,
              position: insert_pos,
              status: "pending",
              created_at: now,
              updated_at: now
            )

          annotate_round!(active_round, inserted: inserted, at: now)
        end

        Broadcasts.queue_updated(@conversation) if inserted

        ::ServiceResponse.success(
          reason: inserted ? :inserted : :not_inserted,
          payload: { participant: inserted }
        )
      end

      private

      def shift_positions!(active_round, from:)
        return if from.blank?

        # Shift in descending order to satisfy unique (round_id, position).
        active_round.participants
          .where("position >= ?", from)
          .order(position: :desc)
          .each do |participant|
            participant.update!(position: participant.position.to_i + 1)
          end
      end

      def annotate_round!(active_round, inserted:, at:)
        meta = (active_round.metadata || {}).dup
        meta["insertions"] ||= []
        meta["insertions"] << {
          "speaker_id" => inserted.space_membership_id,
          "position" => inserted.position,
          "reason" => @reason,
          "inserted_at" => at.iso8601,
        }

        active_round.update!(metadata: meta, updated_at: at)
      end
    end
  end
end
