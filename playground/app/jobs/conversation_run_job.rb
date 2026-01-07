# frozen_string_literal: true

class ConversationRunJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(run_id)
    Conversations::RunExecutor.execute!(run_id)
  end
end
