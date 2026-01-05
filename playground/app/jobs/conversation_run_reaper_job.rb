# frozen_string_literal: true

class ConversationRunReaperJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(run_id)
    now = Time.current

    run =
      ConversationRun.transaction do
        locked = ConversationRun.lock.find(run_id)
        return unless locked.running?
        return unless locked.stale?(now: now)

        locked.failed!(
          at: now,
          error: {
            "code" => "stale_running_run",
            "message" => "Run became stale while running",
            "stale_timeout_seconds" => ConversationRun::STALE_TIMEOUT.to_i,
            "heartbeat_at" => locked.heartbeat_at&.iso8601,
          }
        )

        locked
      end

    return unless run

    user_message = I18n.t(
      "messages.generation_errors.stale_running_run",
      default: "Generation timed out. Please try again."
    )

    finalize_placeholder_messages!(run, user_message: user_message, at: now)

    queued = ConversationRun.queued.find_by(conversation_id: run.conversation_id)
    Conversation::RunPlanner.kick!(queued) if queued
  end

  private

  def finalize_placeholder_messages!(run, user_message:, at:)
    # Clean up any orphaned placeholder messages from the stale run.
    # In the new flow, placeholder messages are rare (message created after generation),
    # but this handles backward compatibility for any existing stale runs.
    run
      .messages
      .where("messages.metadata ->> 'generating' = 'true'")
      .find_each do |message|
        metadata = (message.metadata || {}).merge("generating" => false, "error" => user_message)
        message.update!(content: user_message, metadata: metadata, updated_at: at)
        message.broadcast_update
      end

    # Broadcast UI feedback for the stale run:
    # 1. run_failed: show toast notification to user
    # 2. stream_complete: clear typing indicator
    conversation = run.conversation
    return unless conversation

    # Notify user of the timeout with a toast
    ConversationChannel.broadcast_run_failed(
      conversation,
      code: "stale_timeout",
      user_message: user_message
    )

    # Clear typing indicator
    if run.speaker_space_membership_id
      ConversationChannel.broadcast_stream_complete(
        conversation,
        space_membership_id: run.speaker_space_membership_id
      )
    end
  end
end
