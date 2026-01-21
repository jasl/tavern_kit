# frozen_string_literal: true

module TurnScheduler
  module Queries
    # Returns a predicted queue of speakers for display purposes.
    #
    # Note: This is a best-effort prediction. Natural and pooled strategies
    # have randomness, so the actual speaker selection may differ.
    #
    class QueuePreview
      def self.execute(conversation:, limit: 5)
        new(conversation, limit).execute
      end

      def initialize(conversation, limit)
        @conversation = conversation
        @space = conversation.space
        @limit = limit
      end

      # @return [Array<SpaceMembership>] ordered list of predicted speakers
      def execute
        state = TurnScheduler.state(@conversation)

        Instrumentation.profile(
          "QueuePreview",
          conversation_id: @conversation.id,
          reply_order: @space.reply_order,
          scheduling_state: state.scheduling_state,
          limit: @limit
        ) do
          # If a round is active and has a persisted queue, prefer it for accuracy.
          # IMPORTANT: If there are *no* upcoming speakers (e.g. pooled/manual single-slot round),
          # we must still return an empty array rather than falling back to a prediction.
          ids = state.round_queue_ids
          if !state.idle? && ids.is_a?(Array) && ids.any?
            persisted = persisted_upcoming_queue(state)
            next persisted.first(@limit)
          end

          candidates = eligible_candidates
          next [] if candidates.empty?

          previous_speaker_id = @conversation.last_assistant_message&.space_membership_id
          allow_self = @space.allow_self_responses?

          queue = case @space.reply_order
          when "list"
                    predict_list_queue(candidates, previous_speaker_id, allow_self)
          when "natural"
                    predict_natural_queue(candidates, previous_speaker_id, allow_self)
          when "pooled"
                    predict_pooled_queue(candidates, previous_speaker_id, allow_self, idle: state.idle?)
          when "manual"
                    candidates
          else
                    candidates
          end

          queue.first(@limit)
        end
      end

      private

      # When a round is active, show the remaining speakers from the persisted queue.
      # This avoids misleading previews when natural/pooled randomness was used.
      def persisted_upcoming_queue(state)
        return [] if state.idle?

        ids = state.round_queue_ids
        return [] unless ids.is_a?(Array) && ids.any?

        # Determine index of current speaker within the persisted queue.
        idx = state.round_position.to_i
        if state.current_speaker_id && ids[idx] != state.current_speaker_id
          found = ids.index(state.current_speaker_id)
          idx = found if found
        end

        upcoming_ids = ids.drop(idx + 1)
        return [] if upcoming_ids.empty?

        members_by_id = @space.space_memberships
          .includes(:character, :user)
          .where(id: upcoming_ids)
          .index_by(&:id)
        upcoming_ids.filter_map { |id| members_by_id[id] }.select(&:can_be_scheduled?)
      end

      def eligible_candidates
        # Note: includes AI characters + Auto users (via ai_respondable_participants).
        # Filter with can_be_scheduled? so the preview doesn't show muted members or exhausted Auto users
        # that the real scheduler will skip.
        @conversation.ai_respondable_participants.by_position.to_a.select(&:can_be_scheduled?)
      end

      def predict_list_queue(candidates, previous_speaker_id, allow_self)
        return candidates unless previous_speaker_id

        idx = candidates.index { |m| m.id == previous_speaker_id }
        return candidates unless idx

        rotated = candidates.rotate(idx + 1)
        return rotated if allow_self

        # "Allow self responses" means "can speak twice in a row", not "exclude forever".
        # Keep the previous speaker in the queue but ensure it isn't first, to avoid
        # confusing UI previews like showing only 1 upcoming member in a 2-member group.
        rotated
      end

      def predict_natural_queue(candidates, previous_speaker_id, allow_self)
        queue = candidates.sort_by do |m|
          talkativeness = m.effective_talkativeness_factor.to_f
          [-talkativeness, m.position]
        end

        return queue if allow_self || !previous_speaker_id || queue.size <= 1

        idx = queue.index { |m| m.id == previous_speaker_id }
        idx ? queue.rotate(idx + 1) : queue
      end

      def predict_pooled_queue(candidates, previous_speaker_id, allow_self, idle:)
        # In pooled mode, each user message triggers exactly one AI response.
        #
        # For *idle previews*, show the full eligible pool (so the UI consistently shows
        # both available AIs in a 2-member group), even though the actual selection is
        # constrained per-epoch (since-last-user-message) when a trigger occurs.
        queue =
          if idle
            candidates
          else
            spoken_ids = spoken_participant_ids_for_current_epoch
            candidates.reject { |m| spoken_ids.include?(m.id) }
          end

        return queue if allow_self || !previous_speaker_id || queue.size <= 1

        idx = queue.index { |m| m.id == previous_speaker_id }
        idx ? queue.rotate(idx + 1) : queue
      end

      def spoken_participant_ids_for_current_epoch
        epoch_message = @conversation.last_user_message
        return [] unless epoch_message

        @conversation
          .messages
          .scheduler_visible
          .where(role: "assistant")
          .after_cursor(epoch_message)
          .distinct
          .pluck(:space_membership_id)
      end
    end
  end
end
