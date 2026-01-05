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
# - Broadcasts removals AFTER successful deletion (ensures UI/DB consistency)
# - Returns a Result object with outcome type for controller to handle
#
# @example Basic usage
#   result = Conversation::LastTurnRegenerator.new(conversation: conversation).call
#
#   case result.outcome
#   when :success
#     Conversation::RunPlanner.plan_user_turn!(conversation: conversation, trigger: "regenerate_turn")
#   when :fallback_branch
#     redirect_to conversation_url(result.conversation)
#   when :nothing_to_regenerate
#     render_toast_warning("Nothing to regenerate yet")
#   when :error
#     render_toast_error(result.error)
#   end
#
class Conversation::LastTurnRegenerator
  # Result object returned by #call
  #
  # @!attribute [r] outcome
  #   @return [Symbol] :success, :fallback_branch, :nothing_to_regenerate, or :error
  # @!attribute [r] conversation
  #   @return [Conversation, nil] the conversation to use (original or new branch)
  # @!attribute [r] error
  #   @return [String, nil] human-readable error message
  # @!attribute [r] deleted_message_ids
  #   @return [Array<Integer>, nil] IDs of deleted messages (for broadcasting)
  Result = Data.define(:outcome, :conversation, :error, :deleted_message_ids) do
    def success?
      outcome == :success
    end

    def fallback_branch?
      outcome == :fallback_branch
    end

    def nothing_to_regenerate?
      outcome == :nothing_to_regenerate
    end

    def error?
      outcome == :error
    end
  end

  # @param conversation [Conversation] the conversation to regenerate
  def initialize(conversation:)
    @conversation = conversation
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

  attr_reader :conversation

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

    # Deletion succeeded - broadcast removals
    broadcast_removals(message_ids)

    success_result(deleted_message_ids: message_ids)
  rescue ActiveRecord::InvalidForeignKey
    # A fork was created concurrently between our check and the delete.
    # Fall back to branching strategy.
    create_fallback_branch(last_user_message)
  end

  # Broadcast message removals to all conversation subscribers.
  # Called AFTER successful deletion to ensure UI/DB consistency.
  #
  # @param message_ids [Array<Integer>] IDs of deleted messages
  # @return [void]
  def broadcast_removals(message_ids)
    message_ids.each do |message_id|
      Turbo::StreamsChannel.broadcast_remove_to(
        conversation, :messages,
        target: "message_#{message_id}"
      )
    end

    # Update group queue display after messages are removed
    Message::Broadcasts.broadcast_group_queue_update(conversation)
  end

  # Create a fallback branch from the last user message.
  # This preserves the original conversation and its branches.
  #
  # @param last_user_message [Message] the message to branch from
  # @return [Result] fallback_branch result with new conversation, or error
  def create_fallback_branch(last_user_message)
    result = Conversation::Forker.new(
      parent_conversation: conversation,
      fork_from_message: last_user_message,
      kind: "branch",
      title: "#{conversation.title} (regenerated)"
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
      outcome: :success,
      conversation: conversation,
      error: nil,
      deleted_message_ids: deleted_message_ids
    )
  end

  def fallback_branch_result(branch_conversation)
    Result.new(
      outcome: :fallback_branch,
      conversation: branch_conversation,
      error: nil,
      deleted_message_ids: nil
    )
  end

  def nothing_to_regenerate_result
    Result.new(
      outcome: :nothing_to_regenerate,
      conversation: conversation,
      error: nil,
      deleted_message_ids: nil
    )
  end

  def error_result(message)
    Result.new(
      outcome: :error,
      conversation: conversation,
      error: message,
      deleted_message_ids: nil
    )
  end
end
