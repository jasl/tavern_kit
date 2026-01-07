# frozen_string_literal: true

# Generates the LLM response for a run (streaming or non-streaming).
#
# Responsibilities:
# - Provider + generation settings resolution
# - Cancel polling + heartbeat touches
# - Streaming chunks to typing indicator
#
class Conversations::RunExecutor::RunGeneration
  attr_reader :llm_client

  def initialize(run:, conversation:, speaker:)
    @run = run
    @conversation = conversation
    @speaker = speaker
  end

  # Snapshot of generation parameters stored in message/run metadata.
  #
  # @return [Hash]
  def generation_params_snapshot
    provider = effective_llm_provider
    generation = effective_generation_settings

    {
      provider_name: provider&.name,
      provider_identification: provider&.identification,
      model: provider&.model,
      max_response_tokens: max_response_tokens,
      streaming: streaming_enabled?,
    }.merge(generation.slice("temperature", "top_k", "top_p", "min_p", "repetition_penalty"))
  end

  # Generate response content, streaming to typing indicator.
  #
  # @param prompt_messages [Array] the prompt messages
  # @return [String] the generated content
  def generate_response(prompt_messages)
    @llm_client = LLMClient.new(provider: effective_llm_provider)
    raise Conversations::RunExecutor::Canceled if cancel_requested?(force: true)

    # Build generation parameters
    gen_params = {
      messages: prompt_messages,
      max_tokens: max_response_tokens,
      temperature: generation_temperature,
      top_p: generation_top_p,
      top_k: generation_top_k,
      repetition_penalty: generation_repetition_penalty,
      request_logprobs: true,
    }.compact

    if @llm_client.provider&.streamable? && streaming_enabled?
      full = +""
      @llm_client.chat(**gen_params) do |chunk|
        raise Conversations::RunExecutor::Canceled if cancel_requested?

        touch_run_heartbeat!
        full << chunk

        # Stream to typing indicator (not to a message bubble)
        ConversationChannel.broadcast_stream_chunk(@conversation, content: full, space_membership_id: @speaker.id)
      end

      raise Conversations::RunExecutor::Canceled if cancel_requested?(force: true)
      full
    else
      out = @llm_client.chat(**gen_params)
      raise Conversations::RunExecutor::Canceled if cancel_requested?(force: true)
      out
    end
  end

  private

  attr_reader :run, :conversation, :speaker

  def effective_llm_provider
    speaker&.effective_llm_provider || LLMProvider.get_default
  end

  def llm_settings
    speaker&.llm_settings || {}
  end

  def streaming_enabled?
    generation = effective_generation_settings

    if generation.key?("stream")
      generation["stream"] != false
    else
      llm_settings.dig("output", "streaming") != false
    end
  end

  def max_response_tokens
    generation = effective_generation_settings
    value = generation["max_response_tokens"] || llm_settings.dig("output", "max_response_tokens")
    value = value.to_i if value.present?
    value = nil if value.present? && value <= 0
    value
  end

  def generation_temperature
    generation = effective_generation_settings
    value = generation["temperature"]
    return nil if value.nil?

    value.to_f
  end

  def generation_top_p
    generation = effective_generation_settings
    value = generation["top_p"]
    return nil if value.nil?

    value.to_f
  end

  def generation_top_k
    generation = effective_generation_settings
    value = generation["top_k"]
    return nil if value.nil?

    value.to_i
  end

  def generation_repetition_penalty
    generation = effective_generation_settings
    value = generation["repetition_penalty"]
    return nil if value.nil?

    value.to_f
  end

  def effective_generation_settings
    provider_id = speaker&.provider_identification
    provider_settings = provider_id.present? ? llm_settings.dig("providers", provider_id) : nil
    provider_settings ||= {}
    provider_settings.fetch("generation", {})
  end

  def cancel_requested?(force: false)
    return true if @cancel_requested_cached

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    unless force
      interval = Conversations::RunExecutor::CANCEL_POLL_INTERVAL_SECONDS
      if @last_cancel_poll_monotonic && (now - @last_cancel_poll_monotonic) < interval
        return false
      end
    end

    @last_cancel_poll_monotonic = now
    @cancel_requested_cached = ConversationRun.where(id: run.id).pick(:cancel_requested_at).present?
  end

  def touch_run_heartbeat!(force: false)
    return unless run

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    unless force
      interval = Conversations::RunExecutor::HEARTBEAT_INTERVAL_SECONDS
      if @last_heartbeat_touch_monotonic && (now - @last_heartbeat_touch_monotonic) < interval
        return
      end
    end

    @last_heartbeat_touch_monotonic = now

    ts = Time.current
    run.update_columns(heartbeat_at: ts, updated_at: ts)
  end
end
