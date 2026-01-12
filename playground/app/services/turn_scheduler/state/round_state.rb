# frozen_string_literal: true

module TurnScheduler
  module State
    # Value object representing the current round state.
    #
    # Encapsulates all state needed to understand and manipulate the current
    # conversation scheduling state. Provides a clean interface for querying
    # state without exposing implementation details.
    #
    class RoundState
      attr_reader :conversation

      def initialize(conversation)
        @conversation = conversation
      end

      def round
        @round ||= @conversation.conversation_rounds.find_by(status: "active")
      end

      def scheduling_state
        return "idle" unless round

        round.scheduling_state
      end

      def current_round_id
        round&.id
      end

      def round_position
        round ? round.current_position.to_i : 0
      end

      def round_queue_ids
        participants.map(&:space_membership_id)
      end

      def round_spoken_ids
        participants.select(&:spoken?).map(&:space_membership_id)
      end

      def current_speaker_id
        participants[round_position]&.space_membership_id
      end

      # @return [Boolean] true if no active scheduling is happening
      def idle?
        round.nil?
      end

      # @return [Boolean] true if AI is currently generating
      def ai_generating?
        scheduling_state == "ai_generating"
      end

      # @return [Boolean] true if scheduling failed
      def failed?
        scheduling_state == "failed"
      end

      # @return [Boolean] true if scheduling is paused
      def paused?
        scheduling_state == "paused"
      end

      # @return [Boolean] true if there's an active round (not idle or failed)
      def active?
        !idle? && !failed?
      end

      # @return [SpaceMembership, nil] the current speaker membership
      def current_speaker
        return nil unless current_speaker_id

        conversation.space.space_memberships.find_by(id: current_speaker_id)
      end

      # @return [Boolean] true if the given membership has already spoken this round
      def has_spoken?(membership_id)
        round_spoken_ids.include?(membership_id)
      end

      # @return [Integer] number of participants who have spoken this round
      def spoken_count
        round_spoken_ids.size
      end

      # @return [Boolean] true if round has valid state
      def valid?
        return true if idle?

        current_round_id.present?
      end

      # @return [Hash] serialized state for debugging
      def to_h
        {
          scheduling_state: scheduling_state,
          current_round_id: current_round_id,
          current_speaker_id: current_speaker_id,
          round_position: round_position,
          round_spoken_ids: round_spoken_ids,
          round_queue_ids: round_queue_ids,
        }
      end

      private

      def participants
        return [] unless round

        @participants ||= round.participants.order(:position).to_a
      end
    end
  end
end
