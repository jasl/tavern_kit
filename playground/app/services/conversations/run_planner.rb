# frozen_string_literal: true

# Plans and schedules ConversationRuns for AI responses.
#
# ## Unified Scheduler Integration
#
# Most AI response scheduling is now handled by ConversationScheduler, which is
# triggered by Message after_create_commit. This planner is used for:
#
# - create_scheduled_run! - Called by ConversationScheduler to create runs
# - plan_force_talk! - Manual speaker selection (user clicks "Force Talk")
# - plan_regenerate! - Regenerate a specific message
# - plan_user_turn! - Used for delete-and-regenerate scenarios
#
# ## Concurrency Strategy
#
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
    # Plans an AI response triggered by a user message.
    # This is now handled automatically by Message#after_create_commit callback,
    # but kept for testing purposes.
    #
    # @deprecated Use Message callbacks or ConversationScheduler instead
    def plan_from_user_message!(conversation:, user_message:)
      speaker = SpeakerSelector.new(conversation).select_for_user_turn
      return nil unless speaker

      now = Time.current

      apply_policy_to_running_run!(conversation: conversation, now: now)

      # Apply debounce delay from space settings
      debounce_ms = conversation.space.user_turn_debounce_ms.to_i
      run_after = debounce_ms > 0 ? now + (debounce_ms / 1000.0).seconds : now

      queued = upsert_queued_run!(
        conversation: conversation,
        reason: "user_message",
        speaker_space_membership_id: speaker.id,
        run_after: run_after,
        run_type: ConversationRun::AutoTurn,
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
        reason: trigger.to_s,
        speaker_space_membership_id: speaker.id,
        run_after: now,
        run_type: ConversationRun::AutoTurn,
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
        reason: "force_talk",
        speaker_space_membership_id: speaker.id,
        run_after: now,
        run_type: ConversationRun::ForceTalk,
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
        run_type: ConversationRun::Regenerate,
        debug: {
          trigger: "regenerate",
          target_message_id: target_message.id,
          expected_last_message_id: target_message.id,
        }
      )

      kick!(queued)
      queued
    end

    # Create a scheduled run for the ConversationScheduler.
    #
    # This is the interface used by ConversationScheduler to create runs.
    # It handles the run creation and job scheduling.
    #
    # ## Serial Execution
    #
    # If another run is currently executing, the job will NOT be scheduled.
    # Instead, RunFollowups will kick this run when the current run finishes.
    # This ensures serial execution without race conditions.
    #
    # @param conversation [Conversation] the conversation
    # @param speaker [SpaceMembership] the speaker
    # @param run_after [Time] when to execute the run
    # @param reason [String] reason for the run (for debugging)
    # @param run_type [Class] the STI class to use (default: ConversationRun::AutoTurn)
    # @return [ConversationRun, nil] the created run, or nil if creation failed
    def create_scheduled_run!(conversation:, speaker:, run_after:, reason:, run_type: ConversationRun::AutoTurn)
      return nil unless speaker.can_auto_respond?

      queued = create_exclusive_queued_run!(
        conversation: conversation,
        reason: reason,
        speaker_space_membership_id: speaker.id,
        run_after: run_after,
        run_type: run_type,
        debug: {
          trigger: reason,
          scheduled_by: "conversation_scheduler",
          expected_last_message_id: conversation.messages.maximum(:id),
        }
      )

      # If creation returned nil, a queued run already exists - that's fine
      # If another run is currently executing, kick! will NOT schedule the job
      # RunFollowups will kick this run when the current run finishes
      queued ||= ConversationRun.queued.find_by(conversation_id: conversation.id)
      kick!(queued) if queued

      queued
    end

    # Kicks a run by scheduling its job.
    #
    # Only schedules the job if:
    # 1. No other run is currently running for this conversation
    # 2. Or force is true (used by RunFollowups when previous run just finished)
    #
    # This ensures serial execution: jobs are only scheduled when they can actually run.
    #
    # @param run [ConversationRun] the run to kick
    # @param force [Boolean] if true, bypass all checks (used when we KNOW it's safe to run)
    def kick!(run, force: false)
      return unless run
      return if !force && recently_kicked?(run)

      # Don't schedule if there's already a running run (unless forced)
      # This prevents race conditions where multiple jobs try to claim simultaneously
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
    # @param run_type [Class] the STI class to use (default: ConversationRun)
    # @return [ConversationRun] the created or updated run
    def upsert_queued_run!(conversation:, reason:, speaker_space_membership_id:, run_after:, debug:, run_type: ConversationRun)
      attrs = build_run_attrs(
        reason: reason,
        speaker_space_membership_id: speaker_space_membership_id,
        run_after: run_after,
        debug: debug
      )

      # Try to find and update existing queued run
      existing = ConversationRun.queued.find_by(conversation_id: conversation.id)
      if existing
        # Update type if different (to handle run type changes)
        if existing.type != run_type.name
          attrs[:type] = run_type.name
          existing.update!(attrs)
          # Reload with correct STI class after type change
          return ConversationRun.find(existing.id)
        end
        existing.update!(attrs)
        return existing
      end

      # Try to create new run - may fail if concurrent request created one first
      ConversationRun.transaction(requires_new: true) do
        run_type.create!(attrs.merge(conversation: conversation))
      end
    rescue ActiveRecord::RecordNotUnique
      # Concurrent creation detected - find and update the winner's run
      existing = ConversationRun.queued.find_by!(conversation_id: conversation.id)
      if existing.type != run_type.name
        attrs[:type] = run_type.name
        existing.update!(attrs)
        # Reload with correct STI class after type change
        return ConversationRun.find(existing.id)
      end
      existing.update!(attrs)
      existing
    end

    # Creates a queued run only if no queued run exists (first-one-wins semantics).
    #
    # Unlike upsert_queued_run!, this does NOT update an existing run.
    # Used for scenarios like auto_mode/copilot where we want "first trigger wins".
    #
    # @param run_type [Class] the STI class to use (default: ConversationRun)
    # @return [ConversationRun, nil] the created run, or nil if one already existed
    def create_exclusive_queued_run!(conversation:, reason:, speaker_space_membership_id:, run_after:, debug:, run_type: ConversationRun)
      # Early check to avoid unnecessary DB work
      return nil if ConversationRun.queued.exists?(conversation_id: conversation.id)

      attrs = build_run_attrs(
        reason: reason,
        speaker_space_membership_id: speaker_space_membership_id,
        run_after: run_after,
        debug: debug
      )

      ConversationRun.transaction(requires_new: true) do
        # Use the specified STI type
        run_type.create!(attrs.merge(conversation: conversation))
      end
    rescue ActiveRecord::RecordNotUnique
      # Another request won the race - return nil per first-one-wins semantics
      nil
    end

    def build_run_attrs(reason:, speaker_space_membership_id:, run_after:, debug:)
      {
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
