# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Schedules the current speaker's turn.
    #
    # For AI/Copilot: Creates a ConversationRun and schedules the job
    # For Human + Auto mode: Schedules a timeout job to skip them
    # For Human only: Does nothing (waits for their message)
    #
    class ScheduleSpeaker
      HUMAN_SKIP_DELAY_SECONDS = 10

      def self.call(conversation:, speaker:)
        new(conversation, speaker).call
      end

      def initialize(conversation, speaker)
        @conversation = conversation
        @space = conversation.space
        @speaker = speaker
      end

      # @return [ConversationRun, nil] the created run, or nil if no run created
      def call
        return nil unless @speaker

        if @speaker.can_auto_respond?
          schedule_ai_turn
        elsif @conversation.auto_mode_enabled?
          schedule_human_skip_timeout
          nil
        else
          # Human without auto mode - just wait
          nil
        end
      end

      private

      def schedule_ai_turn
        return nil unless @speaker.can_auto_respond?

        delay_ms = @conversation.auto_mode_enabled? ? @space.auto_mode_delay_ms.to_i : 0
        run_after = Time.current + (delay_ms / 1000.0)

        kind = @speaker.copilot_full? ? "copilot_response" : "auto_response"

        run = create_run(kind: kind, run_after: run_after)
        kick_run(run) if run

        # Show typing indicator immediately
        ConversationChannel.broadcast_typing(@conversation, membership: @speaker, active: true) if run

        run
      end

      def schedule_human_skip_timeout
        timeout_seconds = (@space.auto_mode_delay_ms.to_i / 1000.0) + HUMAN_SKIP_DELAY_SECONDS

        run = create_run(
          kind: "human_turn",
          run_after: Time.current,
          debug: {
            round_id: @conversation.current_round_id,
            timeout_seconds: timeout_seconds,
          }
        )

        if run
          HumanTurnTimeoutJob.set(wait: timeout_seconds.seconds).perform_later(
            run.id,
            @conversation.current_round_id
          )

          Rails.logger.info "[TurnScheduler] Scheduled HumanTurn for #{@speaker.display_name} with #{timeout_seconds}s timeout"
        end

        run
      end

      def create_run(kind:, run_after:, debug: {})
        # Check for existing queued run
        return nil if ConversationRun.queued.exists?(conversation_id: @conversation.id)

        ConversationRun.create!(
          conversation: @conversation,
          speaker_space_membership_id: @speaker.id,
          kind: kind,
          status: "queued",
          reason: kind,
          run_after: run_after,
          debug: debug.merge(
            trigger: kind,
            scheduled_by: "turn_scheduler"
          )
        )
      rescue ActiveRecord::RecordNotUnique
        # Another request won the race
        nil
      end

      def kick_run(run)
        return unless run

        # Don't schedule if there's already a running run
        return if ConversationRun.running.exists?(conversation_id: @conversation.id)

        if run.run_after.present? && run.run_after.future?
          ConversationRunJob.set(wait_until: run.run_after).perform_later(run.id)
        else
          ConversationRunJob.perform_later(run.id)
        end

        record_kick(run)
      end

      def record_kick(run)
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
end
