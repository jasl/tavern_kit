# frozen_string_literal: true

# Checks the health status of a conversation's run state.
#
# Used for frontend polling to detect issues like:
# - Stuck runs (running too long)
# - Failed runs that need attention
# - Missing runs (should be running but isn't)
#
# @example
#   result = Conversations::HealthChecker.check(conversation)
#   result[:status] # => "healthy", "stuck", "failed", "idle_unexpected"
#   result[:action] # => "none", "retry", "generate"
#
module Conversations
  class HealthChecker
    # How long before a running run is considered "stuck" for health check
    STUCK_THRESHOLD = 30.seconds

    # How long after the last message before we consider it "idle" when it shouldn't be
    IDLE_THRESHOLD = 10.seconds

    class << self
      def check(conversation)
        new(conversation).check
      end
    end

    def initialize(conversation)
      # Always reload to ensure we have the latest state from the database.
      # This is critical because:
      # 1. The conversation instance may be stale (e.g., loaded in controller before background job updated it)
      # 2. auto_without_human_remaining_rounds may have been decremented by TurnScheduler in another process
      # 3. Using stale data can cause false "idle_unexpected" alerts
      @conversation = conversation.reload
      @space = @conversation.space
    end

    def check
      # Check for running run that might be stuck
      running_run = @conversation.conversation_runs.running.first
      if running_run
        return check_running_run(running_run)
      end

      # Check for queued run that should have started
      queued_run = @conversation.conversation_runs.queued.first
      if queued_run
        return check_queued_run(queued_run)
      end

      turn_state = TurnScheduler.state(@conversation)

      # Explicit pause: no runs are expected while paused.
      if turn_state.paused?
        return paused_status
      end

      # If TurnScheduler is explicitly in failed state, treat it as failed until resolved.
      if turn_state.failed?
        last_failed = @conversation.conversation_runs.failed.order(finished_at: :desc).first
        return failed_run_status(last_failed)
      end

      # Inconsistency repair:
      # If TurnScheduler says we are ai_generating but there are no active runs,
      # the scheduler likely missed the message advancement callback (or a previous
      # deployment left stale state behind). Try to reconcile using the last succeeded
      # turn_scheduler run for the active round/speaker.
      if turn_state.ai_generating?
        repaired = reconcile_ai_generating_without_active_run!(turn_state)
        if repaired
          @conversation.reload
          turn_state = TurnScheduler.state(@conversation)
        else
          return idle_unexpected_status
        end
      end

      # Check for recent failed run
      recent_failed = @conversation.conversation_runs.failed.order(finished_at: :desc).first
      if recent_failed && recent_failed.finished_at && recent_failed.finished_at > 1.minute.ago
        return failed_run_status(recent_failed)
      end

      # Check if conversation should have activity but doesn't
      if should_have_activity?
        return idle_unexpected_status
      end

      healthy_status
    end

    private

    attr_reader :conversation, :space

    def check_running_run(run)
      duration = Time.current - (run.started_at || run.created_at)
      last_activity = run.heartbeat_at || run.started_at || run.created_at
      since_last_activity = Time.current - last_activity

      # Check if stuck (no heartbeat for too long)
      if since_last_activity > STUCK_THRESHOLD
        return stuck_run_status(run, duration)
      end

      # Running normally
      running_status(run, duration)
    end

    def check_queued_run(run)
      # If queued for too long, might be stuck
      queued_duration = Time.current - run.created_at

      if queued_duration > STUCK_THRESHOLD
        return stuck_queued_status(run, queued_duration)
      end

      # Queued and waiting - this is normal
      queued_status(run, queued_duration)
    end

    def should_have_activity?
      # Check if auto-without-human is active - should have runs
      return true if @conversation.auto_without_human_enabled?

      # Check if the last message was from a human (not auto)
      last_message = @conversation.messages.order(seq: :desc).first
      return false unless last_message

      membership = last_message.space_membership
      return false unless membership

      # If the last message was AI-generated (has conversation_run_id) and its round
      # completed normally, no further activity is expected. The round system already
      # handled who should speak; we shouldn't trigger "idle" alerts for completed rounds.
      if last_message.conversation_run_id.present?
        run = @conversation.conversation_runs.find_by(id: last_message.conversation_run_id)
        if run&.succeeded?
          round = @conversation.conversation_rounds.find_by(id: run.conversation_round_id)
          return false if round&.finished? && round&.ended_reason == "round_complete"
        end
      end

      # Check if there are auto users who should be responding
      has_auto = @space.space_memberships.active.any? { |m| m.user? && m.auto_enabled? && m.can_auto_respond? }

      # If it's an auto user's message, AI should follow up
      return true if has_auto && membership.auto_enabled?

      # If it's a human's message and we have AI characters, AI should respond
      # (applies to both auto and non-auto scenarios)
      has_ai_characters = @space.space_memberships.active.ai_characters.exists?
      if membership.human? && has_ai_characters && !@space.manual?
        # Check how long since the last message
        since_last = Time.current - last_message.created_at
        return since_last > IDLE_THRESHOLD
      end

      false
    end

    def reconcile_ai_generating_without_active_run!(turn_state)
      return false if ConversationRun.active.exists?(conversation_id: @conversation.id)

      active_round = @conversation.conversation_rounds.find_by(status: "active")
      return false unless active_round&.scheduling_state == "ai_generating"

      speaker_id = turn_state.current_speaker_id
      return false unless speaker_id

      speaker = @space.space_memberships.find_by(id: speaker_id)
      return false unless speaker

      participant = active_round.participants.find_by(position: active_round.current_position.to_i)
      return false unless participant&.pending?
      return false unless participant.space_membership_id == speaker_id

      run =
        @conversation
          .conversation_runs
          .succeeded
          .where(conversation_round_id: active_round.id, speaker_space_membership_id: speaker_id)
          .order(finished_at: :desc, id: :desc)
          .first

      return false unless run
      return false unless run.debug&.dig("scheduled_by") == "turn_scheduler"

      message_id =
        @conversation
          .messages
          .where(conversation_run_id: run.id)
          .order(seq: :desc, id: :desc)
          .limit(1)
          .pick(:id)

      return false unless message_id

      Rails.logger.warn(
        "[HealthChecker] Reconciling ai_generating state with no active run: " \
        "conversation_id=#{@conversation.id} run_id=#{run.id} round_id=#{active_round.id} message_id=#{message_id}"
      )

      TurnScheduler.advance_turn!(@conversation, speaker, message_id: message_id)
      true
    rescue StandardError => e
      Rails.logger.error("[HealthChecker] Failed to reconcile stuck ai_generating state: #{e.class}: #{e.message}")
      false
    end

    def healthy_status
      {
        status: "healthy",
        message: I18n.t("conversations.health.healthy", default: "Conversation is healthy."),
        action: "none",
        details: {},
      }
    end

    def paused_status
      active_round = @conversation.conversation_rounds.find_by(status: "active", scheduling_state: "paused")
      paused_reason = active_round&.metadata&.dig("paused_reason")

      turn_state = TurnScheduler.state(@conversation)
      paused_speaker = turn_state.current_speaker

      {
        status: "healthy",
        message: I18n.t("conversations.health.paused", default: "Conversation is paused."),
        action: "none",
        details: {
          paused_reason: paused_reason,
          paused_speaker_id: paused_speaker&.id,
          paused_speaker_name: paused_speaker&.display_name,
        }.compact,
      }
    end

    def running_status(run, duration)
      speaker = @space.space_memberships.find_by(id: run.speaker_space_membership_id)
      {
        status: "healthy",
        message: I18n.t("conversations.health.running",
                        speaker: speaker&.display_name || "AI",
                        default: "%{speaker} is generating a response..."),
        action: "none",
        details: {
          run_id: run.id,
          speaker_name: speaker&.display_name,
          duration_seconds: duration.to_i,
        },
      }
    end

    def queued_status(run, duration)
      speaker = @space.space_memberships.find_by(id: run.speaker_space_membership_id)
      {
        status: "healthy",
        message: I18n.t("conversations.health.queued",
                        speaker: speaker&.display_name || "AI",
                        default: "Waiting for %{speaker} to respond..."),
        action: "none",
        details: {
          run_id: run.id,
          speaker_name: speaker&.display_name,
          queued_seconds: duration.to_i,
        },
      }
    end

    def stuck_run_status(run, duration)
      speaker = @space.space_memberships.find_by(id: run.speaker_space_membership_id)
      {
        status: "stuck",
        message: I18n.t("conversations.health.stuck",
                        speaker: speaker&.display_name || "AI",
                        seconds: duration.to_i,
                        default: "%{speaker}'s response seems stuck (%{seconds}s)."),
        action: "retry",
        details: {
          run_id: run.id,
          run_status: run.status,
          speaker_name: speaker&.display_name,
          duration_seconds: duration.to_i,
        },
      }
    end

    def stuck_queued_status(run, duration)
      speaker = @space.space_memberships.find_by(id: run.speaker_space_membership_id)
      {
        status: "stuck",
        message: I18n.t("conversations.health.stuck_queued",
                        speaker: speaker&.display_name || "AI",
                        seconds: duration.to_i,
                        default: "%{speaker}'s turn has been waiting too long (%{seconds}s)."),
        action: "retry",
        details: {
          run_id: run.id,
          run_status: run.status,
          speaker_name: speaker&.display_name,
          queued_seconds: duration.to_i,
        },
      }
    end

    def failed_run_status(run)
      unless run
        return {
          status: "failed",
          message: I18n.t("conversations.health.failed",
                          speaker: "AI",
                          error: "Unknown error",
                          default: "Conversation is in a failed state. Click Retry to try again."),
          action: "retry",
          details: {},
        }
      end

      speaker = @space.space_memberships.find_by(id: run.speaker_space_membership_id)
      error_message = run.error&.dig("message") || run.error&.dig("code") || "Unknown error"
      {
        status: "failed",
        message: I18n.t("conversations.health.failed",
                        speaker: speaker&.display_name || "AI",
                        error: error_message,
                        default: "%{speaker}'s response failed: %{error}"),
        action: "retry",
        details: {
          run_id: run.id,
          run_status: run.status,
          speaker_name: speaker&.display_name,
          error: run.error,
        },
      }
    end

    def idle_unexpected_status
      # Determine who should be responding
      suggested_speaker = suggest_next_speaker
      {
        status: "idle_unexpected",
        message: I18n.t("conversations.health.idle_unexpected",
                        default: "Conversation seems stuck. No AI is responding."),
        action: "generate",
        details: {
          suggested_speaker_id: suggested_speaker&.id,
          suggested_speaker_name: suggested_speaker&.display_name,
          auto_without_human_active: @conversation.auto_without_human_enabled?,
        },
      }
    end

    def suggest_next_speaker
      # Use TurnScheduler to find who should speak next
      TurnScheduler::Queries::NextSpeaker.call(conversation: @conversation)
    end
  end
end
