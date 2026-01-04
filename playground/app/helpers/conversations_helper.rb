# frozen_string_literal: true

module ConversationsHelper
  # Calculate token usage statistics for a conversation.
  #
  # Aggregates token usage data from recent successful ConversationRuns.
  #
  # @param conversation [Conversation] the conversation to calculate stats for
  # @param limit [Integer] maximum number of runs to consider (default: 50)
  # @return [Hash] token statistics with :prompt_tokens, :completion_tokens, :total_tokens
  def conversation_token_stats(conversation, limit: 50)
    runs = conversation.conversation_runs.succeeded.order(created_at: :desc).limit(limit)

    stats = {
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
    }

    runs.each do |run|
      usage = run.debug&.dig("usage")
      next unless usage

      stats[:prompt_tokens] += usage["prompt_tokens"].to_i
      stats[:completion_tokens] += usage["completion_tokens"].to_i
      stats[:total_tokens] += usage["total_tokens"].to_i
    end

    stats
  end

  # Get status badge class for a ConversationRun.
  #
  # @param run [ConversationRun] the conversation run
  # @return [String] CSS class for the badge
  def run_status_badge_class(run)
    case run.status
    when "succeeded" then "badge-success"
    when "failed" then "badge-error"
    when "running" then "badge-info"
    when "queued" then "badge-warning"
    when "canceled" then "badge-ghost"
    when "skipped" then "badge-ghost"
    else "badge-ghost"
    end
  end

  # Get human-readable label for run kind.
  #
  # @param kind [String] the run kind
  # @return [String] human-readable label
  def run_kind_label(kind)
    case kind
    when "user_turn" then "User Turn"
    when "auto_mode" then "Auto Mode"
    when "regenerate" then "Regenerate"
    when "force_talk" then "Force Talk"
    else kind.humanize
    end
  end

  # Get run detail data for the debug modal.
  #
  # Extracts all relevant data from a ConversationRun for display in the
  # run detail modal. This includes status, timing, error info, token usage,
  # and the prompt snapshot if available.
  #
  # @param run [ConversationRun] the conversation run
  # @return [Hash] run detail data for JSON serialization
  def run_detail_data(run)
    data = {
      id: run.id,
      status: run.status,
      kind: run.kind,
      trigger: run.trigger,
      reason: run.reason,
      created_at: run.created_at&.iso8601,
      started_at: run.started_at&.iso8601,
      finished_at: run.finished_at&.iso8601,
      run_after: run.run_after&.iso8601,
      expected_last_message_id: run.expected_last_message_id,
      speaker_membership_id: run.speaker_space_membership_id,
      speaker_name: run.speaker_space_membership&.display_name,
    }

    # Add debug data if present
    if run.debug.present?
      data[:usage] = run.debug["usage"] if run.debug["usage"].present?
      data[:generation_params] = run.debug["generation_params"] if run.debug["generation_params"].present?
      data[:prompt_snapshot] = run.debug["prompt_snapshot"] if run.debug["prompt_snapshot"].present?
      data[:target_message_id] = run.debug["target_message_id"] if run.debug["target_message_id"].present?
    end

    # Add error data if failed
    data[:error] = run.error if run.error.present?

    data
  end
end
