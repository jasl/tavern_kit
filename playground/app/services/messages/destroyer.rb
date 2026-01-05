# frozen_string_literal: true

# Service for deleting user messages from a conversation.
#
# Encapsulates business logic for message deletion:
# - Fork point protection (messages referenced by child conversations cannot be deleted)
# - Message destruction with exception handling
# - Broadcasting removal
# - Canceling orphaned ConversationRuns
#
# @example Basic usage
#   result = Messages::Destroyer.new(
#     message: message,
#     conversation: conversation
#   ).call
#
#   if result.success?
#     respond_to do |format|
#       format.turbo_stream
#       format.html { redirect_to conversation_url(conversation) }
#     end
#   else
#     case result.error_code
#     when :fork_point_protected then render_fork_point_error
#     when :foreign_key_violation then render_fk_error
#     else head :unprocessable_entity
#     end
#   end
#
class Messages::Destroyer
  # Result object returned by #call
  #
  # @!attribute [r] success?
  #   @return [Boolean] whether the operation succeeded
  # @!attribute [r] error
  #   @return [String, nil] human-readable error message
  # @!attribute [r] error_code
  #   @return [Symbol, nil] machine-readable error code for branching in controller
  Result = Data.define(:success?, :error, :error_code)

  # @param message [Message] the message to delete
  # @param conversation [Conversation] the conversation containing the message
  def initialize(message:, conversation:)
    @message = message
    @conversation = conversation
  end

  # Execute the message deletion.
  #
  # @return [Result] result object with success status and error info
  def call
    return fork_point_protected_result if message.fork_point?

    message_id = message.id

    message.destroy!
    message.broadcast_remove
    Message::Broadcasts.broadcast_group_queue_update(conversation)
    cancel_orphaned_queued_run(message_id)

    success_result
  rescue ActiveRecord::RecordNotDestroyed => e
    # This catches restrict_with_error from dependent associations
    record_not_destroyed_result(e)
  rescue ActiveRecord::InvalidForeignKey => e
    # This catches DB-level FK violations (belt-and-suspenders)
    foreign_key_violation_result(e)
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

  # Result constructors

  def success_result
    Result.new(success?: true, error: nil, error_code: nil)
  end

  def fork_point_protected_result
    Result.new(
      success?: false,
      error: "This message is a fork point for other conversations and cannot be deleted.",
      error_code: :fork_point_protected
    )
  end

  def record_not_destroyed_result(exception)
    Result.new(
      success?: false,
      error: exception.record&.errors&.full_messages&.to_sentence.presence ||
             "Message cannot be deleted due to existing references.",
      error_code: :record_not_destroyed
    )
  end

  def foreign_key_violation_result(_exception)
    Result.new(
      success?: false,
      error: "Message cannot be deleted because it is referenced by other records.",
      error_code: :foreign_key_violation
    )
  end
end
