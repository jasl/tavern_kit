# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Schedules the current speaker's turn.
    #
    # For AI/Auto: Creates a ConversationRun and schedules the job.
    #
    # Note: pure humans are not part of the TurnScheduler queue (ST/Risu-aligned),
    # so this command should only be called with auto-responding speakers.
    #
    class ScheduleSpeaker
      def self.call(conversation:, speaker:, delay_ms: 0, conversation_round: nil, include_auto_without_human_delay: true)
        new(conversation, speaker, delay_ms, conversation_round, include_auto_without_human_delay).call
      end

      def initialize(conversation, speaker, delay_ms, conversation_round, include_auto_without_human_delay)
        @conversation = conversation
        @space = conversation.space
        @speaker = speaker
        @delay_ms = delay_ms
        @conversation_round = conversation_round
        @include_auto_without_human_delay = include_auto_without_human_delay
      end

      # @return [ConversationRun, nil] the created run, or nil if no run created
      def call
        return nil unless @speaker
        return nil unless @speaker.can_auto_respond?

        schedule_ai_turn
      end

      private

      def schedule_ai_turn
        delay_ms = 0
        delay_ms += @space.auto_without_human_delay_ms.to_i if @include_auto_without_human_delay && automation_enabled?
        delay_ms += @delay_ms.to_i

        run_after = Time.current + (delay_ms / 1000.0)

        kind = @speaker.auto_enabled? ? "auto_user_response" : "auto_response"

        run = create_run(kind: kind, run_after: run_after)
        kick_run(run) if run

        run
      end

      # Check if any automated scheduling is enabled (auto_without_human or Auto)
      def automation_enabled?
        @conversation.auto_without_human_enabled? || any_auto_active?
      end

      def any_auto_active?
        @space.space_memberships.active.any?(&:auto_enabled?)
      end

      def create_run(kind:, run_after:, debug: {})
        # Check for existing queued run
        return nil if ConversationRun.queued.exists?(conversation_id: @conversation.id)

        round_id = @conversation_round&.id
        return nil if round_id.blank?

        expected_last_message_id =
          Message
            .where(conversation_id: @conversation.id)
            .scheduler_visible
            .order(seq: :desc, id: :desc)
            .limit(1)
            .pick(:id)

        ConversationRun.create!(
          conversation: @conversation,
          conversation_round_id: round_id,
          speaker_space_membership_id: @speaker.id,
          kind: kind,
          status: "queued",
          reason: kind,
          run_after: run_after,
          debug: (debug || {})
            .merge(
              trigger: kind,
              scheduled_by: "turn_scheduler",
              expected_last_message_id: expected_last_message_id
            )
            .compact
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
