# frozen_string_literal: true

class ConversationRunJob < ApplicationJob
  queue_as :llm

  discard_on ActiveRecord::RecordNotFound

  def perform(run_id)
    Conversations::RunExecutor.execute!(run_id)
  end
end
