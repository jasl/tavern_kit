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

  attr_reader :provider, :last_usage, :last_logprobs

  # Initialize the LLM client.
  # Loads the current active provider from the database.
  #
  # @param provider [LLMProvider, nil] optional provider override
  def initialize(provider: nil)
    @provider = provider || LLMProvider.get_default
    @last_usage = nil
    @last_logprobs = nil
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
  # @param request_logprobs [Boolean] whether to request logprobs (only if provider supports it)
  # @param block [Proc, nil] if provided, streams tokens to the block
  # @return [String] the complete response content (for non-streaming or after streaming completes)
  def chat(messages:, model: nil, max_tokens: nil, temperature: nil, top_p: nil, top_k: nil, repetition_penalty: nil, request_logprobs: false, &block)
    raise NoProviderError, "No LLM provider configured" unless @provider
    raise ArgumentError, "Messages are required" if messages.blank?

    use_model = model || @provider.model
    raise ModelMissingError, "Model is required" if use_model.blank?

    # Only request logprobs if caller requests AND provider supports it
    should_request_logprobs = request_logprobs && @provider.supports_logprobs?

    generation_params = {
      max_tokens: max_tokens,
      temperature: temperature,
      top_p: top_p,
      top_k: top_k,
      repetition_penalty: repetition_penalty,
    }.compact

    result =
      if @provider.streamable? && block_given?
        client.chat(
          model: use_model,
          messages: messages,
          stream: true,
          include_usage: true,
          request_logprobs: should_request_logprobs,
          **generation_params,
          &block
        )
      else
        client.chat(
          model: use_model,
          messages: messages,
          stream: false,
          request_logprobs: should_request_logprobs,
          **generation_params
        )
      end

    @last_usage = result.usage
    @last_logprobs = result.logprobs

    result.content.to_s
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

    models = client.models

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

    result = client.chat(model: model, messages: messages, stream: streamable, max_tokens: 50)
    content = result.content.to_s

    { success: true, response: content }
  rescue SimpleInference::Errors::HTTPError => e
    { success: false, error: "HTTP #{e.status}: #{e.message}" }
  rescue SimpleInference::Errors::ConnectionError => e
    { success: false, error: "Connection failed: #{e.message}" }
  rescue SimpleInference::Errors::TimeoutError => e
    { success: false, error: "Request timed out: #{e.message}" }
  end

  private

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
