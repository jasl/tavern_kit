# frozen_string_literal: true

module TurnScheduler
  module Queries
    # Determines the next speaker for a conversation based on the space's reply_order strategy.
    #
    # NOTE: Most scheduling now uses ActivatedQueue (full round activation).
    # This query remains as a single-speaker helper for one-off triggers
    # (e.g., "generate without user message", health suggestions).
    #
    # Strategies:
    # - manual: No automatic selection; user explicitly picks speaker
    # - natural: Delegate to ActivatedQueue and take the first activated speaker
    # - list: Strict position-based rotation (single-speaker view)
    # - pooled: Delegate to ActivatedQueue and take the single activated speaker
    #
    class NextSpeaker
      def self.call(conversation:, previous_speaker: nil, allow_self: true)
        new(conversation, previous_speaker, allow_self).call
      end

      def initialize(conversation, previous_speaker, allow_self)
        @conversation = conversation
        @space = conversation.space
        @previous_speaker = previous_speaker
        @allow_self = allow_self
      end

      # @return [SpaceMembership, nil] the next speaker to schedule
      def call
        return nil if @space.reply_order == "manual"

        case @space.reply_order
        when "natural"
          pick_from_activated_queue
        when "list"
          candidates = eligible_candidates
          return nil if candidates.empty?
          pick_list(candidates)
        when "pooled"
          pick_from_activated_queue
        else
          nil
        end
      end

      private

      def eligible_candidates
        @conversation.ai_respondable_participants.by_position.to_a.select(&:can_auto_respond?)
      end

      def pick_list(candidates)
        return candidates.first unless @previous_speaker

        idx = candidates.index { |m| m.id == @previous_speaker.id } || -1
        next_speaker = candidates[(idx + 1) % candidates.size]
        return next_speaker if @allow_self || @previous_speaker.nil? || next_speaker.id != @previous_speaker.id

        nil
      end

      def pick_from_activated_queue
        queue = Queries::ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: last_activation_message,
          rng: Random
        )

        if @previous_speaker && !@allow_self
          queue = queue.reject { |m| m.id == @previous_speaker.id }
        end

        queue.first
      end

      def last_activation_message
        @last_activation_message ||= @conversation.messages
                                                  .scheduler_visible
                                                  .where(role: %w[user assistant])
                                                  .order(:seq, :id)
                                                  .last
      end
    end
  end
end
