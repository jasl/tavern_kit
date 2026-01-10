# frozen_string_literal: true

# Channel for real-time conversation events (typing indicators, streaming).
#
# This channel handles JSON events for:
# - Typing indicators (typing_start, typing_stop)
# - Streaming content chunks (stream_chunk)
#
# DOM updates are handled by Turbo Streams separately.
#
# @example Subscribe from JavaScript
#   cable.subscribeTo({ channel: "ConversationChannel", conversation_id: 123 })
#
class ConversationChannel < ApplicationCable::Channel
  include Rails.application.routes.url_helpers

  # Called when a client subscribes to a conversation.
  # Verifies access and starts streaming events.
  def subscribed
    if (@conversation = find_conversation)
      stream_for @conversation
    else
      reject
    end
  end

  class << self
    include Rails.application.routes.url_helpers

    # Broadcast typing indicator state.
    #
    # @param conversation [Conversation] the conversation to broadcast to
    # @param membership [SpaceMembership] the space membership that is typing
    # @param active [Boolean] true to show typing, false to hide
    def broadcast_typing(conversation, membership:, active:)
      broadcast_to(conversation, {
        type: active ? "typing_start" : "typing_stop",
        space_membership_id: membership.id,
        name: membership.display_name,
        avatar_url: space_membership_portrait_path(
          membership.signed_id(purpose: :portrait),
          v: membership.updated_at.to_fs(:number)
        ),
      })
    end

    # Broadcast streaming content chunk to typing indicator.
    #
    # @param conversation [Conversation] the conversation to broadcast to
    # @param content [String] the current accumulated content
    # @param space_membership_id [Integer] the membership that is generating
    def broadcast_stream_chunk(conversation, content:, space_membership_id:)
      broadcast_to(conversation, {
        type: "stream_chunk",
        content: content,
        space_membership_id: space_membership_id,
      })
    end

    # Broadcast that generation is complete.
    #
    # @param conversation [Conversation] the conversation to broadcast to
    # @param space_membership_id [Integer] the membership that finished generating
    def broadcast_stream_complete(conversation, space_membership_id:)
      broadcast_to(conversation, {
        type: "stream_complete",
        space_membership_id: space_membership_id,
      })
    end

    # Broadcast that a run was skipped (e.g., due to race condition).
    #
    # @param conversation [Conversation] the conversation to broadcast to
    # @param reason [String] the reason code for skipping (e.g., "message_mismatch")
    # @param message [String, nil] optional user-facing message
    def broadcast_run_skipped(conversation, reason:, message: nil)
      broadcast_to(conversation, {
        type: "run_skipped",
        reason: reason,
        message: message,
      })
    end

    # Broadcast that a run was canceled by the user.
    #
    # @param conversation [Conversation] the conversation to broadcast to
    def broadcast_run_canceled(conversation)
      broadcast_to(conversation, {
        type: "run_canceled",
      })
    end

    # Broadcast that a run failed with an error.
    #
    # @param conversation [Conversation] the conversation to broadcast to
    # @param code [String] the error code (e.g., "timeout", "connection_error")
    # @param user_message [String] the user-facing error message
    def broadcast_run_failed(conversation, code:, user_message:)
      broadcast_to(conversation, {
        type: "run_failed",
        code: code,
        message: user_message,
      })
    end
  end

  private

  # Find the conversation if the current user has access.
  #
  # @return [Conversation, nil] the conversation or nil if not accessible
  def find_conversation
    conversation = Conversation.find_by(id: params[:conversation_id])
    return nil unless conversation
    return nil unless current_user.space_memberships.active.exists?(space_id: conversation.space_id)

    conversation
  end
end
