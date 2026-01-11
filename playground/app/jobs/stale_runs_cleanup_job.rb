# frozen_string_literal: true

# Periodic job to clean up stale ConversationRuns.
#
# Runs that have been in "running" status without a heartbeat for too long
# are marked as failed and their conversations' schedulers are notified to
# continue processing.
#
# ## Why This Exists
#
# ConversationRuns can get stuck in "running" status if:
# - The worker process crashes during LLM generation
# - The LLM provider hangs indefinitely
# - Network issues prevent response/heartbeat updates
#
# This job provides a safety net to prevent conversations from getting
# permanently stuck.
#
# ## Schedule
#
# Configured via config/recurring.yml to run every minute.
#
class StaleRunsCleanupJob < ApplicationJob
  queue_as :default

  # Shorter threshold than STALE_TIMEOUT for more aggressive cleanup
  HEARTBEAT_THRESHOLD = 30.seconds

  def perform
    stale_runs = ConversationRun
      .running
      .where("heartbeat_at < ? OR (heartbeat_at IS NULL AND started_at < ?)",
             HEARTBEAT_THRESHOLD.ago,
             HEARTBEAT_THRESHOLD.ago)

    count = 0

    stale_runs.find_each do |run|
      Rails.logger.info "[StaleRunsCleanupJob] Cleaning up stale run #{run.id} " \
                        "(last heartbeat: #{run.heartbeat_at}, started: #{run.started_at})"

      # Mark as failed
      run.failed!(
        error: {
          "code" => "stale_timeout",
          "message" => "Run exceeded heartbeat threshold of #{HEARTBEAT_THRESHOLD.inspect}",
          "last_heartbeat_at" => run.heartbeat_at&.iso8601,
          "started_at" => run.started_at&.iso8601,
          "cleaned_up_at" => Time.current.iso8601,
        }
      )

      # Notify scheduler to continue
      if run.conversation
        TurnScheduler::Commands::ScheduleSpeaker.call(conversation: run.conversation)
      end

      count += 1
    rescue StandardError => e
      Rails.logger.error "[StaleRunsCleanupJob] Error cleaning up run #{run.id}: #{e.message}"
      # Continue with other runs
    end

    Rails.logger.info "[StaleRunsCleanupJob] Cleaned up #{count} stale runs" if count > 0
  end
end
