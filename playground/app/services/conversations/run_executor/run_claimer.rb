# frozen_string_literal: true

# Claims a queued ConversationRun for execution using optimistic concurrency.
#
# This class encapsulates:
# - queued → running claim (atomic UPDATE)
# - stale running run detection + preemption handling
# - expected_last_message_id guard (skip when conversation advanced)
#
# NOTE: Concurrency invariants are DB-enforced via partial unique indexes:
# - at most 1 running run per conversation
# - at most 1 queued run per conversation
#
class Conversations::RunExecutor::RunClaimer
  def initialize(run_id:)
    @run_id = run_id
  end

  # @return [ConversationRun, nil] the claimed run, or nil if claim failed
  def claim!
    now = Time.current
    stale_running_run_id = nil

    # First, load the run to check preconditions
    run = ConversationRun.find_by(id: @run_id)
    return nil unless run
    return nil unless run.queued?
    return nil unless run.ready_to_run?(now)

    # Check for existing running run (without lock)
    running = ConversationRun.running.find_by(conversation_id: run.conversation_id)
    if running
      if running.stale?(now: now)
        # Mark stale run as failed
        fail_stale_run!(running, now: now)
        stale_running_run_id = running.id
      else
        # Another run is actively running - can't claim
        return nil
      end
    end

    # Check expected_last_message_id constraint
    expected_last_message_id = run.debug&.dig("expected_last_message_id")
    if expected_last_message_id.present?
      last_id = Message
        .where(conversation_id: run.conversation_id)
        .scheduler_visible
        .order(seq: :desc, id: :desc)
        .limit(1)
        .pick(:id)

      if last_id != expected_last_message_id.to_i
        run.skipped!(
          at: now,
          error: {
            "code" => "expected_last_message_mismatch",
            "expected_last_message_id" => expected_last_message_id,
            "actual_last_message_id" => last_id,
          }
        )

        if run.regenerate?
          ConversationChannel.broadcast_run_skipped(
            run.conversation,
            reason: "message_mismatch",
            message: I18n.t(
              "messages.regenerate_skipped",
              default: "Conversation advanced; regenerate skipped."
            )
          )
        else
          # For other run types, notify scheduler to advance to next speaker
          notify_scheduler_run_skipped!(run)
        end

        return nil
      end
    end

    # Check speaker is present
    unless run.speaker_space_membership_id.present?
      run.skipped!(at: now, error: { "code" => "missing_speaker" })
      notify_scheduler_run_skipped!(run)
      return nil
    end

    # Check speaker is still eligible to run.
    #
    # This is critical for "environment-driven" changes like removing/muting the current speaker
    # after the queued run was created. Without this, the job can raise "Speaker not found"
    # and leave the conversation stuck (because failed runs do not auto-advance).
    conversation = run.conversation
    speaker =
      SpaceMembership.find_by(
        id: run.speaker_space_membership_id,
        space_id: conversation&.space_id
      )

    scheduled_by = run.debug&.dig("scheduled_by")
    eligible =
      if scheduled_by == "turn_scheduler"
        speaker&.can_be_scheduled?
      else
        speaker&.can_auto_respond?
      end

    unless eligible
      run.skipped!(
        at: now,
        error: {
          "code" => "speaker_unavailable",
          "scheduled_by" => scheduled_by,
          "speaker_space_membership_id" => run.speaker_space_membership_id,
        }
      )

      notify_scheduler_run_skipped!(run)
      return nil
    end

    # Attempt atomic transition: queued → running
    # The unique partial index ensures only one running run per conversation
    updated_count = ConversationRun
      .where(id: @run_id, status: "queued")
      .update_all(
        status: "running",
        started_at: now,
        cancel_requested_at: nil,
        heartbeat_at: now,
        updated_at: now
      )

    finalize_stale_run!(stale_running_run_id, at: now) if stale_running_run_id
    return nil if updated_count == 0

    # Reload to get updated state
    run.reload
    run
  rescue ActiveRecord::RecordNotUnique
    # Another run claimed running status first (via unique index)
    nil
  end

  private

  # Notifies the scheduler that a run was skipped.
  #
  # When a run is skipped (e.g., due to message mismatch), we need to
  # tell the scheduler to advance to the next speaker. Otherwise, the
  # conversation can get stuck with no one scheduled to speak.
  #
  # @param run [ConversationRun] the skipped run
  def notify_scheduler_run_skipped!(run)
    return unless run.conversation
    # Don't notify scheduler for regenerate - it's a standalone operation
    return if run.regenerate?

    conversation = run.conversation
    return unless conversation

    # For turn_scheduler-managed runs, "skip" should advance the round to avoid stuck state.
    if run.debug&.dig("scheduled_by") == "turn_scheduler"
      round_id = run.conversation_round_id
      if round_id.blank?
        Rails.logger.error "[RunClaimer] Missing conversation_round_id for turn_scheduler-managed run #{run.id}"
        TurnScheduler::Broadcasts.queue_updated(conversation)
        return
      end

      advanced =
        TurnScheduler::Commands::SkipCurrentSpeaker.call(
          conversation: conversation,
          speaker_id: run.speaker_space_membership_id,
          reason: "run_skipped",
          expected_round_id: round_id,
          cancel_running: false
        )

      return if advanced
    end

    # Fallback: broadcast queue update to notify clients.
    TurnScheduler::Broadcasts.queue_updated(conversation)
  rescue StandardError => e
    Rails.logger.error "[RunClaimer] Failed to notify scheduler after skip: #{e.message}"
  end

  # Marks a stale running run as failed.
  # Uses conditional UPDATE to avoid race conditions.
  #
  # @param running [ConversationRun] the stale run
  # @param now [Time] the timestamp
  def fail_stale_run!(running, now:)
    # Build the error hash - will be serialized as JSONB by ActiveRecord
    error_data = {
      "code" => "stale_running_run",
      "message" => "Run became stale while running",
      "stale_timeout_seconds" => ConversationRun::STALE_TIMEOUT.to_i,
      "heartbeat_at" => running.heartbeat_at&.iso8601,
    }

    ConversationRun
      .where(id: running.id, status: "running")
      .update_all(
        status: "failed",
        finished_at: now,
        cancel_requested_at: now,
        error: error_data,
        updated_at: now
      )
  end

  # Finalize a stale run that was preempted by a new queued run.
  # Cleans up orphaned messages and broadcasts UI feedback.
  #
  # @param stale_run_id [String] the ID of the stale run
  # @param at [Time] the timestamp for updates
  def finalize_stale_run!(stale_run_id, at:)
    stale_run = ConversationRun.find_by(id: stale_run_id)
    return unless stale_run

    user_message = I18n.t(
      "messages.generation_errors.stale_running_run",
      default: "Generation timed out. Please try again."
    )

    # Clean up any messages stuck in "generating" status from the stale run.
    Message
      .where(conversation_run_id: stale_run_id)
      .where(generation_status: "generating")
      .find_each do |msg|
        msg.update!(
          generation_status: "failed",
          content: msg.content.presence || user_message,
          metadata: (msg.metadata || {}).merge("error" => user_message),
          updated_at: at
        )
        msg.broadcast_update
      end

    # Broadcast UI feedback for the stale run:
    # Order matters: first clear the old typing, then the new run starts typing
    # 1. run_failed: show toast notification to user
    # 2. stream_complete: clear typing indicator for the stale run's speaker
    stale_conversation = stale_run.conversation
    return unless stale_conversation

    ConversationChannel.broadcast_run_failed(
      stale_conversation,
      code: "stale_preempted",
      user_message: user_message
    )

    if stale_run.speaker_space_membership_id
      ConversationChannel.broadcast_stream_complete(
        stale_conversation,
        space_membership_id: stale_run.speaker_space_membership_id
      )
    end
  end
end
