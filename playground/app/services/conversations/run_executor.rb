# frozen_string_literal: true

# Executes a ConversationRun by generating AI/copilot responses.
#
# New flow (no placeholder message, streaming to typing indicator):
# 1. broadcast_typing_start → Show typing indicator
# 2. generate → Stream chunks to typing indicator via ConversationChannel
# 3. create_final_message → Save message to DB after generation
# 4. broadcast_create → Append message to DOM via Turbo Streams
# 5. broadcast_typing_stop → Hide typing indicator
#
class Conversations::RunExecutor
  class Canceled < StandardError; end
  class EmptyResponse < StandardError; end

  CANCEL_POLL_INTERVAL_SECONDS = 0.2
  HEARTBEAT_INTERVAL_SECONDS = 5

  def self.execute!(run_id)
    new(run_id).execute!
  end

  def initialize(run_id)
    @run_id = run_id
  end

  def execute!
    persistence = nil

    @run = ConversationRun.find_by(id: run_id)
    return unless run

    reschedule_if_not_ready!

    @run = Conversations::RunExecutor::RunClaimer.new(run_id: run_id).claim!
    return unless run

    ConversationRunReaperJob.set(wait: ConversationRun::STALE_TIMEOUT).perform_later(run.id)

    @conversation = run.conversation
    @space = conversation.space
    @speaker = space.space_memberships.active.find_by(id: run.speaker_space_membership_id)

    persistence = Conversations::RunExecutor::RunPersistence.new(run: run, conversation: conversation, space: space, speaker: speaker)
    raise "Speaker not found" unless speaker

    # For regenerate: find target message (don't delete it)
    @target_message = find_target_message_for_regenerate if run.kind == "regenerate"

    broadcast_typing_start

    @context_builder = ContextBuilder.new(conversation, speaker: speaker)
    prompt_messages = @context_builder.build(before_message: @target_message, generation_type: prompt_generation_type)

    generation = Conversations::RunExecutor::RunGeneration.new(run: run, conversation: conversation, speaker: speaker)
    generation_params_snapshot = generation.generation_params_snapshot

    # Persist debug data to run record for debugging LLM issues
    persistence.persist_debug_data!(
      prompt_messages,
      generation_params_snapshot: generation_params_snapshot,
      target_message: @target_message
    )

    # Check and persist World Info budget overflow status
    persistence.persist_lore_budget_status!(context_builder: @context_builder)

    # Generate response (streaming to typing indicator, no placeholder message)
    content = generation.generate_response(prompt_messages)
    @llm_client = generation.llm_client

    # Store logprobs in run debug data if available
    persistence.persist_logprobs!(@llm_client.last_logprobs)

    raise EmptyResponse, "LLM returned empty content" if content.to_s.strip.blank?

    # Create or add swipe to message AFTER generation completes
    @message = persistence.persist_response_message!(
      content,
      prompt_params: generation_params_snapshot,
      target_message: @target_message
    )

    persistence.finalize_success!(llm_client: @llm_client)
  rescue Canceled
    persistence&.finalize_canceled!
  rescue LLMClient::NoProviderError => e
    persistence&.finalize_failed!(
      e,
      code: "no_provider_configured",
      user_message: I18n.t(
        "messages.generation_errors.no_provider",
        default: "No LLM provider configured. Please add one in Settings."
      )
    )
  rescue ArgumentError => e
    persistence&.finalize_failed!(e, code: "context_builder_error", user_message: e.message)
  rescue SimpleInference::Errors::TimeoutError => e
    persistence&.finalize_failed!(
      e,
      code: "timeout",
      user_message: I18n.t(
        "messages.generation_errors.timeout",
        default: "The LLM request timed out. Please try again."
      )
    )
  rescue SimpleInference::Errors::ConnectionError => e
    persistence&.finalize_failed!(
      e,
      code: "connection_error",
      user_message: I18n.t(
        "messages.generation_errors.connection_error",
        default: "Network error while contacting the LLM provider. Please try again."
      )
    )
  rescue SimpleInference::Errors::HTTPError => e
    persistence&.finalize_failed!(
      e,
      code: "http_error",
      http_status: e.status,
      user_message: I18n.t(
        "messages.generation_errors.http_error",
        status: e.status,
        default: "The LLM provider returned an error (HTTP %{status})."
      )
    )
  rescue EmptyResponse => e
    persistence&.finalize_failed!(
      e,
      code: "empty_response",
      user_message: I18n.t(
        "messages.generation_errors.empty_response",
        default: "The model returned an empty response. Please try again."
      )
    )
  rescue StandardError => e
    persistence&.finalize_failed!(
      e,
      code: "unknown_error",
      user_message: I18n.t("messages.generation_errors.unknown", default: "Generation failed. Please try again.")
    )
  ensure
    broadcast_typing_stop
    Conversations::RunExecutor::RunFollowups
      .new(run: run, conversation: conversation, space: space, speaker: speaker, message: message)
      .kick_if_needed!
  end

  private

  attr_reader :run_id, :run, :conversation, :space, :speaker, :message, :target_message

  def reschedule_if_not_ready!
    return unless run&.queued?
    return if run.ready_to_run?

    Conversations::RunPlanner.kick!(run)
    @run = nil
  end

  # Find the target message for regenerate (without deleting it).
  #
  # @return [Message, nil] the target message
  def find_target_message_for_regenerate
    target_message_id = run.debug&.dig("target_message_id") || run.debug&.dig("trigger_message_id")
    return nil unless target_message_id

    conversation.messages.find_by(id: target_message_id)
  end

  def broadcast_typing_start
    return unless conversation && speaker

    ConversationChannel.broadcast_typing(conversation, membership: speaker, active: true)
  end

  def broadcast_typing_stop
    return unless conversation && speaker

    ConversationChannel.broadcast_typing(conversation, membership: speaker, active: false)
  end

  def prompt_generation_type
    return nil unless run

    case run.kind
    when "regenerate" then :regenerate
    else
      nil
    end
  end
end
