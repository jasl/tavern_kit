# frozen_string_literal: true

# Plans and schedules ConversationRuns for AI responses.
#
# Concurrency Strategy:
# Uses optimistic concurrency control instead of pessimistic locking.
# The database has unique partial indexes that ensure:
# - Only one queued run per conversation
# - Only one running run per conversation
#
# When concurrent requests try to create runs, the unique index violation
# is caught and handled gracefully (either by updating the existing run
# or returning nil for "first one wins" scenarios).
#
class Conversations::RunPlanner
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

      apply_policy_to_running_run!(conversation: conversation, now: now)

      queued = upsert_queued_run!(
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

      apply_policy_to_running_run!(conversation: conversation, now: now)

      queued = upsert_queued_run!(
        conversation: conversation,
        kind: "user_turn",
        reason: trigger.to_s,
        speaker_space_membership_id: speaker.id,
        run_after: now,
        debug: { trigger: trigger.to_s }
      )

      kick!(queued)
      queued
    end

    def plan_force_talk!(conversation:, speaker_space_membership_id:)
      speaker = SpeakerSelector.new(conversation).select_manual(speaker_space_membership_id)
      return nil unless speaker

      now = Time.current

      apply_policy_to_running_run!(conversation: conversation, now: now)

      queued = upsert_queued_run!(
        conversation: conversation,
        kind: "force_talk",
        reason: "force_talk",
        speaker_space_membership_id: speaker.id,
        run_after: now,
        debug: { trigger: "force_talk" }
      )

      kick!(queued)
      queued
    end

    def plan_regenerate!(conversation:, target_message:)
      raise ArgumentError, "target_message must belong to conversation" unless target_message.conversation_id == conversation.id
      raise ArgumentError, "target_message must be an assistant message" unless target_message.assistant_message?

      speaker = conversation.space.space_memberships.active.find_by(id: target_message.space_membership_id)
      return nil unless speaker&.can_auto_respond?

      now = Time.current

      # Cancel any running run
      running = ConversationRun.running.find_by(conversation_id: conversation.id)
      running&.request_cancel!(at: now)

      queued = upsert_queued_run!(
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

      kick!(queued)
      queued
    end

    def plan_auto_mode_followup!(conversation:, trigger_message:)
      AutoModePlanner.call(conversation: conversation, trigger_message: trigger_message)
    end

    def plan_copilot_start!(conversation:, copilot_membership:)
      CopilotPlanner.plan_start!(conversation: conversation, copilot_membership: copilot_membership)
    end

    def plan_copilot_followup!(conversation:, trigger_message:)
      CopilotPlanner.plan_followup!(conversation: conversation, trigger_message: trigger_message)
    end

    def plan_copilot_continue!(conversation:, copilot_membership:, trigger_message:)
      CopilotPlanner.plan_continue!(
        conversation: conversation,
        copilot_membership: copilot_membership,
        trigger_message: trigger_message
      )
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

    # Applies the space's policy for handling user input during generation.
    # This is NOT atomic with run creation, but that's acceptable because:
    # - The "restart" policy is best-effort (cancel request may not be honored immediately)
    # - The worst case is that a cancel request is missed, which is the same as before
    def apply_policy_to_running_run!(conversation:, now:)
      running = ConversationRun.running.find_by(conversation_id: conversation.id)
      return unless running

      case conversation.space.during_generation_user_input_policy
      when "restart"
        running.request_cancel!(at: now)
      end
    end

    # Upserts a queued run using optimistic concurrency.
    #
    # If a queued run already exists, updates it with the new parameters.
    # If not, creates a new one. Handles concurrent creation via the unique
    # partial index on (conversation_id) WHERE status = 'queued'.
    #
    # @return [ConversationRun] the created or updated run
    def upsert_queued_run!(conversation:, kind:, reason:, speaker_space_membership_id:, run_after:, debug:)
      attrs = build_run_attrs(
        kind: kind,
        reason: reason,
        speaker_space_membership_id: speaker_space_membership_id,
        run_after: run_after,
        debug: debug
      )

      # Try to find and update existing queued run
      existing = ConversationRun.queued.find_by(conversation_id: conversation.id)
      if existing
        existing.update!(attrs)
        return existing
      end

      # Try to create new run - may fail if concurrent request created one first
      ConversationRun.transaction(requires_new: true) do
        conversation.conversation_runs.create!(attrs)
      end
    rescue ActiveRecord::RecordNotUnique
      # Concurrent creation detected - find and update the winner's run
      existing = ConversationRun.queued.find_by!(conversation_id: conversation.id)
      existing.update!(attrs)
      existing
    end

    # Creates a queued run only if no queued run exists (first-one-wins semantics).
    #
    # Unlike upsert_queued_run!, this does NOT update an existing run.
    # Used for scenarios like auto_mode/copilot where we want "first trigger wins".
    #
    # @return [ConversationRun, nil] the created run, or nil if one already existed
    def create_exclusive_queued_run!(conversation:, kind:, reason:, speaker_space_membership_id:, run_after:, debug:)
      # Early check to avoid unnecessary DB work
      return nil if ConversationRun.queued.exists?(conversation_id: conversation.id)

      attrs = build_run_attrs(
        kind: kind,
        reason: reason,
        speaker_space_membership_id: speaker_space_membership_id,
        run_after: run_after,
        debug: debug
      )

      ConversationRun.transaction(requires_new: true) do
        conversation.conversation_runs.create!(attrs)
      end
    rescue ActiveRecord::RecordNotUnique
      # Another request won the race - return nil per first-one-wins semantics
      nil
    end

    def build_run_attrs(kind:, reason:, speaker_space_membership_id:, run_after:, debug:)
      {
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
