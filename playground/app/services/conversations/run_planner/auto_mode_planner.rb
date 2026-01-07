# frozen_string_literal: true

# Encapsulates auto-mode followup planning policy.
#
# This keeps Conversations::RunPlanner focused on concurrency-safe queue upsert/exclusive
# primitives, while moving policy decisions (guards + speaker selection + timing) into
# a small, testable object.
#
class Conversations::RunPlanner::AutoModePlanner
  def self.call(conversation:, trigger_message:)
    new(conversation: conversation, trigger_message: trigger_message).call
  end

  def initialize(conversation:, trigger_message:)
    @conversation = conversation
    @trigger_message = trigger_message
  end

  def call
    space = @conversation.space
    return nil unless space.auto_mode_enabled?
    return nil if space.reply_order == "manual"

    raise ArgumentError, "trigger_message must belong to conversation" unless @trigger_message.conversation_id == @conversation.id
    raise ArgumentError, "trigger_message must be an assistant message" unless @trigger_message.assistant_message?

    speaker = SpeakerSelector.new(@conversation).select_for_auto_mode(previous_speaker: @trigger_message.space_membership)
    return nil unless speaker

    now = Time.current
    run_after = now + (space.auto_mode_delay_ms.to_i / 1000.0)

    queued = Conversations::RunPlanner.send(
      :create_exclusive_queued_run!,
      conversation: @conversation,
      kind: "auto_mode",
      reason: "auto_mode",
      speaker_space_membership_id: speaker.id,
      run_after: run_after,
      debug: {
        trigger: "auto_mode",
        trigger_message_id: @trigger_message.id,
        expected_last_message_id: @trigger_message.id,
      }
    )

    Conversations::RunPlanner.kick!(queued) if queued
    queued
  end
end
