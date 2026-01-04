# frozen_string_literal: true

# Service for interacting with OpenAI-compatible LLM APIs using simple_inference.
#
# This class wraps SimpleInference::Client and manages configuration from
# the LLMProvider model.
#
# @example Basic usage with non-streaming
#   client = LLMClient.new
#   response = client.chat(messages: [{ role: "user", content: "Hello!" }])
#   puts response # => "Hello! How can I help you today?"
#
# @example Streaming usage
#   client = LLMClient.new
#   client.chat(messages: [{ role: "user", content: "Hello!" }]) do |chunk|
#     print chunk # Prints each token as it arrives
#   end
#
# @example Test connection
#   result = LLMClient.test_connection_with(
#     base_url: "https://api.openai.com/v1",
#     api_key: "sk-...",
#     model: "gpt-4o",
#     streamable: true
#   )
#   puts result[:response] if result[:success]
#
class LLMClient
  class Error < StandardError; end
  class NoProviderError < Error; end
  class ModelMissingError < Error; end

  attr_reader :provider, :last_usage

  # Initialize the LLM client.
  # Loads the current active provider from the database.
  #
  # @param provider [LLMProvider, nil] optional provider override
  def initialize(provider: nil)
    @provider = provider || LLMProvider.get_default
    @last_usage = nil
  end

  # Get the underlying SimpleInference client.
  #
  # @return [SimpleInference::Client] configured client instance
  def client
    @client ||= build_client
  end

  # Send a chat completion request.
  # Automatically uses streaming or non-streaming based on provider settings.
  #
  # @param messages [Array<Hash>] array of message hashes with :role and :content
  # @param model [String, nil] model override (defaults to provider's model)
  # @param max_tokens [Integer, nil] maximum tokens in response
  # @param temperature [Float, nil] sampling temperature (0-2)
  # @param top_p [Float, nil] nucleus sampling threshold (0-1)
  # @param top_k [Integer, nil] top-k sampling limit (0 = disabled)
  # @param repetition_penalty [Float, nil] penalty for repeated tokens (1-2)
  # @param block [Proc, nil] if provided, streams tokens to the block
  # @return [String] the complete response content (for non-streaming or after streaming completes)
  def chat(messages:, model: nil, max_tokens: nil, temperature: nil, top_p: nil, top_k: nil, repetition_penalty: nil, &block)
    raise NoProviderError, "No LLM provider configured" unless @provider
    raise ArgumentError, "Messages are required" if messages.blank?

    use_model = model || @provider.model
    raise ModelMissingError, "Model is required" if use_model.blank?

    generation_params = {
      temperature: temperature,
      top_p: top_p,
      top_k: top_k,
      repetition_penalty: repetition_penalty,
    }.compact

    if @provider.streamable? && block_given?
      chat_streaming(messages: messages, model: use_model, max_tokens: max_tokens, **generation_params, &block)
    else
      chat_non_streaming(messages: messages, model: use_model, max_tokens: max_tokens, **generation_params)
    end
  end

  # Fetch available models from the API (may not be supported by all providers).
  #
  # @param base_url [String] API base URL
  # @param api_key [String, nil] API key
  # @return [Hash] result with :success, :models (on success), or :error (on failure)
  def self.fetch_models_with(base_url:, api_key: nil)
    client = SimpleInference::Client.new(
      base_url: base_url,
      api_key: api_key,
      api_prefix: nil,
      timeout: 30,
      read_timeout: 30,
    )

    response = client.list_models
    models = response[:body]["data"]&.map { |m| m["id"] } || []

    { success: true, models: models }
  rescue SimpleInference::Errors::HTTPError => e
    { success: false, error: "HTTP #{e.status}: #{e.message}" }
  rescue SimpleInference::Errors::ConnectionError => e
    { success: false, error: "Connection failed: #{e.message}" }
  rescue SimpleInference::Errors::TimeoutError => e
    { success: false, error: "Request timed out: #{e.message}" }
  end

  # Test connection by sending a greeting message to the API.
  # Uses streaming or non-streaming based on the streamable parameter.
  #
  # @param base_url [String] API base URL
  # @param api_key [String, nil] API key
  # @param model [String] model identifier to use
  # @param streamable [Boolean] whether to use streaming API (default: true)
  # @return [Hash] result with :success, :response (on success), or :error (on failure)
  def self.test_connection_with(base_url:, api_key: nil, model: nil, streamable: true)
    raise ArgumentError, "Model is required for connection test" if model.blank?

    client = SimpleInference::Client.new(
      base_url: base_url,
      api_key: api_key,
      api_prefix: nil,
      timeout: 30,
      read_timeout: 60,
    )

    messages = [{ role: "user", content: "Hello! Please respond with a brief greeting." }]

    content = if streamable
                # Test streaming API
                chunks = []
                client.chat_completions_stream(model: model, messages: messages, max_tokens: 50) do |chunk|
                  delta = chunk.dig("choices", 0, "delta", "content")
                  chunks << delta if delta
                end
                chunks.join
    else
                # Test non-streaming API
                response = client.chat_completions(model: model, messages: messages, max_tokens: 50)
                response.dig(:body, "choices", 0, "message", "content")
    end

    { success: true, response: content }
  rescue SimpleInference::Errors::HTTPError => e
    { success: false, error: "HTTP #{e.status}: #{e.message}" }
  rescue SimpleInference::Errors::ConnectionError => e
    { success: false, error: "Connection failed: #{e.message}" }
  rescue SimpleInference::Errors::TimeoutError => e
    { success: false, error: "Request timed out: #{e.message}" }
  end

  # Get the current provider name.
  #
  # @return [String, nil] provider name
  def provider_name
    @provider&.name
  end

  private

  # Send a non-streaming chat completion request.
  #
  # @param messages [Array<Hash>] messages
  # @param model [String] model to use
  # @param max_tokens [Integer, nil] max tokens
  # @param temperature [Float, nil] sampling temperature
  # @param top_p [Float, nil] nucleus sampling threshold
  # @param top_k [Integer, nil] top-k sampling limit
  # @param repetition_penalty [Float, nil] repetition penalty
  # @return [String] response content
  def chat_non_streaming(messages:, model:, max_tokens: nil, temperature: nil, top_p: nil, top_k: nil, repetition_penalty: nil)
    params = { model: model, messages: messages }
    params[:max_tokens] = max_tokens if max_tokens
    params[:temperature] = temperature if temperature
    params[:top_p] = top_p if top_p
    # top_k and repetition_penalty are provider-specific, pass if supported
    params[:top_k] = top_k if top_k && top_k.positive?
    params[:repetition_penalty] = repetition_penalty if repetition_penalty && repetition_penalty != 1.0

    response = client.chat_completions(**params)
    body = response[:body]

    # Capture usage data if available
    @last_usage = extract_usage(body)

    body.dig("choices", 0, "message", "content") || ""
  end

  # Send a streaming chat completion request.
  #
  # @param messages [Array<Hash>] messages
  # @param model [String] model to use
  # @param max_tokens [Integer, nil] max tokens
  # @param temperature [Float, nil] sampling temperature
  # @param top_p [Float, nil] nucleus sampling threshold
  # @param top_k [Integer, nil] top-k sampling limit
  # @param repetition_penalty [Float, nil] repetition penalty
  # @param block [Proc] block to receive each chunk
  # @return [String] complete response content
  def chat_streaming(messages:, model:, max_tokens: nil, temperature: nil, top_p: nil, top_k: nil, repetition_penalty: nil, &block)
    params = { model: model, messages: messages }
    params[:max_tokens] = max_tokens if max_tokens
    params[:temperature] = temperature if temperature
    params[:top_p] = top_p if top_p
    # top_k and repetition_penalty are provider-specific, pass if supported
    params[:top_k] = top_k if top_k && top_k.positive?
    params[:repetition_penalty] = repetition_penalty if repetition_penalty && repetition_penalty != 1.0
    # Request usage data in streaming mode (OpenAI-compatible APIs)
    params[:stream_options] = { include_usage: true }

    full_content = +""
    @last_usage = nil

    client.chat_completions_stream(**params) do |chunk|
      delta = chunk.dig("choices", 0, "delta", "content")
      if delta
        full_content << delta
        block.call(delta)
      end

      # Some providers send usage in the final chunk when stream_options.include_usage is true
      if chunk["usage"]
        @last_usage = extract_usage(chunk)
      end
    end

    full_content
  end

  # Extract usage data from API response.
  #
  # @param body [Hash] response body
  # @return [Hash, nil] usage data
  def extract_usage(body)
    usage = body["usage"]
    return nil unless usage

    {
      prompt_tokens: usage["prompt_tokens"],
      completion_tokens: usage["completion_tokens"],
      total_tokens: usage["total_tokens"],
    }.compact
  end

  # Default timeout values (in seconds)
  DEFAULT_TIMEOUT = 30
  DEFAULT_READ_TIMEOUT = 60

  # Build the SimpleInference client with current provider settings.
  #
  # @return [SimpleInference::Client] configured client
  def build_client
    raise "No LLM provider configured" unless @provider

    SimpleInference::Client.new(
      base_url: @provider.base_url,
      api_key: @provider.api_key,
      api_prefix: nil, # Already included in base_url
      timeout: DEFAULT_TIMEOUT,
      read_timeout: DEFAULT_READ_TIMEOUT,
    )
  end
end
