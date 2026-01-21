# frozen_string_literal: true

# Service for generating Auto suggestion candidates.
#
# Designed to work with individual jobs - each candidate is generated
# by a separate AutoCandidateJob, allowing SolidQueue to parallelize
# them using the llm queue's thread pool.
#
# Frontend tracks completion by counting received candidates, so no
# server-side coordination is needed.
#
# @example Generate 3 candidates (called from 3 separate jobs)
#   Conversations::AutoCandidateGenerator.generate_single(
#     conversation: conv, participant: membership,
#     generation_id: "abc-123", index: 0
#   )
#
class Conversations::AutoCandidateGenerator
  class << self
    # Generate a single candidate and broadcast it.
    #
    # @param conversation [Conversation]
    # @param participant [SpaceMembership]
    # @param generation_id [String] unique ID for this batch
    # @param index [Integer] candidate index (0-based)
    def generate_single(conversation:, participant:, generation_id:, index:)
      new(
        conversation: conversation,
        participant: participant,
        generation_id: generation_id,
        index: index
      ).generate_single
    end
  end

  def initialize(conversation:, participant:, generation_id:, index:)
    @conversation = conversation
    @participant = participant
    @generation_id = generation_id
    @index = index
  end

  def generate_single
    context_error = context_error_message
    if context_error
      broadcast_error(context_error)
      return
    end

    generate_and_broadcast_candidate
  rescue PromptBuilder::PromptBuilderError => e
    log_error("Prompt build failed", e)
    broadcast_error(e.message)
  rescue SimpleInference::Errors::HTTPError => e
    log_error("API error", e)
    broadcast_error("API error: #{e.message}")
  rescue SimpleInference::Errors::TimeoutError => e
    log_error("Timeout", e)
    broadcast_error("Request timed out")
  rescue SimpleInference::Errors::ConnectionError => e
    log_error("Connection error", e)
    broadcast_error("Connection failed: #{e.message}")
  rescue StandardError => e
    # Catch-all: frontend tracks completion by counting candidates, so any
    # unexpected failure must broadcast an error to avoid a stuck "Generating..."
    log_error("Unexpected error", e)
    broadcast_error("Generation failed: #{e.message}")
  end

  private

  attr_reader :conversation, :participant, :generation_id, :index

  def context_error_message
    return "Generation canceled: space is inactive." unless conversation&.space&.active?

    unless participant&.user? && participant&.auto_capable?
      return "Generation canceled: Auto suggestions are no longer available."
    end

    return "Generation canceled: Auto is active." if participant.auto_enabled?

    nil
  end

  def generate_and_broadcast_candidate
    messages = build_messages
    client = build_client

    unless client.provider
      broadcast_error("No LLM provider configured")
      return
    end

    content = client.chat(messages: messages, max_tokens: max_response_tokens)
    content = content.to_s.strip

    # Record token usage to conversation/space statistics
    record_token_usage(client.last_usage)

    Messages::Broadcasts.broadcast_auto_candidate(
      participant,
      generation_id: generation_id,
      index: index,
      text: content
    )
  end

  def build_messages
    PromptBuilder.new(conversation, speaker: participant).to_messages
  end

  def build_client
    LLMClient.new(provider: effective_llm_provider)
  end

  def broadcast_error(error_message)
    Messages::Broadcasts.broadcast_auto_candidate_error(
      participant,
      generation_id: generation_id,
      error: error_message
    )
  end

  def log_error(context, error)
    Rails.logger.error "[AutoCandidateGenerator] #{context} for candidate #{index}: #{error.class}: #{error.message}"
  end

  def record_token_usage(usage)
    return unless usage

    TokenUsageRecorder.execute(conversation: conversation, usage: usage)
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
