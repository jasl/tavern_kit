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
  # @param kind [String, nil] the run kind
  # @return [String] human-readable label
  def run_kind_label(kind)
    case kind
    when "user_turn" then "User Turn"
    when "auto_turn" then "Auto Turn"
    when "regenerate" then "Regenerate"
    when "force_talk" then "Force Talk"
    when nil then "Unknown"
    else kind.humanize
    end
  end

  # Get badge class for run kind.
  #
  # @param run [ConversationRun] the run
  # @return [String] CSS badge class
  def run_type_badge_class(run)
    case run.kind
    when "auto_response" then "badge-primary"
    when "auto_user_response" then "badge-secondary"
    when "regenerate" then "badge-accent"
    when "force_talk" then "badge-info"
    else "badge-ghost"
    end
  end

  # Get icon class for run kind.
  #
  # @param run [ConversationRun] the run
  # @return [String] icon class
  def run_type_icon_class(run)
    case run.kind
    when "auto_response" then "icon-[lucide--bot]"
    when "auto_user_response" then "icon-[lucide--sparkles]"
    when "regenerate" then "icon-[lucide--refresh-cw]"
    when "force_talk" then "icon-[lucide--message-circle]"
    else "icon-[lucide--help-circle]"
    end
  end

  # Get color class for run kind icon.
  #
  # @param run [ConversationRun] the run
  # @return [String] text color class
  def run_type_color_class(run)
    case run.kind
    when "auto_response" then "text-primary"
    when "auto_user_response" then "text-secondary"
    when "regenerate" then "text-accent"
    when "force_talk" then "text-info"
    else "text-base-content/50"
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
      kind_label: run.kind_label,
      reason: run.reason,
      created_at: run.created_at&.iso8601,
      started_at: run.started_at&.iso8601,
      finished_at: run.finished_at&.iso8601,
      run_after: run.run_after&.iso8601,
      speaker_membership_id: run.speaker_space_membership_id,
      speaker_name: run.speaker_space_membership&.display_name,
    }

    # Add debug data if present
    # Note: trigger and expected_last_message_id are stored in debug jsonb,
    # not as direct columns - see RunPlanner for how these are set.
    if run.debug.present?
      data[:trigger] = run.debug["trigger"] if run.debug["trigger"].present?
      data[:expected_last_message_id] = run.debug["expected_last_message_id"] if run.debug["expected_last_message_id"].present?
      data[:usage] = run.debug["usage"] if run.debug["usage"].present?
      data[:generation_params] = run.debug["generation_params"] if run.debug["generation_params"].present?
      data[:prompt_snapshot] = run.debug["prompt_snapshot"] if run.debug["prompt_snapshot"].present?
      data[:target_message_id] = run.debug["target_message_id"] if run.debug["target_message_id"].present?
      data[:tokenized_prompt] = run.debug["tokenized_prompt"] if run.debug["tokenized_prompt"].present?
      data[:logprobs] = run.debug["logprobs"] if run.debug["logprobs"].present?

      # World Info (Lore) budget status
      data[:lore_budget_exceeded] = run.debug["lore_budget_exceeded"] if run.debug.key?("lore_budget_exceeded")
      data[:lore_budget_dropped_count] = run.debug["lore_budget_dropped_count"] if run.debug.key?("lore_budget_dropped_count")
      data[:lore_selected_count] = run.debug["lore_selected_count"] if run.debug.key?("lore_selected_count")
      data[:lore_budget] = run.debug["lore_budget"] if run.debug.key?("lore_budget")
      data[:lore_used_tokens] = run.debug["lore_used_tokens"] if run.debug.key?("lore_used_tokens")
    end

    # Add error data if failed
    data[:error] = run.error if run.error.present?

    data
  end

  # Build the breadcrumb path from root to current conversation.
  #
  # Walks up the parent_conversation chain to build an ordered array
  # of conversations from root to the current one.
  #
  # @param conversation [Conversation] the current conversation
  # @return [Array<Conversation>] ordered array from root to current
  def conversation_breadcrumb_path(conversation)
    path = []
    current = conversation
    while current
      path.unshift(current)
      current = current.parent_conversation
    end
    path
  end

  # Get the display label for a conversation in breadcrumb/list context.
  #
  # @param conversation [Conversation] the conversation
  # @return [String] display label
  def conversation_display_label(conversation)
    if conversation.root?
      conversation.title.presence || I18n.t("conversations.root", default: "Main")
    else
      conversation.title.presence || I18n.t("conversations.untitled_#{conversation.kind}", default: conversation.kind.humanize)
    end
  end

  # Get icon class for conversation kind.
  #
  # @param conversation [Conversation] the conversation
  # @return [String] icon class
  def conversation_kind_icon(conversation)
    case conversation.kind
    when "root" then "icon-[lucide--message-circle]"
    when "branch" then "icon-[lucide--git-branch]"
    when "checkpoint" then "icon-[lucide--bookmark]"
    when "thread" then "icon-[lucide--messages-square]"
    else "icon-[lucide--message-circle]"
    end
  end

  # Get badge class for conversation kind.
  #
  # @param conversation [Conversation] the conversation
  # @return [String] badge class
  def conversation_kind_badge_class(conversation)
    case conversation.kind
    when "root" then "badge-primary"
    when "branch" then "badge-info"
    when "checkpoint" then "badge-warning"
    when "thread" then "badge-secondary"
    else "badge-ghost"
    end
  end
end
