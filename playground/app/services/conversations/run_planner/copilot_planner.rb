# frozen_string_literal: true

# Encapsulates copilot planning policy (start / followup / continue).
#
# Conversations::RunPlanner retains the concurrency-safe queue primitives, while this
# class centralizes the copilot-specific guardrails and speaker selection rules.
#
class Conversations::RunPlanner::CopilotPlanner
  def self.plan_start!(conversation:, copilot_membership:)
    new(conversation: conversation).plan_start!(copilot_membership: copilot_membership)
  end

  def self.plan_followup!(conversation:, trigger_message:)
    new(conversation: conversation).plan_followup!(trigger_message: trigger_message)
  end

  def self.plan_continue!(conversation:, copilot_membership:, trigger_message:)
    new(conversation: conversation).plan_continue!(copilot_membership: copilot_membership, trigger_message: trigger_message)
  end

  def initialize(conversation:)
    @conversation = conversation
    @space = conversation.space
  end

  def plan_start!(copilot_membership:)
    return nil if @space.reply_order == "manual"
    return nil unless copilot_membership.copilot_full?
    return nil unless copilot_membership.can_auto_respond?

    # Early check for running runs (copilot_start should not interrupt)
    return nil if ConversationRun.running.exists?(conversation_id: @conversation.id)

    now = Time.current

    queued = Conversations::RunPlanner.send(
      :create_exclusive_queued_run!,
      conversation: @conversation,
      kind: "user_turn",
      reason: "copilot_start",
      speaker_space_membership_id: copilot_membership.id,
      run_after: now,
      debug: {
        trigger: "copilot_start",
        copilot_membership_id: copilot_membership.id,
      }
    )

    Conversations::RunPlanner.kick!(queued) if queued
    queued
  end

  def plan_followup!(trigger_message:)
    return nil if @space.reply_order == "manual"

    raise ArgumentError, "trigger_message must belong to conversation" unless trigger_message.conversation_id == @conversation.id
    raise ArgumentError, "trigger_message must be a user message (from copilot user)" unless trigger_message.user_message?

    copilot_membership_id = trigger_message.space_membership_id

    speaker =
      SpeakerSelector
        .new(@conversation)
        .select_ai_character_only(exclude_participant_id: copilot_membership_id)

    return nil unless speaker

    now = Time.current

    queued = Conversations::RunPlanner.send(
      :create_exclusive_queued_run!,
      conversation: @conversation,
      kind: "user_turn",
      reason: "copilot_followup",
      speaker_space_membership_id: speaker.id,
      run_after: now,
      debug: {
        trigger: "copilot_followup",
        trigger_message_id: trigger_message.id,
        expected_last_message_id: trigger_message.id,
        copilot_message_id: trigger_message.id,
      }
    )

    Conversations::RunPlanner.kick!(queued) if queued
    queued
  end

  def plan_continue!(copilot_membership:, trigger_message:)
    return nil if @space.reply_order == "manual"
    return nil unless copilot_membership.copilot_full?
    return nil unless copilot_membership.can_auto_respond?

    raise ArgumentError, "trigger_message must belong to conversation" unless trigger_message.conversation_id == @conversation.id
    raise ArgumentError, "trigger_message must be an assistant message" unless trigger_message.assistant_message?

    now = Time.current

    queued = Conversations::RunPlanner.send(
      :create_exclusive_queued_run!,
      conversation: @conversation,
      kind: "user_turn",
      reason: "copilot_continue",
      speaker_space_membership_id: copilot_membership.id,
      run_after: now,
      debug: {
        trigger: "copilot_continue",
        trigger_message_id: trigger_message.id,
        expected_last_message_id: trigger_message.id,
        ai_message_id: trigger_message.id,
      }
    )

    Conversations::RunPlanner.kick!(queued) if queued
    queued
  end
end
