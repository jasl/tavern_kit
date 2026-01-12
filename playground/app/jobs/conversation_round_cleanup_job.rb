# frozen_string_literal: true

# Periodic job to clean up old ConversationRound records.
#
# Motivation:
# - Rounds are a runtime concept, but we intentionally keep records for a short
#   time to aid debugging and to support stale protection during queue policy
#   races (late messages / late run completions).
# - To prevent unbounded growth, we keep rounds only for a limited retention
#   window and then delete them.
#
# Important:
# - We never delete active rounds.
# - Deleting a round will nullify ConversationRun.conversation_round_id via
#   FK (on_delete: :nullify), so runs/messages are not hard-dependent on rounds.
#
class ConversationRoundCleanupJob < ApplicationJob
  queue_as :default

  # @param retention_hours [Integer] how long to keep finished rounds (default 24)
  # @param batch_size [Integer] max rows to delete per batch (default 1000)
  # @param sleep_between_batches [Float] optional sleep to reduce DB pressure (default 0.1)
  def perform(retention_hours: 24, batch_size: 1000, sleep_between_batches: 0.1)
    retention_hours = retention_hours.to_i
    batch_size = batch_size.to_i

    cutoff = retention_hours.hours.ago
    total_deleted = 0

    loop do
      ids = deletable_round_ids(cutoff: cutoff, limit: batch_size)
      break if ids.empty?

      deleted = ConversationRound.where(id: ids).delete_all
      total_deleted += deleted

      sleep sleep_between_batches.to_f if sleep_between_batches.to_f.positive?
    end

    Rails.logger.info("[ConversationRoundCleanupJob] Deleted #{total_deleted} rounds older than #{retention_hours}h")
  end

  private

  def deletable_round_ids(cutoff:, limit:)
    active_round_ids =
      ConversationRun
        .active
        .where.not(conversation_round_id: nil)
        .select(:conversation_round_id)

    ConversationRound
      .where.not(status: "active")
      .where("finished_at < ?", cutoff)
      .where.not(id: active_round_ids)
      .order(finished_at: :asc, id: :asc)
      .limit(limit)
      .pluck(:id)
  end
end
