# frozen_string_literal: true

module Playgrounds
  # Controller for previewing prompts before sending.
  #
  # This allows users to see the complete prompt that will be sent to the LLM,
  # including system prompts, character cards, chat history, and their message.
  class PromptPreviewsController < Playgrounds::ApplicationController
    # POST /playgrounds/:playground_id/prompt_preview
    #
    # Returns the rendered prompt preview modal content.
    def create
      content = params[:content].to_s.strip
      content = nil if content.empty?

      # Find speaker (AI character that would respond)
      speaker = @playground.space_memberships.participating.ai_characters.by_position.first

      unless speaker
        render partial: "playgrounds/prompt_previews/error",
               locals: { error: t("prompt_preview.no_speaker", default: "No AI character in playground") },
               status: :unprocessable_entity
        return
      end

      # Get the primary conversation (root)
      conversation = @playground.conversations.root.first

      unless conversation
        render partial: "playgrounds/prompt_previews/error",
               locals: { error: t("prompt_preview.no_conversation", default: "No conversation in playground") },
               status: :unprocessable_entity
        return
      end

      # Build prompt using PromptBuilder service
      begin
        builder = PromptBuilder.new(
          conversation,
          user_message: content,
          speaker: speaker
        )

        @messages = builder.to_messages
        @token_count = estimate_token_count(@messages)
        @tokenized_messages = tokenize_messages(@messages)
        @generation_params = build_generation_params(speaker)

        render partial: "playgrounds/prompt_previews/preview",
               locals: {
                 messages: @messages,
                 token_count: @token_count,
                 tokenized_messages: @tokenized_messages,
                 generation_params: @generation_params,
               }
      rescue PromptBuilder::PromptBuilderError => e
        render partial: "playgrounds/prompt_previews/error",
               locals: { error: e.message },
               status: :unprocessable_entity
      rescue StandardError => e
        Rails.logger.error "PromptPreview error: #{e.message}"
        render partial: "playgrounds/prompt_previews/error",
               locals: { error: "Failed to build prompt preview" },
               status: :unprocessable_entity
      end
    end

    private

    # Estimate token count for the messages.
    #
    # @param messages [Array<Hash>] the prompt messages
    # @return [Integer] estimated token count
    def estimate_token_count(messages)
      text = messages.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n")
      TavernKit::TokenEstimator.default.estimate(text)
    end

    # Tokenize each message content for the Token Inspector view.
    #
    # @param messages [Array<Hash>] the prompt messages
    # @return [Array<Hash>] messages with tokenized content
    def tokenize_messages(messages)
      estimator = TavernKit::TokenEstimator.default
      messages.map do |msg|
        {
          role: msg[:role],
          name: msg[:name],
          tokens: estimator.tokenize(msg[:content].to_s),
        }
      end
    end

    # Build generation parameters snapshot for the Parameters tab.
    # This mirrors the logic in Conversations::RunExecutor.
    #
    # @param speaker [SpaceMembership] the AI speaker membership
    # @return [Hash] generation parameters
    def build_generation_params(speaker)
      provider = speaker.effective_llm_provider
      llm_settings = speaker.llm_settings
      provider_id = speaker.provider_identification
      provider_settings = provider_id.present? ? llm_settings.dig("providers", provider_id) : nil
      provider_settings ||= {}
      generation = provider_settings.fetch("generation", {})

      # Get preset info
      preset = speaker.preset || Preset.get_default

      {
        # Provider info
        provider_name: provider&.name,
        provider_type: provider&.identification,
        model: provider&.model,
        base_url: provider&.base_url,

        # Preset info
        preset_name: preset&.name,
        preset_id: preset&.id,

        # Generation settings
        max_context_tokens: generation["max_context_tokens"],
        max_response_tokens: generation["max_response_tokens"],
        temperature: generation["temperature"],
        top_p: generation["top_p"],
        top_k: generation["top_k"],
        repetition_penalty: generation["repetition_penalty"],
        streaming: llm_settings.dig("output", "streaming") != false,
      }
    end
  end
end
