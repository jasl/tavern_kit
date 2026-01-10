# frozen_string_literal: true

# Tracks a human's turn in auto mode.
#
# Unlike other run types, this does NOT call the LLM. It's a placeholder
# that tracks the state of a human's turn when auto mode is active.
#
# ## Lifecycle
#
# 1. Scheduler creates HumanTurn when human's turn comes up in auto mode
# 2. A timeout job is scheduled (HumanTurnTimeoutJob)
# 3. If human sends a message before timeout:
#    - Message#after_create_commit marks run as succeeded
#    - Scheduler advances to next speaker
# 4. If timeout expires without human message:
#    - Job marks run as skipped
#    - Scheduler advances to next speaker
#
# ## Visibility
#
# Hidden by default in UI (shown only when skipped for debugging).
#
class ConversationRun::HumanTurn < ConversationRun
  # Do NOT execute via RunExecutor - this is a tracking record only
  def should_execute?
    false
  end

  # Hidden by default, shown when skipped
  def visible_in_ui?
    skipped?
  end

  # Override to clarify this is not an AI response
  def ai_response?
    false
  end

  # Create a HumanTurn run for tracking.
  #
  # @param conversation [Conversation] the conversation
  # @param speaker [SpaceMembership] the human speaker
  # @param timeout_seconds [Integer] how long to wait before skipping
  # @param round_id [String] the round ID for validation in timeout job
  # @return [ConversationRun::HumanTurn]
  def self.create_for_human!(conversation:, speaker:, timeout_seconds:, round_id: nil)
    run = create!(
      conversation: conversation,
      speaker_space_membership: speaker,
      status: "queued",
      reason: "human_turn",
      run_after: nil, # No run_after for human turns - they don't execute
      debug: {
        timeout_seconds: timeout_seconds,
        human_turn: true,
        round_id: round_id,
        expected_last_message_id: conversation.messages.maximum(:id),
      }
    )

    # Schedule timeout check
    HumanTurnTimeoutJob.set(wait: timeout_seconds.seconds).perform_later(run.id)

    run
  end

  # Mark as succeeded when human sends their message.
  #
  # @param message [Message] the message the human sent
  # @return [void]
  def complete_with_message!(message)
    return unless queued?

    succeeded!(
      debug: debug.merge(
        "completed_by_message_id" => message.id,
        "completed_at" => Time.current.iso8601
      )
    )
  end

  # Skip this turn due to timeout.
  #
  # @return [void]
  def skip_due_to_timeout!
    return unless queued?

    skipped!(
      debug: debug.merge(
        "skip_reason" => "timeout",
        "skipped_at" => Time.current.iso8601
      )
    )
  end
end
