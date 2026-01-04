# frozen_string_literal: true

class ConversationRunJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(run_id)
    Conversation::RunExecutor.execute!(run_id)
  end
end
