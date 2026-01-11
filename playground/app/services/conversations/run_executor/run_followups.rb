# frozen_string_literal: true

# Handles followup actions after a run finishes.
#
# ## Serial Execution Guarantee
#
# This class is critical for ensuring serial execution of runs within a conversation.
# When RunPlanner creates a new run while another is running, it creates the record
# but does NOT schedule a job (to avoid race conditions). This class ensures that
# when a run finishes, any waiting queued run gets kicked with force: true.
#
# Flow:
# 1. Run A is running
# 2. Scheduler creates Run B (queued), but job is NOT scheduled (running exists)
# 3. Run A finishes successfully → RunFollowups.kick_if_needed! kicks Run B
# 4. Run B executes
#
# ## Failure Handling
#
# If a run fails (errored, timed out, etc.), we do NOT auto-advance to the next run.
# This prevents cascading failures and gives users a chance to:
# - Review what went wrong
# - Retry the failed run
# - Or manually intervene
#
# The UI will show an error indicator with a Retry button.
#
# ## Other responsibilities
#
# - Regenerate runs don't trigger followups (they're a "redo this one" operation)
# - Turn counting and resource decrementing are handled by TurnScheduler::Commands::AdvanceTurn
#
class Conversations::RunExecutor::RunFollowups
  def initialize(run:, conversation:, space:, speaker:, message:)
    @run = run
    @conversation = conversation
    @space = space
    @speaker = speaker
    @message = message
  end

  def kick_if_needed!
    return unless @run
    return unless @conversation

    # Regenerate should not trigger followups - it's a "redo this one" operation
    return if @run.regenerate?

    # DON'T auto-advance if the run failed - let the user decide what to do
    # This prevents cascading failures and corrupted conversation state
    if @run.failed?
      Rails.logger.info "[RunFollowups] Run #{@run.id} failed - not auto-advancing. " \
                        "Error: #{@run.error.dig('code')}"
      broadcast_failure_alert!
      return
    end

    # If there's already a queued run, force kick it
    # This handles cases where a run was queued but its job couldn't claim
    # (e.g., because another run was still running at the time)
    queued = ConversationRun.queued.find_by(conversation_id: @conversation.id)
    return unless queued

    Conversations::RunPlanner.kick!(queued, force: true)
  end

  private

  # Broadcast an alert to notify users that the conversation is stuck due to an error
  def broadcast_failure_alert!
    return unless @conversation

    error_code = @run.error&.dig("code") || "unknown_error"
    user_message = case error_code
    when "stale_timeout"
                     I18n.t("messages.errors.run_timed_out",
                            default: "AI response timed out. Click Retry to try again.")
    when "no_provider_configured"
                     I18n.t("messages.errors.no_provider",
                            default: "No LLM provider configured. Please add one in Settings.")
    when "connection_error", "http_error"
                     I18n.t("messages.errors.llm_error",
                            default: "Failed to connect to LLM provider. Click Retry to try again.")
    else
                     I18n.t("messages.errors.run_failed",
                            default: "AI response failed. Click Retry to try again.")
    end

    ConversationChannel.broadcast_run_error_alert(
      @conversation,
      run_id: @run.id,
      error_code: error_code,
      message: user_message
    )
  end
end
