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
class Conversation::RunExecutor
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
    @run = ConversationRun.find_by(id: run_id)
    return unless run

    reschedule_if_not_ready!

    @run = claim_queued_run!
    return unless run

    ConversationRunReaperJob.set(wait: ConversationRun::STALE_TIMEOUT).perform_later(run.id)

    @conversation = run.conversation
    @space = conversation.space
    @speaker = space.space_memberships.active.find_by(id: run.speaker_space_membership_id)
    raise "Speaker not found" unless speaker

    # For regenerate: find target message (don't delete it)
    @target_message = find_target_message_for_regenerate if run.kind == "regenerate"

    broadcast_typing_start

    context_builder = ContextBuilder.new(conversation, speaker: speaker)
    prompt_messages = context_builder.build(before_message: @target_message)

    # Persist debug data to run record for debugging LLM issues
    persist_debug_data!(prompt_messages)

    # Generate response (streaming to typing indicator, no placeholder message)
    content = generate_response(prompt_messages)
    raise EmptyResponse, "LLM returned empty content" if content.to_s.strip.blank?

    # Create or add swipe to message AFTER generation completes
    @message = if @target_message
      add_swipe_to_target_message!(@target_message, content)
    else
      create_final_message(content)
    end

    finalize_success!
  rescue Canceled
    finalize_canceled!
  rescue LLMClient::NoProviderError => e
    finalize_failed!(
      e,
      code: "no_provider_configured",
      user_message: I18n.t(
        "messages.generation_errors.no_provider",
        default: "No LLM provider configured. Please add one in Settings."
      )
    )
  rescue ArgumentError => e
    finalize_failed!(e, code: "context_builder_error", user_message: e.message)
  rescue SimpleInference::Errors::TimeoutError => e
    finalize_failed!(
      e,
      code: "timeout",
      user_message: I18n.t(
        "messages.generation_errors.timeout",
        default: "The LLM request timed out. Please try again."
      )
    )
  rescue SimpleInference::Errors::ConnectionError => e
    finalize_failed!(
      e,
      code: "connection_error",
      user_message: I18n.t(
        "messages.generation_errors.connection_error",
        default: "Network error while contacting the LLM provider. Please try again."
      )
    )
  rescue SimpleInference::Errors::HTTPError => e
    finalize_failed!(
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
    finalize_failed!(
      e,
      code: "empty_response",
      user_message: I18n.t(
        "messages.generation_errors.empty_response",
        default: "The model returned an empty response. Please try again."
      )
    )
  rescue StandardError => e
    finalize_failed!(
      e,
      code: "unknown_error",
      user_message: I18n.t("messages.generation_errors.unknown", default: "Generation failed. Please try again.")
    )
  ensure
    broadcast_typing_stop
    kick_followups_if_needed
  end

  private

  attr_reader :run_id, :run, :conversation, :space, :speaker, :message, :target_message

  def reschedule_if_not_ready!
    return unless run&.queued?
    return if run.ready_to_run?

    Conversation::RunPlanner.kick!(run)
    @run = nil
  end

  def claim_queued_run!
    now = Time.current
    stale_running_run_id = nil

    claimed = ConversationRun.transaction do
      locked = ConversationRun.lock.find(run_id)
      break nil unless locked.queued?
      break nil unless locked.ready_to_run?(now)

      running = ConversationRun.lock.running.find_by(conversation_id: locked.conversation_id)
      if running
        if running.stale?(now: now)
          running.failed!(
            at: now,
            cancel_requested_at: now,
            error: {
              "code" => "stale_running_run",
              "message" => "Run became stale while running",
              "stale_timeout_seconds" => ConversationRun::STALE_TIMEOUT.to_i,
              "heartbeat_at" => running.heartbeat_at&.iso8601,
            }
          )
          stale_running_run_id = running.id
        else
          break nil
        end
      end

      expected_last_message_id = locked.debug&.dig("expected_last_message_id")

      if expected_last_message_id.present?
        last_id =
          Message
            .where(conversation_id: locked.conversation_id)
            .order(seq: :desc, id: :desc)
            .limit(1)
            .pick(:id)

        if last_id != expected_last_message_id.to_i
          locked.skipped!(
            at: now,
            error: {
              "code" => "expected_last_message_mismatch",
              "expected_last_message_id" => expected_last_message_id,
              "actual_last_message_id" => last_id,
            }
          )

          # Notify user if this was a regenerate
          if locked.kind == "regenerate"
            ConversationChannel.broadcast_run_skipped(
              locked.conversation,
              reason: "message_mismatch",
              message: I18n.t(
                "messages.regenerate_skipped",
                default: "Conversation advanced; regenerate skipped."
              )
            )
          end

          break nil
        end
      end

      unless locked.speaker_space_membership_id.present?
        locked.skipped!(at: now, error: { "code" => "missing_speaker" })
        break nil
      end

      locked.running!(at: now, cancel_requested_at: nil)
      locked
    end

    if stale_running_run_id
      finalize_stale_run!(stale_running_run_id, at: now)
    end

    claimed
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Finalize a stale run that was preempted by a new queued run.
  # Cleans up placeholder messages and broadcasts UI feedback.
  #
  # @param stale_run_id [String] the ID of the stale run
  # @param at [Time] the timestamp for updates
  def finalize_stale_run!(stale_run_id, at:)
    stale_run = ConversationRun.find_by(id: stale_run_id)
    return unless stale_run

    user_message = I18n.t(
      "messages.generation_errors.stale_running_run",
      default: "Generation timed out. Please try again."
    )

    # Clean up any orphaned placeholder messages from the stale run
    Message
      .where(conversation_run_id: stale_run_id)
      .where("messages.metadata ->> 'generating' = 'true'")
      .find_each do |msg|
        metadata = (msg.metadata || {}).merge("generating" => false, "error" => user_message)
        msg.update!(content: user_message, metadata: metadata, updated_at: at)
        msg.broadcast_update
      end

    # Broadcast UI feedback for the stale run:
    # Order matters: first clear the old typing, then the new run starts typing
    # 1. run_failed: show toast notification to user
    # 2. stream_complete: clear typing indicator for the stale run's speaker
    stale_conversation = stale_run.conversation
    return unless stale_conversation

    ConversationChannel.broadcast_run_failed(
      stale_conversation,
      code: "stale_preempted",
      user_message: user_message
    )

    if stale_run.speaker_space_membership_id
      ConversationChannel.broadcast_stream_complete(
        stale_conversation,
        space_membership_id: stale_run.speaker_space_membership_id
      )
    end
  end

  # Find the target message for regenerate (without deleting it).
  #
  # @return [Message, nil] the target message
  def find_target_message_for_regenerate
    target_message_id = run.debug&.dig("target_message_id") || run.debug&.dig("trigger_message_id")
    return nil unless target_message_id

    conversation.messages.find_by(id: target_message_id)
  end

  # Add a new swipe version to the target message (for regenerate).
  # Preserves message.id and position in history.
  # Creates a new swipe with the generated content and sets it as active.
  #
  # Note: add_swipe! internally ensures initial swipe exists within its
  # transaction, so we don't need to call ensure_initial_swipe! separately.
  #
  # @param target [Message] the message to add a swipe to
  # @param content [String] the new generated content
  # @return [Message] the updated message
  def add_swipe_to_target_message!(target, content)
    # Apply group message trimming for AI characters in group chats
    trimmed_content = speaker.ai_character? ? trim_group_message(content) : content

    # Add new swipe version (internally ensures initial swipe exists)
    target.add_swipe!(
      content: trimmed_content.to_s.strip.presence,
      metadata: { "prompt_params" => generation_params_snapshot },
      conversation_run_id: run.id
    )

    # Replace the message DOM in place (not append)
    target.broadcast_update

    # Signal completion to typing indicator
    ConversationChannel.broadcast_stream_complete(conversation, space_membership_id: speaker.id)

    target
  end

  # Create the final message AFTER generation completes.
  # This eliminates placeholder message complexity and race conditions.
  #
  # @param content [String] the generated content
  # @return [Message] the created message
  def create_final_message(content)
    # Determine the message role based on the speaker type:
    # - AI characters generate "assistant" messages
    # - Copilot users (user participants with persona) generate "user" messages
    #   because the AI is speaking ON BEHALF OF the user
    message_role = speaker.ai_character? ? "assistant" : "user"

    # Apply group message trimming for AI characters in group chats
    trimmed_content = speaker.ai_character? ? trim_group_message(content) : content

    msg = conversation.messages.create!(
      space_membership: speaker,
      role: message_role,
      content: trimmed_content.to_s.strip.presence,
      conversation_run: run,
      metadata: { "prompt_params" => generation_params_snapshot }
    )

    # Broadcast the complete message via Turbo Streams
    msg.broadcast_create

    # Update group queue display (for group chats)
    Message::Broadcasts.broadcast_group_queue_update(conversation)

    # Signal completion to typing indicator
    ConversationChannel.broadcast_stream_complete(conversation, space_membership_id: speaker.id)

    msg
  end

  # Generate response content, streaming to typing indicator.
  #
  # @param prompt_messages [Array] the prompt messages
  # @return [String] the generated content
  def generate_response(prompt_messages)
    @llm_client = LLMClient.new(provider: effective_llm_provider)
    raise Canceled if cancel_requested?(force: true)

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

    content = if @llm_client.provider&.streamable? && streaming_enabled?
      full = +""
      @llm_client.chat(**gen_params) do |chunk|
        raise Canceled if cancel_requested?

        touch_run_heartbeat!
        full << chunk

        # Stream to typing indicator (not to a message bubble)
        ConversationChannel.broadcast_stream_chunk(conversation, content: full, space_membership_id: speaker.id)
      end

      raise Canceled if cancel_requested?(force: true)
      full
    else
      out = @llm_client.chat(**gen_params)
      raise Canceled if cancel_requested?(force: true)
      out
    end

    # Store logprobs in run debug data if available
    persist_logprobs!(@llm_client.last_logprobs)

    content
  end

  # Trim group message to remove dialogue from other characters.
  # This implements SillyTavern's cleanGroupMessage / disable_group_trimming behavior.
  #
  # When relax_message_trim is false (default), we detect lines starting with
  # "OtherCharacterName:" and truncate the response at that point, preventing
  # the AI from speaking as multiple characters in a single response.
  #
  # When relax_message_trim is true, the response is returned as-is.
  #
  # @param content [String] the generated content
  # @return [String] the trimmed content
  def trim_group_message(content)
    return content if content.blank?
    return content if space.relax_message_trim?
    return content unless space.group?

    # Get all group member display names except current speaker
    other_members = space.space_memberships.active.ai_characters
                         .where.not(id: speaker.id)
                         .map(&:display_name)
                         .compact

    return content if other_members.empty?

    trimmed = content.dup

    # Find first occurrence of "OtherMemberName:" and truncate there
    other_members.each do |name|
      # Match "Name:" at start of line (including first line)
      pattern = /(?:^|\n)#{Regexp.escape(name)}:/i
      match = trimmed.match(pattern)
      if match
        trimmed = trimmed[0...match.begin(0)]
      end
    end

    trimmed.strip
  end

  def finalize_success!
    # Re-check status to avoid overwriting terminal states (e.g., run was marked stale/failed)
    run.reload
    unless run.running?
      Rails.logger.warn("[RunExecutor] Skipping finalize_success! for run #{run.id}: status is #{run.status}, not running")
      return
    end

    # Record token usage to debug field if available
    if @llm_client.respond_to?(:last_usage) && @llm_client.last_usage.present?
      run.update!(debug: run.debug.merge("usage" => @llm_client.last_usage))
    end

    run.succeeded!(at: Time.current)

    # Decrement copilot remaining steps for full copilot users.
    # This will automatically disable copilot mode when steps reach 0.
    speaker&.decrement_copilot_remaining_steps!
  end

  def finalize_canceled!
    run.canceled!(at: Time.current)
    ConversationChannel.broadcast_stream_complete(conversation, space_membership_id: speaker.id) if conversation && speaker

    # Notify user that generation was stopped
    ConversationChannel.broadcast_run_canceled(conversation) if conversation
  end

  def finalize_failed!(error, code:, user_message: nil, **extra)
    # Re-check status to avoid overwriting terminal states (e.g., run was marked stale/failed)
    run.reload
    unless run.running?
      Rails.logger.warn("[RunExecutor] Skipping finalize_failed! for run #{run.id}: status is #{run.status}, not running")
      return
    end

    user_message = user_message.presence || error.message.to_s

    payload = {
      "code" => code,
      "message" => error.message.to_s,
    }.merge(extra.transform_keys(&:to_s))

    payload["user_message"] = user_message if user_message != payload["message"]

    run.failed!(at: Time.current, error: payload)

    # In the new flow, message is only created after successful generation,
    # so on failure we just need to signal stream complete to clear the typing indicator
    ConversationChannel.broadcast_stream_complete(conversation, space_membership_id: speaker.id) if conversation && speaker

    # Notify user of the failure with a toast
    ConversationChannel.broadcast_run_failed(conversation, code: code, user_message: user_message) if conversation

    disable_full_copilot_on_error(user_message)
  end

  def kick_followups_if_needed
    return unless run
    return unless conversation

    # Regenerate should not trigger followups - it's a "redo this one" operation
    return if run.kind == "regenerate"

    # If there's already a queued run, just kick it
    queued = ConversationRun.queued.find_by(conversation_id: conversation.id)
    if queued
      Conversation::RunPlanner.kick!(queued)
      return
    end

    return unless run.succeeded?
    return unless message

    # Case 1: Copilot user spoke → AI Character should respond
    # Check by run.reason instead of copilot_full? because copilot_mode might have been disabled
    # when steps reached 0 during finalize_success! (before kick_followups_if_needed is called)
    if speaker&.user? && copilot_user_run?
      Conversation::RunPlanner.plan_copilot_followup!(conversation: conversation, trigger_message: message)
      return
    end

    # Case 2: AI Character spoke → check if Copilot user should continue
    if speaker&.ai_character?
      copilot_user = find_active_copilot_user
      if copilot_user
        Conversation::RunPlanner.plan_copilot_continue!(conversation: conversation, copilot_membership: copilot_user, trigger_message: message)
        return
      end
    end

    # Case 3: AI-to-AI auto-mode followups (requires auto_mode_enabled)
    return unless space.auto_mode_enabled?

    Conversation::RunPlanner.plan_auto_mode_followup!(conversation: conversation, trigger_message: message)
  end

  # Find an active copilot user who can continue the conversation.
  #
  # @return [Participant, nil] the copilot user participant, or nil if none found
  def find_active_copilot_user
    space.space_memberships.active.find do |m|
      m.user? && m.copilot_full? && m.can_auto_respond?
    end
  end

  # Check if the current run was triggered by a copilot user action.
  # This is more reliable than checking copilot_full? because the mode
  # might have been disabled after steps reached 0.
  #
  # @return [Boolean] true if this run was a copilot user run
  def copilot_user_run?
    %w[copilot_start copilot_continue].include?(run.reason)
  end

  def cancel_requested?(force: false)
    return true if @cancel_requested_cached

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    unless force
      if @last_cancel_poll_monotonic && (now - @last_cancel_poll_monotonic) < CANCEL_POLL_INTERVAL_SECONDS
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
      if @last_heartbeat_touch_monotonic && (now - @last_heartbeat_touch_monotonic) < HEARTBEAT_INTERVAL_SECONDS
        return
      end
    end

    @last_heartbeat_touch_monotonic = now

    ts = Time.current
    run.update_columns(heartbeat_at: ts, updated_at: ts)
  end

  def broadcast_typing_start
    return unless conversation && speaker

    ConversationChannel.broadcast_typing(conversation, membership: speaker, active: true)
  end

  def broadcast_typing_stop
    return unless conversation && speaker

    ConversationChannel.broadcast_typing(conversation, membership: speaker, active: false)
  end

  def disable_full_copilot_on_error(error_message)
    # Case 1: Copilot user's own run failed
    if speaker&.user? && speaker.copilot_full?
      speaker.update!(copilot_mode: "none")
      Message::Broadcasts.broadcast_copilot_disabled(speaker, error: error_message)
      return
    end

    # Case 2: AI character's run failed during copilot loop
    # Find and disable any active copilot user to prevent the conversation from getting stuck
    if speaker&.ai_character?
      copilot_user = find_active_copilot_user
      if copilot_user
        copilot_user.update!(copilot_mode: "none")
        Message::Broadcasts.broadcast_copilot_disabled(copilot_user, error: error_message)
      end
    end
  end

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

  # Persist debug data to the run record for debugging LLM issues.
  #
  # The prompt_snapshot is only persisted if the Setting is enabled, as it can
  # be quite large and expensive to store.
  #
  # @param prompt_messages [Array<Hash>] the messages array sent to the LLM
  def persist_debug_data!(prompt_messages)
    return unless run

    debug_data = {
      "generation_params" => generation_params_snapshot,
      "speaker_membership_id" => speaker&.id,
      "speaker_name" => speaker&.display_name,
      "target_message_id" => @target_message&.id,
    }

    # Store prompt snapshot if enabled (can be expensive to store)
    if Setting.get("conversation.snapshot_prompt") == "true"
      debug_data["prompt_snapshot"] = truncate_prompt_snapshot(prompt_messages)
    end

    # Store tokenized prompt for Token Inspector view
    debug_data["tokenized_prompt"] = tokenize_prompt_messages(prompt_messages)

    run.update!(debug: run.debug.merge(debug_data))
  end

  # Tokenize each message in the prompt for the Token Inspector view.
  # Limits token storage to avoid excessively large payloads.
  #
  # @param prompt_messages [Array<Hash>] the messages array
  # @param max_tokens_per_message [Integer] max tokens to store per message (default 500)
  # @return [Array<Hash>] tokenized messages
  def tokenize_prompt_messages(prompt_messages, max_tokens_per_message: 500)
    estimator = TavernKit::TokenEstimator.default
    prompt_messages.map do |msg|
      content = msg[:content] || msg["content"]
      tokens = estimator.tokenize(content.to_s)

      # Truncate if too many tokens
      if tokens.size > max_tokens_per_message
        tokens = tokens.first(max_tokens_per_message)
        tokens << { id: -1, text: "... [truncated]" }
      end

      {
        "role" => msg[:role] || msg["role"],
        "name" => msg[:name] || msg["name"],
        "tokens" => tokens,
        "token_count" => estimator.estimate(content.to_s),
      }
    end
  end

  # Truncate individual message contents in the prompt snapshot to avoid
  # storing excessively large payloads.
  #
  # @param prompt_messages [Array<Hash>] the messages array
  # @param max_length [Integer] max length per message content (default 2000)
  # @return [Array<Hash>] truncated copy
  def truncate_prompt_snapshot(prompt_messages, max_length: 2000)
    prompt_messages.map do |msg|
      content = msg[:content] || msg["content"]
      if content.is_a?(String) && content.length > max_length
        msg.merge("content" => "#{content[0, max_length]}... [truncated, #{content.length} chars total]")
      else
        msg
      end
    end
  end

  # Persist logprobs data to the run record.
  # Only stores logprobs if available (provider supports it and returned data).
  #
  # @param logprobs [Array<Hash>, nil] logprobs data from LLM response
  # @param max_tokens [Integer] max number of tokens to store (default 500)
  def persist_logprobs!(logprobs, max_tokens: 500)
    return unless run
    return unless logprobs.is_a?(Array) && logprobs.any?

    # Truncate logprobs to avoid excessively large payloads
    stored_logprobs = logprobs.first(max_tokens)

    run.update!(debug: run.debug.merge("logprobs" => stored_logprobs))
  rescue StandardError => e
    Rails.logger.warn "Failed to persist logprobs: #{e.message}"
  end
end
