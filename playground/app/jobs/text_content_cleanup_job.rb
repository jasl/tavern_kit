# frozen_string_literal: true

# Periodic job to clean up orphaned TextContent records.
#
# TextContent records become orphaned (references_count <= 0) when:
# - Messages/MessageSwipes are deleted
# - Conversations are destroyed
# - Bugs cause incorrect reference counting
#
# This job runs periodically to reclaim storage from unused content.
#
# @example Run manually
#   TextContentCleanupJob.perform_later
#
# @example Run synchronously (e.g., in console)
#   TextContentCleanupJob.perform_now
#
class TextContentCleanupJob < ApplicationJob
  queue_as :default

  # @param batch_size [Integer] records to delete per batch (default 1000)
  def perform(batch_size: 1000)
    deleted_count = TextContent.cleanup_orphans!(batch_size: batch_size)

    Rails.logger.info("[TextContentCleanupJob] Cleaned up #{deleted_count} orphaned TextContent records")
  end
end
