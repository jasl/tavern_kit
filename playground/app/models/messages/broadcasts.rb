# frozen_string_literal: true

module Messages
  # Broadcast callbacks for Message model.
  #
  # Provides explicit broadcast methods for message lifecycle events via Turbo Streams.
  # All DOM updates go through Turbo Streams for reliable delivery.
  #
  # JSON events (typing, streaming) are handled by ConversationChannel separately.
  #
  # @example Turbo Stream subscription in view
  #   <%= turbo_stream_from @conversation, :messages %>
  #
  # @example Manual broadcast from controller
  #   @message.broadcast_create
  #
  module Broadcasts
    extend ActiveSupport::Concern

    # Broadcast the new message to all conversation subscribers.
    #
    # @return [void]
    def broadcast_create
      broadcast_append_to(
        conversation, :messages,
        target: dom_id(conversation, :messages_list),
        partial: "messages/message",
        locals: { message: self }
      )
    end

    # Broadcast the message update to all conversation subscribers.
    #
    # @return [void]
    def broadcast_update
      broadcast_replace_to(
        conversation, :messages,
        target: dom_id(self),
        partial: "messages/message",
        locals: { message: self }
      )
    end

    # Broadcast the message removal to all conversation subscribers.
    #
    # @return [void]
    def broadcast_remove
      broadcast_remove_to conversation, :messages
    end

    # Broadcast a copilot candidate reply.
    #
    # Uses CopilotChannel (separate from ConversationChannel/Turbo Streams) following
    # Campfire's pattern of separating concerns.
    #
    # Broadcasts to the specific membership to ensure unicast delivery
    # (only the requesting user receives the candidate).
    #
    # @param space_membership [SpaceMembership] the membership to broadcast to
    # @param generation_id [String] unique ID for this generation request
    # @param index [Integer] the candidate index (0-based)
    # @param text [String] the candidate text
    # @return [void]
    def self.broadcast_copilot_candidate(space_membership, generation_id:, index:, text:)
      CopilotChannel.broadcast_to(
        space_membership,
        {
          type: "copilot_candidate",
          generation_id: generation_id,
          index: index,
          text: text,
        }
      )
    end

    # Broadcast copilot generation error.
    #
    # Signals that generation failed with an error message.
    #
    # @param space_membership [SpaceMembership] the membership to broadcast to
    # @param generation_id [String] unique ID for this generation request
    # @param error [String] the error message
    # @return [void]
    def self.broadcast_copilot_error(space_membership, generation_id:, error:)
      CopilotChannel.broadcast_to(
        space_membership,
        {
          type: "copilot_error",
          generation_id: generation_id,
          error: error,
        }
      )
    end

    # Broadcast full copilot mode disabled.
    #
    # Used when AI generation fails during auto-mode, or when remaining steps
    # are exhausted, notifying the client to disable full mode.
    #
    # @param space_membership [SpaceMembership] the membership to broadcast to
    # @param error [String, nil] the error message if disabled due to error
    # @param reason [String, nil] the reason code if disabled for other reasons
    #   (e.g., "remaining_steps_exhausted")
    # @return [void]
    def self.broadcast_copilot_disabled(space_membership, error: nil, reason: nil)
      CopilotChannel.broadcast_to(
        space_membership,
        {
          type: "copilot_disabled",
          error: error,
          reason: reason,
        }.compact
      )
    end

    # Broadcast copilot steps updated.
    #
    # Used when copilot remaining steps are decremented,
    # notifying the client to update the displayed count.
    #
    # @param space_membership [SpaceMembership] the membership to broadcast to
    # @param remaining_steps [Integer] the new remaining steps count
    # @return [void]
    def self.broadcast_copilot_steps_updated(space_membership, remaining_steps:)
      CopilotChannel.broadcast_to(
        space_membership,
        {
          type: "copilot_steps_updated",
          remaining_steps: remaining_steps,
        }
      )
    end

    # Broadcast group chat queue update.
    #
    # Delegates to TurnScheduler::Broadcasts.queue_updated which is the
    # single source of truth for queue-related broadcasts.
    #
    # @param conversation [Conversation] the conversation whose queue to update
    # @return [void]
    def self.broadcast_group_queue_update(conversation)
      return unless conversation.space.group?

      TurnScheduler::Broadcasts.queue_updated(conversation)
    end

    private

    # Generate DOM ID for ActionView helpers.
    #
    # @param record [ActiveRecord::Base] the record
    # @param prefix [Symbol, nil] optional prefix
    # @return [String] the DOM ID
    def dom_id(record, prefix = nil)
      ActionView::RecordIdentifier.dom_id(record, prefix)
    end

    # Get the stream name for this message's conversation.
    #
    # @return [String] the stream name
    def stream_name
      self.class.broadcasting_for(conversation)
    end

    class_methods do
      # Generate the broadcasting name for a conversation.
      #
      # @param conversation [Conversation] the conversation
      # @return [String] the broadcasting name
      def broadcasting_for(conversation)
        Turbo::StreamsChannel.signed_stream_name([conversation, :messages])
      end
    end
  end
end
