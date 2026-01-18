# frozen_string_literal: true

# Service for deleting user messages from a conversation.
#
# Encapsulates business logic for message deletion:
# - Fork point protection (messages referenced by child conversations cannot be deleted)
# - Message destruction with exception handling
# - Canceling/stopping any in-flight scheduling that was based on the message
# - UI operations (broadcasts) are injected via callbacks, keeping service pure
#
# @example Basic usage
#   result = Messages::Destroyer.new(
#     message: message,
#     conversation: conversation,
#     on_destroyed: ->(msg, conv) {
#       msg.broadcast_remove
#       Messages::Broadcasts.broadcast_group_queue_update(conv)
#     }
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
  # @param on_destroyed [Proc, nil] callback called after message is destroyed
  #   Receives (message, conversation) as arguments.
  #   Use this to inject UI operations (e.g., Turbo broadcasts) from the controller.
  def initialize(message:, conversation:, on_destroyed: nil)
    @message = message
    @conversation = conversation
    @on_destroyed = on_destroyed
  end

  # Execute the message deletion.
  #
  # @return [Result] result object with success status and error info
  def call
    return fork_point_protected_result if message.fork_point?

    # Deleting the tail message is a timeline mutation. We must prevent:
    # - an AI response from being produced for a message that no longer exists
    # - the scheduler being left in a stuck "ai_generating" state
    #
    # We only cancel runs that are *logically downstream* of the message:
    # - TurnScheduler-managed runs (debug["scheduled_by"] == "turn_scheduler")
    # - Legacy user-message-triggered runs (debug["trigger"] == "user_message" + matching id)
    #
    # Note: We intentionally do NOT attempt to "rewind" turns_count / quotas.
    conversation.with_lock do
      deleted_message_id = message.id
      cancel_affected_queued_run!(deleted_message_id)
      request_cancel_affected_running_run!(deleted_message_id)
      cancel_active_round_in_lock!(ended_reason: "message_deleted")
      message.destroy!
    end

    on_destroyed&.call(message, conversation)

    success_result
  rescue ActiveRecord::RecordNotDestroyed => e
    # This catches restrict_with_error from dependent associations
    record_not_destroyed_result(e)
  rescue ActiveRecord::InvalidForeignKey => e
    # This catches DB-level FK violations (belt-and-suspenders)
    foreign_key_violation_result(e)
  end

  private

  attr_reader :message, :conversation, :on_destroyed

  def cancel_affected_queued_run!(deleted_message_id)
    queued = ConversationRun.queued.find_by(conversation_id: conversation.id)
    return unless run_affected_by_deleted_message?(queued, deleted_message_id)

    queued.update!(
      status: "canceled",
      finished_at: Time.current,
      debug: (queued.debug || {}).merge(
        "canceled_by" => "message_deleted",
        "canceled_at" => Time.current.iso8601
      )
    )
  end

  def request_cancel_affected_running_run!(deleted_message_id)
    running = ConversationRun.running.find_by(conversation_id: conversation.id)
    return unless run_affected_by_deleted_message?(running, deleted_message_id)

    running.request_cancel!
  end

  def run_affected_by_deleted_message?(run, deleted_message_id)
    return false unless run

    debug = run.debug || {}

    return true if debug["scheduled_by"] == "turn_scheduler"

    debug["trigger"] == "user_message" && debug["user_message_id"].to_i == deleted_message_id.to_i
  end

  def cancel_active_round_in_lock!(ended_reason:)
    active = conversation.conversation_rounds.find_by(status: "active")
    return unless active

    now = Time.current
    active.update!(
      status: "canceled",
      scheduling_state: nil,
      ended_reason: ended_reason.to_s,
      finished_at: now,
      updated_at: now
    )
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
