# frozen_string_literal: true

# Service for creating user messages in a conversation.
#
# Encapsulates all business logic for message creation:
# - Copilot mode validation
# - During-generation policy enforcement (reject/queue)
# - Message persistence
# - AI response planning
# - UI operations (broadcasts) are injected via callbacks, keeping service pure
#
# @example Basic usage
#   result = Messages::Creator.new(
#     conversation: conversation,
#     membership: user_membership,
#     content: "Hello!",
#     on_created: ->(msg, conv) {
#       msg.broadcast_create
#       Message::Broadcasts.broadcast_group_queue_update(conv)
#     }
#   ).call
#
#   if result.success?
#     redirect_to conversation_url(conversation, anchor: dom_id(result.message))
#   else
#     case result.error_code
#     when :copilot_blocked then head :forbidden
#     when :generation_locked then head :locked
#     else render :new, status: :unprocessable_entity
#     end
#   end
#
class Messages::Creator
  # Result object returned by #call
  #
  # @!attribute [r] success?
  #   @return [Boolean] whether the operation succeeded
  # @!attribute [r] message
  #   @return [Message, nil] the created message (on success) or invalid message (on validation error)
  # @!attribute [r] error
  #   @return [String, nil] human-readable error message
  # @!attribute [r] error_code
  #   @return [Symbol, nil] machine-readable error code for branching in controller
  Result = Data.define(:success?, :message, :error, :error_code)

  # @param conversation [Conversation] the conversation to create the message in
  # @param membership [SpaceMembership] the user's space membership
  # @param content [String] the message content
  # @param on_created [Proc, nil] callback called after message is created
  #   Receives (message, conversation) as arguments.
  #   Use this to inject UI operations (e.g., Turbo broadcasts) from the controller.
  def initialize(conversation:, membership:, content:, on_created: nil)
    @conversation = conversation
    @space = conversation.space
    @membership = membership
    @content = content
    @on_created = on_created
  end

  # Execute the message creation.
  #
  # @return [Result] result object with success status, message, and error info
  def call
    return copilot_blocked_result if copilot_blocks_manual_input?
    return generation_locked_result if reject_policy_blocks?

    apply_restart_policy_to_running_run!

    # Cancel any queued runs - user message takes priority
    # This prevents race conditions where both user and AI messages appear
    cancel_queued_runs!

    # Clear scheduler queue state - user message resets the turn flow
    clear_scheduler_state!

    message = build_message
    if message.save
      on_created&.call(message, conversation)
      # NOTE: AI response is now handled by TurnScheduler via
      # Message after_create_commit callback. No need to call plan_ai_response!
      success_result(message)
    else
      validation_error_result(message)
    end
  end

  private

  attr_reader :conversation, :space, :membership, :content, :on_created

  # Check if copilot_full mode prevents manual message input
  def copilot_blocks_manual_input?
    membership.copilot_full?
  end

  # Check if reject policy blocks new messages during pending generation
  def reject_policy_blocks?
    return false unless space.during_generation_user_input_policy == "reject"

    ConversationRun.running.exists?(conversation_id: conversation.id) ||
      ConversationRun.queued.exists?(conversation_id: conversation.id)
  end

  # For restart policy, user input cancels the in-flight run (ChatGPT-like).
  # We still allow the message to be created; the queued follow-up run will be
  # scheduled by TurnScheduler after commit.
  def apply_restart_policy_to_running_run!
    return unless space.during_generation_user_input_policy == "restart"

    running = ConversationRun.running.find_by(conversation_id: conversation.id)
    running&.request_cancel!
  end

  def build_message
    message = conversation.messages.new(content: content)
    message.space_membership = membership
    message.role = "user"
    message
  end

  # Cancel any queued runs for this conversation.
  # User's message takes priority over any auto-generated content.
  def cancel_queued_runs!
    conversation.cancel_all_queued_runs!(reason: "user_message_submitted")
  end

  # Clear the scheduler queue state.
  # User's message resets the turn flow - the scheduler will start fresh
  # after the message is created via the after_create_commit callback.
  def clear_scheduler_state!
    TurnScheduler.stop!(conversation)
  end

  # Result constructors

  def success_result(message)
    Result.new(success?: true, message: message, error: nil, error_code: nil)
  end

  def copilot_blocked_result
    Result.new(
      success?: false,
      message: nil,
      error: "Copilot is in full mode. Manual replies are disabled.",
      error_code: :copilot_blocked
    )
  end

  def generation_locked_result
    Result.new(
      success?: false,
      message: nil,
      error: "AI is generating a response. Please wait…",
      error_code: :generation_locked
    )
  end

  def validation_error_result(message)
    Result.new(
      success?: false,
      message: message,
      error: message.errors.full_messages.to_sentence,
      error_code: :validation_failed
    )
  end
end
