# frozen_string_literal: true

# Job to handle human turn timeout in auto mode.
#
# When a human_turn run is created, this job is scheduled with a delay.
# If the human hasn't sent a message by the time this job runs, the
# run is marked as skipped and the scheduler advances to the next speaker.
#
# ## Idempotency
#
# The job validates that:
# - The run still exists
# - The run is still queued (not already succeeded/skipped)
# - The conversation's auto mode is still active
# - The round_id matches (prevents stale jobs from affecting new rounds)
#
# ## Concurrency Safety
#
# Uses conversation.with_lock to ensure atomic state transitions and
# prevent race conditions with concurrent user messages.
#
class HumanTurnTimeoutJob < ApplicationJob
  queue_as :default

  def perform(run_id, round_id = nil)
    run = ConversationRun.find_by(id: run_id)
    return unless run

    # Only process human_turn runs
    return unless run.human_turn?

    conversation = run.conversation
    return unless conversation

    # Get round_id from run's debug info if not provided
    round_id ||= run.debug&.dig("round_id")
    membership_id = run.speaker_space_membership_id

    # Use with_lock to ensure atomic state check and transition
    # This prevents race conditions with concurrent user messages
    skipped = false
    conversation.with_lock do
      # Re-check conditions inside lock (they may have changed)
      run.reload
      return unless run.queued?
      return unless conversation.auto_mode_enabled?
      return unless conversation.current_round_id == round_id

      # Mark as skipped inside the lock
      run.skipped!(debug: run.debug.merge(
        "skipped_reason" => "timeout",
        "skipped_at" => Time.current.iso8601
      ))

      # Note: TurnScheduler.skip_human_turn! also uses with_lock internally,
      # but since we're already in a lock, it will use the same transaction.
      # The preconditions are checked again inside skip_human_turn! for safety.
      skipped = TurnScheduler.skip_human_turn!(conversation, membership_id, round_id)
    end

    Rails.logger.info "[HumanTurnTimeoutJob] Skip result for run #{run_id}: #{skipped}"
  rescue StandardError => e
    Rails.logger.error "[HumanTurnTimeoutJob] Error processing run #{run_id}: #{e.message}"
    raise
  end
end
