# frozen_string_literal: true

# Reaps stale running ConversationRuns that have timed out.
#
# Uses optimistic concurrency with conditional UPDATE to atomically
# transition stale running runs to failed status without pessimistic locking.
#
class ConversationRunReaperJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(run_id)
    now = Time.current

    # Load the run to check preconditions
    run = ConversationRun.find_by(id: run_id)
    return unless run
    return unless run.running?
    return unless run.stale?(now: now)

    # Atomic conditional update: only fail if still running and stale
    stale_threshold = now - ConversationRun::STALE_TIMEOUT

    # Build the error hash - will be serialized as JSONB by ActiveRecord
    error_data = {
      "code" => "stale_running_run",
      "message" => "Run became stale while running",
      "stale_timeout_seconds" => ConversationRun::STALE_TIMEOUT.to_i,
      "heartbeat_at" => run.heartbeat_at&.iso8601,
    }

    updated_count = ConversationRun
      .where(id: run_id, status: "running")
      .where("heartbeat_at < ?", stale_threshold)
      .update_all(
        status: "failed",
        finished_at: now,
        cancel_requested_at: now,
        error: error_data,
        updated_at: now
      )

    return if updated_count == 0

    # Reload to get updated state
    run.reload

    user_message = I18n.t(
      "messages.generation_errors.stale_running_run",
      default: "Generation timed out. Please try again."
    )

    finalize_placeholder_messages!(run, user_message: user_message, at: now)

    queued = ConversationRun.queued.find_by(conversation_id: run.conversation_id)
    Conversations::RunPlanner.kick!(queued) if queued
  end

  private

  def finalize_placeholder_messages!(run, user_message:, at:)
    # Clean up any messages stuck in "generating" status from the stale run.
    run
      .messages
      .where(generation_status: "generating")
      .find_each do |message|
        message.update!(
          generation_status: "failed",
          content: message.content.presence || user_message,
          metadata: (message.metadata || {}).merge("error" => user_message),
          updated_at: at
        )
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
