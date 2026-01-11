# frozen_string_literal: true

module TurnScheduler
  module Queries
    # Determines the next speaker for a conversation based on the space's reply_order strategy.
    #
    # Strategies:
    # - manual: No automatic selection; user explicitly picks speaker
    # - natural: Mention detection + talkativeness probability + round-robin fallback
    # - list: Strict position-based rotation
    # - pooled: Each character speaks at most once per user message epoch
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

        candidates = eligible_candidates
        return nil if candidates.empty?

        case @space.reply_order
        when "natural"
          pick_natural(candidates)
        when "list"
          pick_list(candidates)
        when "pooled"
          pick_pooled(candidates)
        else
          nil
        end
      end

      private

      def eligible_candidates
        @conversation.ai_respondable_participants.by_position.to_a.select(&:can_auto_respond?)
      end

      # Natural strategy: SillyTavern-compatible speaker selection.
      def pick_natural(candidates)
        banned_speaker_id = @allow_self ? nil : @previous_speaker&.id

        # Get activation text from last message
        activation_text = last_activation_message&.content

        # Find mentioned candidates
        mentioned = detect_mentioned_candidates(candidates, activation_text, banned_speaker_id)

        # Activate by talkativeness probability
        activated_by_talkativeness = activate_by_talkativeness(candidates, banned_speaker_id)

        # Combine mentioned + talkativeness-activated
        all_activated = (mentioned + activated_by_talkativeness).uniq(&:id)

        return all_activated.sample if all_activated.any?

        # Fallback: chatty members
        chatty = candidates.reject { |c| c.id == banned_speaker_id }
                           .select { |c| c.talkativeness_factor.to_f > 0 }
        return chatty.sample if chatty.any?

        # Final fallback: round-robin
        round_robin_select(candidates)
      end

      def pick_list(candidates)
        return candidates.first unless @previous_speaker

        idx = candidates.index { |m| m.id == @previous_speaker.id } || -1
        next_speaker = candidates[(idx + 1) % candidates.size]
        return next_speaker if @allow_self || @previous_speaker.nil? || next_speaker.id != @previous_speaker.id

        nil
      end

      def pick_pooled(candidates)
        spoken_ids = spoken_participant_ids_for_current_epoch

        available = candidates.reject { |m| spoken_ids.include?(m.id) }
        available = available.reject { |m| m.id == @previous_speaker&.id } unless @allow_self

        return nil if available.empty?

        available.sample
      end

      def last_activation_message
        @last_activation_message ||= @conversation.messages
                                                  .where(role: %w[user assistant])
                                                  .order(:seq, :id)
                                                  .last
      end

      def detect_mentioned_candidates(candidates, text, banned_speaker_id)
        return [] if text.blank?

        input_words = extract_words(text)
        return [] if input_words.empty?

        candidates.select do |candidate|
          next false if candidate.id == banned_speaker_id

          name_words = extract_words(candidate.display_name)
          (name_words & input_words).any?
        end
      end

      def extract_words(text)
        return [] if text.blank?

        text.scan(/\b\w+\b/i).map(&:downcase).uniq
      end

      def activate_by_talkativeness(candidates, banned_speaker_id)
        candidates.select do |candidate|
          next false if candidate.id == banned_speaker_id

          talkativeness = candidate.talkativeness_factor.to_f
          talkativeness = SpaceMembership::DEFAULT_TALKATIVENESS_FACTOR if talkativeness.zero? && candidate.talkativeness_factor.nil?
          talkativeness >= rand
        end
      end

      def round_robin_select(candidates)
        return candidates.first unless @previous_speaker

        idx = candidates.index { |m| m.id == @previous_speaker.id }
        return candidates.first unless idx

        candidates.size.times do |offset|
          next_idx = (idx + 1 + offset) % candidates.size
          candidate = candidates[next_idx]
          next if !@allow_self && candidate.id == @previous_speaker.id
          return candidate
        end

        nil
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
