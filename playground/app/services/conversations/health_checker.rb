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
      @conversation = conversation
      @space = conversation.space
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
      # Check if auto mode is active - should have runs
      return true if @conversation.auto_mode_enabled?

      # Check if there are copilot users who should be responding
      has_copilot = @space.space_memberships.active.any?(&:copilot_full?)
      return false unless has_copilot

      # Check if the last message was from a human (not copilot)
      last_message = @conversation.messages.order(seq: :desc).first
      return false unless last_message

      # If last message was from copilot user, AI should respond
      membership = last_message.space_membership
      return false unless membership

      # If it's a copilot user's message, AI should follow up
      return true if membership.copilot_full?

      # If it's a human's message and we have AI characters, AI should respond
      has_ai_characters = @space.space_memberships.active.ai_characters.exists?
      if membership.human? && has_ai_characters && !@space.manual?
        # Check how long since the last message
        since_last = Time.current - last_message.created_at
        return since_last > IDLE_THRESHOLD
      end

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
          auto_mode_active: @conversation.auto_mode_enabled?,
        },
      }
    end

    def suggest_next_speaker
      # Use TurnScheduler to find who should speak next
      TurnScheduler::Queries::NextSpeaker.call(conversation: @conversation)
    end
  end
end
