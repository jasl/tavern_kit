# frozen_string_literal: true

# Service for regenerating the last turn in a group conversation.
#
# This service handles the "last_turn" regeneration mode for group chats:
# - Deletes all messages after the last user message (the AI turn)
# - Handles fork point protection (auto-branches if messages are fork points)
# - Handles concurrent fork creation gracefully
#
# Key design decisions:
# - Uses `delete_all` for atomic deletion (avoids partial deletes)
# - Returns a Result object with outcome type for controller to handle
# - UI operations (broadcasts) are injected via callbacks, keeping service pure
#
# @example Basic usage
#   result = Conversations::LastTurnRegenerator.new(
#     conversation: conversation,
#     on_messages_deleted: ->(ids, conv) {
#       ids.each { |id| Turbo::StreamsChannel.broadcast_remove_to(conv, :messages, target: "message_#{id}") }
#       Messages::Broadcasts.broadcast_group_queue_update(conv)
#     }
#   ).call
#
#   if result.fallback_branch?
#     redirect_to conversation_url(result.conversation)
#   elsif result.success?
#     TurnScheduler::Commands::StartRound.call(
#       conversation: conversation,
#       trigger_message: conversation.last_user_message,
#       is_user_input: false
#     )
#   elsif result.nothing_to_regenerate?
#     render_toast_warning("Nothing to regenerate yet")
#   else
#     render_toast_error(result.error)
#   end
#
class Conversations::LastTurnRegenerator
  # Result object returned by #call
  #
  # @!attribute [r] success?
  #   @return [Boolean] whether the operation succeeded
  # @!attribute [r] conversation
  #   @return [Conversation, nil] the conversation to use (original or new branch)
  # @!attribute [r] error
  #   @return [String, nil] human-readable error message
  # @!attribute [r] error_code
  #   @return [Symbol, nil] machine-readable code for branching
  # @!attribute [r] deleted_message_ids
  #   @return [Array<Integer>, nil] IDs of deleted messages (for broadcasting)
  Result = Data.define(:success?, :conversation, :error, :error_code, :deleted_message_ids) do
    def ok? = success?
    def fallback_branch? = error_code == :fallback_branch
    def nothing_to_regenerate? = error_code == :nothing_to_regenerate
    def error? = error_code == :error
  end

  # @param conversation [Conversation] the conversation to regenerate
  # @param on_messages_deleted [Proc, nil] callback called after messages are deleted
  #   Receives (message_ids, conversation) as arguments.
  #   Use this to inject UI operations (e.g., Turbo broadcasts) from the controller.
  def initialize(conversation:, on_messages_deleted: nil)
    @conversation = conversation
    @on_messages_deleted = on_messages_deleted
  end

  # Execute the last turn regeneration.
  #
  # @return [Result] result object with outcome and relevant data
  def call
    # Find the last user message (the start of the current turn)
    last_user_message = conversation.messages.where(role: "user").order(seq: :desc).first

    # No user messages: nothing to regenerate
    # This preserves greeting messages and provides clear feedback to the user.
    unless last_user_message
      return nothing_to_regenerate_result
    end

    # Identify messages to delete (all messages after the last user message)
    messages_to_delete = conversation.messages.where("seq > ?", last_user_message.seq)
    message_ids_to_delete = messages_to_delete.pluck(:id)

    # No messages to delete (user message is the tail)
    if message_ids_to_delete.empty?
      return success_result(deleted_message_ids: [])
    end

    # Check if any of these messages are fork points
    if fork_points_exist?(message_ids_to_delete)
      return create_fallback_branch(last_user_message)
    end

    # Attempt atomic deletion
    perform_atomic_deletion(message_ids_to_delete, last_user_message)
  end

  private

  attr_reader :conversation, :on_messages_deleted

  # Check if any of the given message IDs are fork points.
  #
  # @param message_ids [Array<Integer>] message IDs to check
  # @return [Boolean] true if any message is a fork point
  def fork_points_exist?(message_ids)
    Conversation.where(forked_from_message_id: message_ids).exists?
  end

  # Perform atomic deletion of messages.
  # Uses delete_all for atomicity - either all are deleted or none.
  #
  # @param message_ids [Array<Integer>] IDs of messages to delete
  # @param last_user_message [Message] the last user message (for fallback branching)
  # @return [Result] success or fallback_branch result
  def perform_atomic_deletion(message_ids, last_user_message)
    deleted_count = 0

    Message.transaction do
      # Single SQL DELETE - atomic, no partial deletes possible
      deleted_count = Message.where(id: message_ids).delete_all
    end

    # Deletion succeeded - invoke callback for UI operations (if provided)
    on_messages_deleted&.call(message_ids, conversation)

    success_result(deleted_message_ids: message_ids)
  rescue ActiveRecord::InvalidForeignKey
    # A fork was created concurrently between our check and the delete.
    # Fall back to branching strategy.
    create_fallback_branch(last_user_message)
  end

  # Create a fallback branch from the last user message.
  # This preserves the original conversation and its branches.
  #
  # @param last_user_message [Message] the message to branch from
  # @return [Result] fallback_branch result with new conversation, or error
  def create_fallback_branch(last_user_message)
    result = Conversations::Forker.new(
      parent_conversation: conversation,
      fork_from_message: last_user_message,
      kind: "branch",
      title: "#{conversation.title} (regenerated)",
      async: false # Force sync to ensure messages are ready
    ).call

    if result.success?
      fallback_branch_result(result.conversation)
    else
      error_result(result.error)
    end
  end

  # --- Result constructors ---

  def success_result(deleted_message_ids:)
    Result.new(
      success?: true,
      conversation: conversation,
      error: nil,
      error_code: nil,
      deleted_message_ids: deleted_message_ids
    )
  end

  def fallback_branch_result(branch_conversation)
    Result.new(
      success?: true,
      conversation: branch_conversation,
      error: nil,
      error_code: :fallback_branch,
      deleted_message_ids: nil
    )
  end

  def nothing_to_regenerate_result
    Result.new(
      success?: false,
      conversation: conversation,
      error: nil,
      error_code: :nothing_to_regenerate,
      deleted_message_ids: nil
    )
  end

  def error_result(message)
    Result.new(
      success?: false,
      conversation: conversation,
      error: message,
      error_code: :error,
      deleted_message_ids: nil
    )
  end
end
