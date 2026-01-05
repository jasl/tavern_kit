# frozen_string_literal: true

# Service for deleting user messages from a conversation.
#
# Encapsulates business logic for message deletion:
# - Message destruction
# - Broadcasting removal
# - Canceling orphaned ConversationRuns
#
# @example Basic usage
#   Messages::Destroyer.new(
#     message: message,
#     conversation: conversation
#   ).call
#
class Messages::Destroyer
  # @param message [Message] the message to delete
  # @param conversation [Conversation] the conversation containing the message
  def initialize(message:, conversation:)
    @message = message
    @conversation = conversation
  end

  # Execute the message deletion.
  #
  # @return [void]
  def call
    message_id = message.id

    message.destroy!
    message.broadcast_remove

    cancel_orphaned_queued_run(message_id)
  end

  private

  attr_reader :message, :conversation

  # Cancel any queued ConversationRun that was triggered by the deleted message.
  # This prevents orphaned AI responses when a user deletes their message before
  # the AI has started generating a response.
  #
  # Only cancels if the queued run matches all conditions:
  # - kind == "user_turn"
  # - debug["trigger"] == "user_message"
  # - debug["user_message_id"] == deleted_message_id
  def cancel_orphaned_queued_run(deleted_message_id)
    queued_run = ConversationRun.queued.find_by(conversation_id: conversation.id)
    return unless queued_run
    return unless queued_run.user_turn?
    return unless queued_run.debug&.dig("trigger") == "user_message"
    return unless queued_run.debug&.dig("user_message_id") == deleted_message_id

    queued_run.canceled!
  end
end
