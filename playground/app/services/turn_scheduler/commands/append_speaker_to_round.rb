# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Appends a speaker to the end of the active round queue.
    #
    # Used by the "Manage round" modal:
    # - Does NOT interrupt the current generation
    # - Allows duplicate turns for the same speaker within a round
    #
    # @return [ConversationRoundParticipant, nil] the inserted participant slot
    class AppendSpeakerToRound
      def self.call(conversation:, speaker_id:, expected_round_id: nil, reason: "append_speaker_to_round")
        new(conversation, speaker_id, expected_round_id, reason).call
      end

      def initialize(conversation, speaker_id, expected_round_id, reason)
        @conversation = conversation
        @space = conversation.space
        @speaker_id = speaker_id
        @expected_round_id = expected_round_id
        @reason = reason.to_s
      end

      def call
        inserted = nil

        @conversation.with_lock do
          active_round = @conversation.conversation_rounds.find_by(status: "active")
          next nil unless active_round
          next nil if @speaker_id.blank?

          if @expected_round_id.present? && active_round.id != @expected_round_id.to_s
            next nil
          end

          speaker = @space.space_memberships.find_by(id: @speaker_id)
          next nil unless speaker&.can_be_scheduled?

          now = Time.current
          pos = (active_round.participants.maximum(:position) || -1) + 1

          inserted =
            active_round.participants.create!(
              space_membership_id: speaker.id,
              position: pos,
              status: "pending",
              created_at: now,
              updated_at: now
            )

          annotate_round!(active_round, inserted: inserted, at: now)
        end

        Broadcasts.queue_updated(@conversation) if inserted
        inserted
      end

      private

      def annotate_round!(active_round, inserted:, at:)
        meta = (active_round.metadata || {}).dup
        meta["insertions"] ||= []
        meta["insertions"] << {
          "speaker_id" => inserted.space_membership_id,
          "position" => inserted.position,
          "reason" => @reason,
          "inserted_at" => at.iso8601,
          "kind" => "append",
        }

        active_round.update!(metadata: meta, updated_at: at)
      end
    end
  end
end
