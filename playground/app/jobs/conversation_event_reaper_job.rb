# frozen_string_literal: true

# Reaps old ConversationEvents to enforce retention.
class ConversationEventReaperJob < ApplicationJob
  queue_as :default

  RETENTION = 24.hours

  def perform(retention: RETENTION)
    threshold = Time.current - retention

    ConversationEvent
      .before(threshold)
      .in_batches(of: 10_000)
      .delete_all
  end
end
