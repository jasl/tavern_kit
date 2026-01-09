# frozen_string_literal: true

# Service for generating copilot candidate replies (suggestions).
#
# Extracted from CopilotCandidateJob to keep jobs thin and to make the
# generation/broadcast flow easier to test.
#
class Conversations::CopilotCandidateGenerator
  MAX_CANDIDATES = 4

  def initialize(conversation:, participant:, generation_id:, candidate_count: 1)
    @conversation = conversation
    @participant = participant
    @generation_id = generation_id
    @candidate_count = candidate_count
  end

  def call
    return unless conversation.space.active?
    return unless participant.user? && participant.character?
    return if participant.copilot_full?

    builder = PromptBuilder.new(conversation, speaker: participant)
    messages = builder.to_messages

    client = LLMClient.new(provider: effective_llm_provider)
    unless client.provider
      broadcast_error("No LLM provider configured")
      return
    end

    candidate_count.times do |index|
      generate_single_candidate(client, messages, index)
    end

    broadcast_complete
  rescue PromptBuilder::PromptBuilderError => e
    Rails.logger.error "[Conversations::CopilotCandidateGenerator] Prompt build failed: #{e.message}"
    broadcast_error(e.message)
  rescue SimpleInference::Errors::HTTPError => e
    Rails.logger.error "[Conversations::CopilotCandidateGenerator] API error: #{e.message}"
    broadcast_error("API error: #{e.message}")
  rescue SimpleInference::Errors::TimeoutError => e
    Rails.logger.error "[Conversations::CopilotCandidateGenerator] Timeout error: #{e.message}"
    broadcast_error("Request timed out")
  rescue SimpleInference::Errors::ConnectionError => e
    Rails.logger.error "[Conversations::CopilotCandidateGenerator] Connection error: #{e.message}"
    broadcast_error("Connection failed: #{e.message}")
  end

  private

  attr_reader :conversation, :participant, :generation_id, :candidate_count

  def candidate_count
    @candidate_count.to_i.clamp(1, MAX_CANDIDATES)
  end

  def generate_single_candidate(client, messages, index)
    content = client.chat(messages: messages, max_tokens: max_response_tokens)
    content = content.to_s.strip

    Message::Broadcasts.broadcast_copilot_candidate(
      participant,
      generation_id: generation_id,
      index: index,
      text: content
    )
  rescue StandardError => e
    Rails.logger.error "[Conversations::CopilotCandidateGenerator] Candidate #{index} failed: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
  end

  def broadcast_complete
    Message::Broadcasts.broadcast_copilot_complete(
      participant,
      generation_id: generation_id
    )
  end

  def broadcast_error(error_message)
    Message::Broadcasts.broadcast_copilot_error(
      participant,
      generation_id: generation_id,
      error: error_message
    )
  end

  def effective_llm_provider
    participant.effective_llm_provider || LLMProvider.get_default
  end

  def llm_settings
    participant.llm_settings || {}
  end

  def max_response_tokens
    generation = effective_generation_settings
    value = generation["max_response_tokens"] || llm_settings.dig("output", "max_response_tokens")
    value = value.to_i if value.present?
    value = nil if value.present? && value <= 0
    value
  end

  def effective_generation_settings
    provider_id = participant.provider_identification
    provider_settings = provider_id.present? ? llm_settings.dig("providers", provider_id) : nil
    provider_settings ||= {}

    provider_settings.fetch("generation", {})
  end
end
