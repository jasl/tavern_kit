# frozen_string_literal: true

module TurnScheduler
  module Queries
    # Computes the activated speaker queue for the next scheduling round.
    #
    # This intentionally aligns with SillyTavern / RisuAI group-chat semantics:
    # - natural: mentions-first + talkativeness activation (can be multi)
    # - list: all eligible speakers in list order (can be multi)
    # - pooled: pick 1 speaker that hasn't spoken since last user message (single)
    # - manual: user-trigger produces none; non-user trigger picks 1 random (single)
    #
    # IMPORTANT: natural/pooled involve randomness. Callers should persist the
    # resulting queue on the conversation to avoid recomputing mid-round.
    #
    class ActivatedQueue
      def self.call(conversation:, trigger_message: nil, is_user_input: nil, rng: Random)
        new(conversation, trigger_message, is_user_input, rng).call
      end

      def initialize(conversation, trigger_message, is_user_input, rng)
        @conversation = conversation
        @space = conversation.space
        @trigger_message = trigger_message
        @is_user_input = is_user_input
        @rng = rng
      end

      # @return [Array<SpaceMembership>] ordered activated speakers
      def call
        candidates = eligible_candidates
        return [] if candidates.empty?

        is_user_input = resolved_is_user_input

        case @space.reply_order
        when "natural"
          pick_natural(candidates, is_user_input: is_user_input)
        when "list"
          candidates
        when "pooled"
          pick_pooled(candidates, is_user_input: is_user_input)
        when "manual"
          pick_manual(candidates, is_user_input: is_user_input)
        else
          candidates
        end
      end

      private

      def eligible_candidates
        # Note: includes AI characters + full copilot users with persona.
        @conversation.ai_respondable_participants.by_position.to_a.select(&:can_auto_respond?)
      end

      def resolved_is_user_input
        return @is_user_input unless @is_user_input.nil?
        return false unless @trigger_message

        @trigger_message.user?
      end

      def activation_text(is_user_input:)
        return @trigger_message.content.to_s if @trigger_message

        # When there's no explicit trigger message (e.g. auto-mode start),
        # fall back to the last non-system message.
        @conversation.messages.where(role: %w[user assistant]).order(:seq, :id).last&.content.to_s
      end

      def last_non_system_message
        @last_non_system_message ||= @conversation.messages.where(role: %w[user assistant]).order(:seq, :id).last
      end

      def last_assistant_membership_id
        @conversation.last_assistant_message&.space_membership_id
      end

      def pick_manual(candidates, is_user_input:)
        return [] if is_user_input

        [pick_one(candidates)]
      end

      def pick_pooled(candidates, is_user_input:)
        spoken_ids = spoken_participant_ids_for_current_epoch

        available = candidates.reject { |m| spoken_ids.include?(m.id) }
        return [pick_one(available)] if available.any?

        # ST fallback: pick random, avoiding immediate repeat when possible.
        pool = candidates
        if candidates.size > 1 && last_assistant_membership_id
          pool = candidates.reject { |m| m.id == last_assistant_membership_id }
          pool = candidates if pool.empty?
        end

        [pick_one(pool)]
      end

      def pick_natural(candidates, is_user_input:)
        allow_self = @space.allow_self_responses?

        banned_id =
          if is_user_input || allow_self
            nil
          else
            # ST only bans when activation is NOT user input and last message is from a character.
            last_msg = last_non_system_message
            last_msg&.assistant? ? last_msg.space_membership_id : nil
          end

        text = activation_text(is_user_input: is_user_input)

        activated = []

        # 1) Mention activation (preserve input word order)
        if text.present?
          input_words = extract_words(text)
          input_words.each do |word|
            candidates.each do |candidate|
              next if banned_id && candidate.id == banned_id

              name_words = extract_words(candidate.display_name)
              if name_words.include?(word)
                activated << candidate
                break
              end
            end
          end
        end

        # 2) Talkativeness activation (shuffled order)
        chatty = []
        shuffled = candidates.shuffle(random: @rng)
        shuffled.each do |candidate|
          next if banned_id && candidate.id == banned_id

          talk = talkativeness_for(candidate)
          activated << candidate if talk >= @rng.rand
          chatty << candidate if talk.positive?
        end

        activated = activated.uniq(&:id)

        # 3) Fallback: pick 1 at random if none activated
        if activated.empty?
          pool = chatty.any? ? chatty : candidates
          activated << pick_one(pool)
        end

        activated
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

      def talkativeness_for(membership)
        talk = membership.talkativeness_factor
        talk = SpaceMembership::DEFAULT_TALKATIVENESS_FACTOR if talk.nil? || (talk.to_f.zero? && membership.talkativeness_factor.nil?)
        talk.to_f
      end

      def extract_words(text)
        return [] if text.blank?

        # ST/Risu use simple splitting; we keep it close and case-insensitive.
        text.scan(/\b\w+\b/i).map(&:downcase).uniq
      end

      def pick_one(array)
        return nil if array.empty?

        array[@rng.rand(array.length)]
      end
    end
  end
end
