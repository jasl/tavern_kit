# frozen_string_literal: true

module PromptBuilding
  # Semantic alias for the ActiveRecord-backed ChatHistory adapter.
  #
  # In the Rails app, "history" is stored as Message records; naming this `MessageHistory`
  # makes call sites read closer to the domain model, while still implementing
  # TavernKit's `ChatHistory` interface.
  #
  # @see PromptBuilding::ActiveRecordChatHistory
  MessageHistory = ActiveRecordChatHistory
end
