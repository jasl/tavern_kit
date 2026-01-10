# frozen_string_literal: true

# Persists run-side effects (messages + run status) and emits UI broadcasts.
#
# Responsibilities:
# - Create message or swipe after generation completes
# - Finalize run status (succeeded / failed / canceled)
# - Persist debug artifacts (prompt snapshot, tokenized prompt, logprobs, lore budget)
# - Broadcast Turbo/Channel updates as needed
#
class Conversations::RunExecutor::RunPersistence
  def initialize(run:, conversation:, space:, speaker:)
    @run = run
    @conversation = conversation
    @space = space
    @speaker = speaker
  end

  # Create or update a message AFTER generation completes.
  #
  # @param content [String] generated content
  # @param prompt_params [Hash] generation params snapshot to store in metadata
  # @param target_message [Message, nil] if present, add a swipe instead of creating a message
  # @return [Message] persisted message
  def persist_response_message!(content, prompt_params:, target_message:)
    if target_message
      add_swipe_to_target_message!(target_message, content, prompt_params: prompt_params)
    else
      create_final_message(content, prompt_params: prompt_params)
    end
  end

  # Persist debug data to the run record for debugging LLM issues.
  #
  # The prompt_snapshot is only persisted if the Setting is enabled, as it can
  # be quite large and expensive to store.
  #
  # @param prompt_messages [Array<Hash>] the messages array sent to the LLM
  # @param generation_params_snapshot [Hash] generation params snapshot
  # @param target_message [Message, nil] regenerate target (if any)
  def persist_debug_data!(prompt_messages, generation_params_snapshot:, target_message:)
    return unless run

    debug_data = {
      "generation_params" => generation_params_snapshot,
      "speaker_membership_id" => speaker&.id,
      "speaker_name" => speaker&.display_name,
      "target_message_id" => target_message&.id,
    }

    # Store prompt snapshot if enabled (can be expensive to store)
    if Setting.get("conversation.snapshot_prompt") == "true"
      debug_data["prompt_snapshot"] = truncate_prompt_snapshot(prompt_messages)
    end

    # Store tokenized prompt for Token Inspector view
    debug_data["tokenized_prompt"] = tokenize_prompt_messages(prompt_messages)

    run.update!(debug: run.debug.merge(debug_data))
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
    Rails.logger.warn "Failed to persist logprobs: #{e.class}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
  end

  # Persist World Info (Lore) budget status to the run record.
  # This enables UI display of budget overflow alerts.
  #
  # Stores:
  # - lore_budget_exceeded: boolean indicating if any entries were dropped
  # - lore_budget_dropped_count: number of entries dropped due to budget
  # - lore_selected_count: number of entries selected
  # - lore_budget: the token budget (or "unlimited")
  # - lore_used_tokens: tokens used by selected entries
  def persist_lore_budget_status!(context_builder:)
    return unless run
    return unless context_builder

    lore_result = context_builder.lore_result
    return unless lore_result

    lore_data = {
      "lore_budget_exceeded" => lore_result.budget_exceeded?,
      "lore_budget_dropped_count" => lore_result.budget_dropped_count,
      "lore_selected_count" => lore_result.selected.count,
      "lore_budget" => lore_result.budget || "unlimited",
      "lore_used_tokens" => lore_result.used_tokens,
    }

    run.update!(debug: run.debug.merge(lore_data))
  rescue StandardError => e
    Rails.logger.warn "Failed to persist lore budget status: #{e.class}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
  end

  # Finalize a successful generation run.
  #
  # NOTE: With the generation_status refactor, message status is set to "succeeded"
  # at creation time (in create_final_message), so we no longer need to broadcast_update
  # the message here. This eliminates Turbo Stream race conditions.
  #
  # @param llm_client [LLMClient] the LLM client (for usage stats)
  # @param message [Message, nil] unused after refactor, kept for API compatibility
  def finalize_success!(llm_client:, message: nil)
    # Re-check status to avoid overwriting terminal states (e.g., run was marked stale/failed)
    run.reload
    unless run.running?
      Rails.logger.warn("[RunExecutor] Skipping finalize_success! for run #{run.id}: status is #{run.status}, not running")
      return
    end

    # Record token usage to debug field if available
    if llm_client.respond_to?(:last_usage) && llm_client.last_usage.present?
      run.update!(debug: run.debug.merge("usage" => llm_client.last_usage))
    end

    run.succeeded!(at: Time.current)

    # Decrement copilot remaining steps for full copilot users.
    # This will automatically disable copilot mode when steps reach 0.
    speaker&.decrement_copilot_remaining_steps!
  end

  def finalize_canceled!
    # Re-check status to avoid overwriting terminal states (e.g., run was marked stale/failed by reaper)
    run.reload
    unless run.running?
      Rails.logger.warn("[RunExecutor] Skipping finalize_canceled! for run #{run.id}: status is #{run.status}, not running")
      return
    end

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

  private

  attr_reader :run, :conversation, :space, :speaker

  # Add a new swipe version to the target message (for regenerate).
  # Preserves message.id and position in history.
  # Creates a new swipe with the generated content and sets it as active.
  #
  # Note: add_swipe! internally ensures initial swipe exists within its
  # transaction, so we don't need to call ensure_initial_swipe! separately.
  #
  # @param target [Message] the message to add a swipe to
  # @param content [String] the new generated content
  # @param prompt_params [Hash] generation params snapshot to store in metadata
  # @return [Message] the updated message
  def add_swipe_to_target_message!(target, content, prompt_params:)
    # Apply group message trimming for AI characters in group chats
    trimmed_content = speaker.ai_character? ? trim_group_message(content) : content

    # Add new swipe version (internally ensures initial swipe exists)
    target.add_swipe!(
      content: trimmed_content.to_s.strip.presence,
      metadata: { "prompt_params" => prompt_params },
      conversation_run_id: run.id
    )

    # Mark the message as succeeded (regenerate completed)
    target.update!(generation_status: "succeeded")

    # Replace the message DOM in place (not append)
    target.broadcast_update

    # Signal completion to typing indicator
    ConversationChannel.broadcast_stream_complete(conversation, space_membership_id: speaker.id)

    target
  end

  # Create the final message AFTER generation completes.
  # Sets generation_status to "succeeded" directly, eliminating race conditions
  # between broadcast_create and broadcast_update.
  #
  # @param content [String] the generated content
  # @param prompt_params [Hash] generation params snapshot to store in metadata
  # @return [Message] the created message
  def create_final_message(content, prompt_params:)
    # Determine the message role based on the speaker type:
    # - AI characters generate "assistant" messages
    # - Copilot users (user participants with persona) generate "user" messages
    #   because the AI is speaking ON BEHALF OF the user
    message_role = speaker.ai_character? ? "assistant" : "user"

    # Apply group message trimming for AI characters in group chats
    trimmed_content = speaker.ai_character? ? trim_group_message(content) : content

    # Create message with final status directly - no need for separate broadcast_update
    # since the status is already correct at creation time.
    msg = conversation.messages.create!(
      space_membership: speaker,
      role: message_role,
      content: trimmed_content.to_s.strip.presence,
      conversation_run: run,
      generation_status: "succeeded",
      metadata: { "prompt_params" => prompt_params }
    )

    # Broadcast the complete message via Turbo Streams (status already correct)
    msg.broadcast_create

    # Update group queue display (for group chats)
    Message::Broadcasts.broadcast_group_queue_update(conversation)

    # Signal completion to typing indicator
    ConversationChannel.broadcast_stream_complete(conversation, space_membership_id: speaker.id)

    msg
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
      trimmed = trimmed[0...match.begin(0)] if match
    end

    trimmed.strip
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
      copilot_user = space.space_memberships.active.find { |m| m.copilot_full? && m.can_auto_respond? }
      if copilot_user
        copilot_user.update!(copilot_mode: "none")
        Message::Broadcasts.broadcast_copilot_disabled(copilot_user, error: error_message)
      end
    end
  end
end
