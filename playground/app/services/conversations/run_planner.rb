# frozen_string_literal: true

# Plans and schedules ConversationRuns for AI responses.
#
# ## TurnScheduler Integration
#
# Most AI response scheduling is now handled by TurnScheduler, which is
# triggered by Message after_create_commit. This planner is used for:
#
# - plan_force_talk! - Manual speaker selection (user clicks "Force Talk")
# - plan_regenerate! - Regenerate a specific message
#
# ## Concurrency Strategy
#
# Uses optimistic concurrency control instead of pessimistic locking.
# The database has unique partial indexes that ensure:
# - Only one queued run per conversation
# - Only one running run per conversation
#
class Conversations::RunPlanner
  KICK_DEDUP_WINDOW_MS = 2000

  class << self
    # Creates and schedules a new queued run for a specific speaker.
    #
    # This is a low-level helper used by controller actions (e.g. retrying a failed run)
    # and any code path that wants to explicitly enqueue "the same speaker should speak again".
    #
    # NOTE: This differs from the "plan_*" methods:
    # - plan_* methods intentionally upsert the single-slot queued run (overwrite semantics)
    # - create_scheduled_run! will NOT overwrite an existing queued run (it returns nil)
    #
    # @param conversation [Conversation]
    # @param speaker [SpaceMembership]
    # @param run_after [Time]
    # @param reason [String]
    # @param kind [String] one of ConversationRun::KINDS
    # @param debug [Hash]
    # @return [ConversationRun, nil]
    def create_scheduled_run!(conversation:, speaker:, run_after:, reason:, kind:, debug: {})
      return nil unless conversation
      return nil unless speaker&.can_auto_respond?
      return nil if ConversationRun.queued.exists?(conversation_id: conversation.id)

      attrs = build_run_attrs(
        reason: reason.to_s,
        speaker_space_membership_id: speaker.id,
        run_after: run_after || Time.current,
        kind: kind.to_s,
        debug: (debug || {}).merge(
          trigger: reason.to_s,
          scheduled_by: "run_planner"
        )
      )

      run = ConversationRun.transaction(requires_new: true) do
        ConversationRun.create!(attrs.merge(conversation: conversation))
      end

      kick!(run)
      run
    rescue ActiveRecord::RecordNotUnique
      # Another request won the race (single-slot queue constraint).
      nil
    end

    def plan_force_talk!(conversation:, speaker_space_membership_id:)
      return nil unless speaker_space_membership_id

      membership = conversation.space.space_memberships.active.find_by(id: speaker_space_membership_id)
      return nil unless membership&.can_auto_respond?

      now = Time.current

      apply_policy_to_running_run!(conversation: conversation, now: now)

      queued = upsert_queued_run!(
        conversation: conversation,
        reason: "force_talk",
        speaker_space_membership_id: membership.id,
        run_after: now,
        kind: "force_talk",
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
        reason: "regenerate",
        speaker_space_membership_id: speaker.id,
        run_after: now,
        kind: "regenerate",
        debug: {
          trigger: "regenerate",
          target_message_id: target_message.id,
          expected_last_message_id: target_message.id,
        }
      )

      kick!(queued)
      queued
    end

    # Kicks a run by scheduling its job.
    #
    # Only schedules the job if:
    # 1. No other run is currently running for this conversation
    # 2. Or force is true (used by RunFollowups when previous run just finished)
    def kick!(run, force: false)
      return unless run
      return if !force && recently_kicked?(run)

      # Don't schedule if there's already a running run (unless forced)
      unless force
        running_exists = ConversationRun.running.exists?(conversation_id: run.conversation_id)
        if running_exists
          Rails.logger.info "[RunPlanner] Skipping kick for #{run.id} - another run is already running"
          return
        end
      end

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
    def apply_policy_to_running_run!(conversation:, now:)
      running = ConversationRun.running.find_by(conversation_id: conversation.id)
      return unless running

      case conversation.space.during_generation_user_input_policy
      when "restart"
        running.request_cancel!(at: now)
      end
    end

    # Upserts a queued run using optimistic concurrency.
    def upsert_queued_run!(conversation:, reason:, speaker_space_membership_id:, run_after:, kind:, debug:)
      attrs = build_run_attrs(
        reason: reason,
        speaker_space_membership_id: speaker_space_membership_id,
        run_after: run_after,
        kind: kind,
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
        ConversationRun.create!(attrs.merge(conversation: conversation))
      end
    rescue ActiveRecord::RecordNotUnique
      # Concurrent creation detected - find and update the winner's run
      existing = ConversationRun.queued.find_by!(conversation_id: conversation.id)
      existing.update!(attrs)
      existing
    end

    def build_run_attrs(reason:, speaker_space_membership_id:, run_after:, kind:, debug:)
      {
        status: "queued",
        reason: reason,
        kind: kind,
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
