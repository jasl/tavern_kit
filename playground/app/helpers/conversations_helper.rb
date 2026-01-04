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
end
