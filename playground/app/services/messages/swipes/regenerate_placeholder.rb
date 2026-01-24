# frozen_string_literal: true

module Messages
  module Swipes
    class RegeneratePlaceholder
      class << self
        # Creates (or reuses) a placeholder swipe for a regenerate run.
        #
        # This enables ST-like UX:
        # - swipe count increments immediately (new empty swipe)
        # - message shows loading state while regeneration runs
        #
        # The placeholder swipe is later filled by RunPersistence when generation completes.
        #
        # @param message [Message] the target assistant message being regenerated
        # @param run [ConversationRun] the regenerate run
        # @return [Hash] { placeholder_swipe_id:, previous_active_swipe_id:, previous_conversation_run_id: }
        def prepare!(message:, run:)
          raise ArgumentError, "run must be regenerate" unless run&.regenerate?
          raise ArgumentError, "message must be assistant" unless message&.assistant_message?

          if (existing = reuse_existing_placeholder(message: message, run: run))
            return existing
          end

          message.ensure_initial_swipe! if message.message_swipes.empty?

          previous_active_swipe_id = message.active_message_swipe_id
          previous_conversation_run_id = message.conversation_run_id

          placeholder = create_placeholder_swipe!(message: message, run: run)

          message.update!(
            active_message_swipe: placeholder,
            generation_status: "generating",
            content: nil,
            conversation_run_id: run.id
          )

          {
            placeholder_swipe_id: placeholder.id,
            previous_active_swipe_id: previous_active_swipe_id,
            previous_conversation_run_id: previous_conversation_run_id,
          }
        end

        # Reverts a placeholder swipe for a regenerate run (skip/cancel/fail/stale).
        #
        # @param run [ConversationRun] the regenerate run
        # @return [Boolean] true if anything changed
        def revert!(run:)
          return false unless run&.regenerate?

          message_id = run.debug&.dig("target_message_id")
          return false if message_id.blank?

          message = Message.find_by(id: message_id, conversation_id: run.conversation_id)
          return false unless message

          placeholder_id = run.debug&.dig("regenerate_placeholder_swipe_id")
          previous_swipe_id = run.debug&.dig("regenerate_previous_swipe_id")
          previous_conversation_run_id = run.debug&.dig("regenerate_previous_conversation_run_id")

          changed = false

          if placeholder_id.present?
            placeholder = message.message_swipes.find_by(id: placeholder_id)
            if placeholder
              placeholder.destroy!
              changed = true
            end
          end

          previous_swipe = previous_swipe_id.present? ? message.message_swipes.find_by(id: previous_swipe_id) : nil
          fallback_swipe = previous_swipe || message.message_swipes.ordered.last || message.message_swipes.ordered.first

          if fallback_swipe
            message.update!(
              active_message_swipe: fallback_swipe,
              generation_status: "succeeded",
              content: fallback_swipe.content,
              conversation_run_id: previous_conversation_run_id
            )
            changed = true
          else
            # No swipes? Just restore message status/content.
            message.update!(
              generation_status: "succeeded",
              conversation_run_id: previous_conversation_run_id
            )
            changed = true
          end

          message.broadcast_update if changed
          changed
        end

        private

        def reuse_existing_placeholder(message:, run:)
          placeholder_id = run.debug&.dig("regenerate_placeholder_swipe_id")
          return nil if placeholder_id.blank?

          placeholder = message.message_swipes.find_by(id: placeholder_id)
          return nil unless placeholder
          return nil unless placeholder.conversation_run_id == run.id
          return nil unless placeholder.content.blank?

          message.update!(
            active_message_swipe: placeholder,
            generation_status: "generating",
            content: nil,
            conversation_run_id: run.id
          )

          {
            placeholder_swipe_id: placeholder.id,
            previous_active_swipe_id: run.debug&.dig("regenerate_previous_swipe_id"),
            previous_conversation_run_id: run.debug&.dig("regenerate_previous_conversation_run_id"),
          }
        end

        def create_placeholder_swipe!(message:, run:)
          next_position = (message.message_swipes.maximum(:position) || -1) + 1

          message.message_swipes.create!(
            position: next_position,
            content: nil,
            metadata: { "regenerate_placeholder" => true },
            conversation_run_id: run.id
          )
        end
      end
    end
  end
end
