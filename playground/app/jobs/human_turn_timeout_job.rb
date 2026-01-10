# frozen_string_literal: true

# Job to handle human turn timeout in auto mode.
#
# When a HumanTurn run is created, this job is scheduled with a delay.
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
# This ensures safe behavior even with race conditions.
#
# @example Scheduled by HumanTurn.create_for_human!
#   HumanTurnTimeoutJob.set(wait: 15.seconds).perform_later(run_id)
#
class HumanTurnTimeoutJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = ConversationRun.find_by(id: run_id)
    return unless run

    # Only process HumanTurn runs
    return unless run.is_a?(ConversationRun::HumanTurn)

    # Only skip if still queued
    return unless run.queued?

    conversation = run.conversation
    return unless conversation

    # Only skip if auto mode is still active
    return unless conversation.auto_mode_enabled?

    # Get round_id from run's debug info to validate against stale jobs
    round_id = run.debug&.dig("round_id")
    membership_id = run.speaker_space_membership_id

    # Mark as skipped
    run.skip_due_to_timeout!

    # Use skip_human_if_eligible! which properly advances without incrementing turns_count
    # This also validates that the round hasn't changed since the job was scheduled
    scheduler = ConversationScheduler.new(conversation)
    skipped = scheduler.skip_human_if_eligible!(membership_id, round_id)

    # If skip_human_if_eligible! returned false (round changed, etc.), just log it
    Rails.logger.info "[HumanTurnTimeoutJob] Skip result for run #{run_id}: #{skipped}"
  rescue StandardError => e
    Rails.logger.error "[HumanTurnTimeoutJob] Error processing run #{run_id}: #{e.message}"
    raise # Re-raise for job retry
  end
end
