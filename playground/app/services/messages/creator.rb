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

    message = build_message
    if message.save
      on_created&.call(message, conversation)
      plan_ai_response!(message)
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

  def build_message
    message = conversation.messages.new(content: content)
    message.space_membership = membership
    message.role = "user"
    message
  end

  def plan_ai_response!(message)
    Conversations::RunPlanner.plan_from_user_message!(
      conversation: conversation,
      user_message: message
    )
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
