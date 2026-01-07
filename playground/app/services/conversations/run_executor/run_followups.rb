# frozen_string_literal: true

# Plans/kicks followup runs after a run finishes.
#
# This is invoked from RunExecutor's ensure block to keep followup behavior
# consistent even when exceptions occur (including cancellation).
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
    return if @run.kind == "regenerate"

    # If there's already a queued run, just kick it
    queued = ConversationRun.queued.find_by(conversation_id: @conversation.id)
    if queued
      Conversations::RunPlanner.kick!(queued)
      return
    end

    return unless @run.succeeded?
    return unless @message

    # Case 1: Copilot user spoke → AI Character should respond
    # Check by run.reason instead of copilot_full? because copilot_mode might have been disabled
    # when steps reached 0 during finalize_success! (before kick_followups_if_needed is called)
    if @speaker&.user? && copilot_user_run?
      Conversations::RunPlanner.plan_copilot_followup!(conversation: @conversation, trigger_message: @message)
      return
    end

    # Case 2: AI Character spoke → check if Copilot user should continue
    if @speaker&.ai_character?
      copilot_user = Conversations::RunExecutor::CopilotUserFinder.find_active(@space)
      if copilot_user
        Conversations::RunPlanner.plan_copilot_continue!(
          conversation: @conversation,
          copilot_membership: copilot_user,
          trigger_message: @message
        )
        return
      end
    end

    # Case 3: AI-to-AI auto-mode followups (requires auto_mode_enabled)
    return unless @space&.auto_mode_enabled?

    Conversations::RunPlanner.plan_auto_mode_followup!(conversation: @conversation, trigger_message: @message)
  end

  private

  # Check if the current run was triggered by a copilot user action.
  # This is more reliable than checking copilot_full? because the mode
  # might have been disabled after steps reached 0.
  #
  # @return [Boolean] true if this run was a copilot user run
  def copilot_user_run?
    %w[copilot_start copilot_continue].include?(@run.reason)
  end
end
