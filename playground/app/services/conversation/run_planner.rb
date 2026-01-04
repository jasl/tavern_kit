# frozen_string_literal: true

class Conversation::RunPlanner
  KICK_DEDUP_WINDOW_MS = 2000

  class << self
    def plan_from_user_message!(conversation:, user_message:)
      raise ArgumentError, "user_message must belong to conversation" unless user_message.conversation_id == conversation.id

      space = conversation.space
      return nil if space.reply_order == "manual"

      speaker = SpeakerSelector.new(conversation).select_for_user_turn
      return nil unless speaker

      now = Time.current
      run_after = now + (space.user_turn_debounce_ms.to_i / 1000.0)

      queued =
        conversation.with_lock do
          apply_policy_to_running_run!(conversation: conversation, now: now)

          upsert_queued_run!(
            conversation: conversation,
            kind: "user_turn",
            reason: "user_message",
            speaker_space_membership_id: speaker.id,
            run_after: run_after,
            debug: {
              trigger: "user_message",
              user_message_id: user_message.id,
            }
          )
        end

      kick!(queued)
      queued
    end

    # Plans a "user_turn" run that uses normal speaker selection, but isn't necessarily
    # tied to a newly-created user Message. Used for operations like group chat
    # "last_turn" regeneration (delete AI turn and re-queue generation).
    def plan_user_turn!(conversation:, trigger:)
      speaker = SpeakerSelector.new(conversation).select_for_user_turn
      return nil unless speaker

      now = Time.current

      queued =
        conversation.with_lock do
          apply_policy_to_running_run!(conversation: conversation, now: now)

          upsert_queued_run!(
            conversation: conversation,
            kind: "user_turn",
            reason: trigger.to_s,
            speaker_space_membership_id: speaker.id,
            run_after: now,
            debug: { trigger: trigger.to_s }
          )
        end

      kick!(queued)
      queued
    end

    def plan_force_talk!(conversation:, speaker_space_membership_id:)
      speaker = SpeakerSelector.new(conversation).select_manual(speaker_space_membership_id)
      return nil unless speaker

      now = Time.current

      queued =
        conversation.with_lock do
          apply_policy_to_running_run!(conversation: conversation, now: now)

          upsert_queued_run!(
            conversation: conversation,
            kind: "force_talk",
            reason: "force_talk",
            speaker_space_membership_id: speaker.id,
            run_after: now,
            debug: { trigger: "force_talk" }
          )
        end

      kick!(queued)
      queued
    end

    def plan_regenerate!(conversation:, target_message:)
      raise ArgumentError, "target_message must belong to conversation" unless target_message.conversation_id == conversation.id
      raise ArgumentError, "target_message must be an assistant message" unless target_message.assistant_message?

      speaker = conversation.space.space_memberships.active.find_by(id: target_message.space_membership_id)
      return nil unless speaker&.can_auto_respond?

      now = Time.current

      queued =
        conversation.with_lock do
          running = ConversationRun.running.find_by(conversation_id: conversation.id)
          running&.request_cancel!(at: now)

          upsert_queued_run!(
            conversation: conversation,
            kind: "regenerate",
            reason: "regenerate",
            speaker_space_membership_id: speaker.id,
            run_after: now,
            debug: {
              trigger: "regenerate",
              target_message_id: target_message.id,
              expected_last_message_id: target_message.id,
            }
          )
        end

      kick!(queued)
      queued
    end

    def plan_auto_mode_followup!(conversation:, trigger_message:)
      space = conversation.space
      return nil unless space.auto_mode_enabled?
      return nil if space.reply_order == "manual"

      raise ArgumentError, "trigger_message must belong to conversation" unless trigger_message.conversation_id == conversation.id
      raise ArgumentError, "trigger_message must be an assistant message" unless trigger_message.assistant_message?

      speaker = SpeakerSelector.new(conversation).select_for_auto_mode(previous_speaker: trigger_message.space_membership)
      return nil unless speaker

      now = Time.current
      run_after = now + (space.auto_mode_delay_ms.to_i / 1000.0)

      queued =
        conversation.with_lock do
          existing = ConversationRun.queued.find_by(conversation_id: conversation.id)
          return nil if existing

          conversation.conversation_runs.create!(
            kind: "auto_mode",
            status: "queued",
            reason: "auto_mode",
            speaker_space_membership_id: speaker.id,
            run_after: run_after,
            debug: {
              trigger: "auto_mode",
              trigger_message_id: trigger_message.id,
              expected_last_message_id: trigger_message.id,
            }
          )
        end

      kick!(queued) if queued
      queued
    end

    def plan_copilot_start!(conversation:, copilot_membership:)
      space = conversation.space
      return nil if space.reply_order == "manual"
      return nil unless copilot_membership.copilot_full?
      return nil unless copilot_membership.can_auto_respond?

      now = Time.current

      queued =
        conversation.with_lock do
          return nil if ConversationRun.queued.exists?(conversation_id: conversation.id)
          return nil if ConversationRun.running.exists?(conversation_id: conversation.id)

          conversation.conversation_runs.create!(
            kind: "user_turn",
            status: "queued",
            reason: "copilot_start",
            speaker_space_membership_id: copilot_membership.id,
            run_after: now,
            debug: {
              trigger: "copilot_start",
              copilot_membership_id: copilot_membership.id,
            }
          )
        end

      kick!(queued) if queued
      queued
    end

    def plan_copilot_followup!(conversation:, trigger_message:)
      space = conversation.space
      return nil if space.reply_order == "manual"

      raise ArgumentError, "trigger_message must belong to conversation" unless trigger_message.conversation_id == conversation.id
      raise ArgumentError, "trigger_message must be a user message (from copilot user)" unless trigger_message.user_message?

      copilot_membership_id = trigger_message.space_membership_id

      speaker =
        SpeakerSelector
          .new(conversation)
          .select_ai_character_only(exclude_participant_id: copilot_membership_id)

      return nil unless speaker

      now = Time.current

      queued =
        conversation.with_lock do
          existing = ConversationRun.queued.find_by(conversation_id: conversation.id)
          return nil if existing

          conversation.conversation_runs.create!(
            kind: "user_turn",
            status: "queued",
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
        end

      kick!(queued) if queued
      queued
    end

    def plan_copilot_continue!(conversation:, copilot_membership:, trigger_message:)
      space = conversation.space
      return nil if space.reply_order == "manual"
      return nil unless copilot_membership.copilot_full?
      return nil unless copilot_membership.can_auto_respond?

      raise ArgumentError, "trigger_message must belong to conversation" unless trigger_message.conversation_id == conversation.id
      raise ArgumentError, "trigger_message must be an assistant message" unless trigger_message.assistant_message?

      now = Time.current

      queued =
        conversation.with_lock do
          existing = ConversationRun.queued.find_by(conversation_id: conversation.id)
          return nil if existing

          conversation.conversation_runs.create!(
            kind: "user_turn",
            status: "queued",
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
        end

      kick!(queued) if queued
      queued
    end

    def kick!(run)
      return unless run
      return if recently_kicked?(run)

      if run.run_after.present? && run.run_after.future?
        ConversationRunJob.set(wait_until: run.run_after).perform_later(run.id)
      else
        ConversationRunJob.perform_later(run.id)
      end

      record_kick!(run)
    end

    private

    def recently_kicked?(run)
      debug = run.debug || {}

      last_kicked_at_ms = debug["last_kicked_at_ms"].to_i
      return false if last_kicked_at_ms <= 0

      last_kicked_run_after_ms = debug["last_kicked_run_after_ms"]
      last_kicked_run_after_ms = last_kicked_run_after_ms.to_i if last_kicked_run_after_ms

      current_run_after_ms = run.run_after ? (run.run_after.to_f * 1000).to_i : nil
      return false if last_kicked_run_after_ms != current_run_after_ms

      now_ms = (Time.current.to_f * 1000).to_i
      (now_ms - last_kicked_at_ms) < KICK_DEDUP_WINDOW_MS
    end

    def apply_policy_to_running_run!(conversation:, now:)
      running = ConversationRun.running.find_by(conversation_id: conversation.id)
      return unless running

      case conversation.space.during_generation_user_input_policy
      when "restart"
        running.request_cancel!(at: now)
      end
    end

    def upsert_queued_run!(conversation:, kind:, reason:, speaker_space_membership_id:, run_after:, debug:)
      existing = ConversationRun.queued.find_by(conversation_id: conversation.id)

      attrs = {
        kind: kind,
        status: "queued",
        reason: reason,
        speaker_space_membership_id: speaker_space_membership_id,
        run_after: run_after,
        cancel_requested_at: nil,
        started_at: nil,
        finished_at: nil,
        error: {},
        debug: (debug || {}).deep_stringify_keys,
      }

      if existing
        existing.update!(attrs)
        existing
      else
        conversation.conversation_runs.create!(attrs)
      end
    end

    def record_kick!(run)
      now = Time.current
      now_ms = (now.to_f * 1000).to_i
      run_after_ms = run.run_after ? (run.run_after.to_f * 1000).to_i : nil

      debug = (run.debug || {}).dup
      debug["last_kicked_at_ms"] = now_ms
      debug["last_kicked_run_after_ms"] = run_after_ms
      debug["kicked_count"] = debug.fetch("kicked_count", 0).to_i + 1

      run.update_columns(debug: debug, updated_at: now)
    end
  end
end
