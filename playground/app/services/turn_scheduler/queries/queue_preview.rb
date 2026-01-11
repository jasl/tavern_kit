# frozen_string_literal: true

module TurnScheduler
  module Queries
    # Returns a predicted queue of speakers for display purposes.
    #
    # Note: This is a best-effort prediction. Natural and pooled strategies
    # have randomness, so the actual speaker selection may differ.
    #
    class QueuePreview
      def self.call(conversation:, limit: 5)
        new(conversation, limit).call
      end

      def initialize(conversation, limit)
        @conversation = conversation
        @space = conversation.space
        @limit = limit
      end

      # @return [Array<SpaceMembership>] ordered list of predicted speakers
      def call
        # If a round is active, prefer the persisted queue for accuracy.
        persisted = persisted_upcoming_queue
        return persisted.first(@limit) if persisted.any?

        candidates = eligible_candidates
        return [] if candidates.empty?

        previous_speaker = @conversation.last_assistant_message&.space_membership
        allow_self = @space.allow_self_responses?

        queue = case @space.reply_order
        when "list"
                  predict_list_queue(candidates, previous_speaker, allow_self)
        when "natural"
                  predict_natural_queue(candidates, previous_speaker, allow_self)
        when "pooled"
                  predict_pooled_queue(candidates, previous_speaker, allow_self)
        when "manual"
                  candidates
        else
                  candidates
        end

        queue.first(@limit)
      end

      private

      # When a round is active, show the remaining speakers from the persisted queue.
      # This avoids misleading previews when natural/pooled randomness was used.
      def persisted_upcoming_queue
        return [] if @conversation.scheduling_state == "idle"

        ids = @conversation.round_queue_ids
        return [] unless ids.is_a?(Array) && ids.any?

        # Determine index of current speaker within the persisted queue.
        idx = @conversation.round_position.to_i
        if @conversation.current_speaker_id && ids[idx] != @conversation.current_speaker_id
          found = ids.index(@conversation.current_speaker_id)
          idx = found if found
        end

        upcoming_ids = ids.drop(idx + 1)
        return [] if upcoming_ids.empty?

        members_by_id = @conversation.space.space_memberships
          .includes(:character, :user)
          .where(id: upcoming_ids)
          .index_by(&:id)
        upcoming_ids.filter_map { |id| members_by_id[id] }.select(&:can_be_scheduled?)
      end

      def eligible_candidates
        # ai_respondable_participants already includes(:character, :user)
        @conversation.ai_respondable_participants.by_position.to_a.select(&:can_auto_respond?)
      end

      def predict_list_queue(candidates, previous_speaker, allow_self)
        return candidates unless previous_speaker

        idx = candidates.index { |m| m.id == previous_speaker.id }
        return candidates unless idx

        rotated = candidates.rotate(idx + 1)
        rotated = rotated.reject { |m| m.id == previous_speaker.id } unless allow_self
        rotated
      end

      def predict_natural_queue(candidates, previous_speaker, allow_self)
        queue = candidates.sort_by do |m|
          talkativeness = m.talkativeness_factor.to_f
          talkativeness = SpaceMembership::DEFAULT_TALKATIVENESS_FACTOR if talkativeness.zero? && m.talkativeness_factor.nil?
          [-talkativeness, m.position]
        end

        queue = queue.reject { |m| m.id == previous_speaker&.id } unless allow_self
        queue
      end

      def predict_pooled_queue(candidates, previous_speaker, allow_self)
        spoken_ids = spoken_participant_ids_for_current_epoch
        queue = candidates.reject { |m| spoken_ids.include?(m.id) }
        queue = queue.reject { |m| m.id == previous_speaker&.id } unless allow_self
        queue
      end

      def spoken_participant_ids_for_current_epoch
        epoch_message = @conversation.last_user_message
        return [] unless epoch_message

        @conversation
          .messages
          .where(role: "assistant")
          .after_cursor(epoch_message)
          .distinct
          .pluck(:space_membership_id)
      end
    end
  end
end
