# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Marks the current round as failed (without clearing round state).
    #
    # This is used for "unexpected/exception" failures (LLM/provider/network/etc).
    # It pauses the scheduler so a human can decide what to do (Retry/Stop/Skip).
    #
    # Note: UI error surfaces are handled by RunExecutor (run_failed toast) and
    # RunFollowups (run_error_alert). This command only mutates scheduling state
    # and emits a queue update broadcast.
    class HandleFailure
      def self.call(conversation:, run:, error: nil)
        new(conversation, run, error).call
      end

      def initialize(conversation, run, error)
        @conversation = conversation
        @space = conversation.space
        @run = run
        @error = error
      end

      # @return [Boolean] true if handled successfully
      def call
        handled = false
        disabled_auto_memberships = []

        @conversation.with_lock do
          active_round = @conversation.conversation_rounds.find_by(status: "active")
          next false unless active_round
          next false unless @run
          next false unless @run.debug&.dig("scheduled_by") == "turn_scheduler"
          next false if current_speaker_id(active_round) != @run.speaker_space_membership_id

          run_round_id = @run.conversation_round_id
          next false if run_round_id.blank?
          next false if active_round.id != run_round_id

          cancel_queued_runs
          stop_automations!(disabled_auto_memberships)
          active_round.update!(scheduling_state: "failed")
          handled = true
        end

        disabled_auto_memberships.each do |membership|
          Messages::Broadcasts.broadcast_auto_disabled(membership, reason: "turn_failed")
        end

        Broadcasts.queue_updated(@conversation) if handled
        handled
      end

      private

      def cancel_queued_runs
        @conversation.conversation_runs.queued.find_each do |queued|
          queued.update!(
            status: "canceled",
            finished_at: Time.current,
            debug: (queued.debug || {}).merge(
              "canceled_by" => "handle_failure",
              "canceled_at" => Time.current.iso8601
            )
          )
        end
      end

      def current_speaker_id(active_round)
        position = active_round.current_position.to_i
        active_round.participants.find_by(position: position)&.space_membership_id
      end

      def stop_automations!(disabled_auto_memberships)
        @conversation.stop_auto_without_human! if @conversation.auto_without_human_enabled?

        now = Time.current
        @space.space_memberships.where(kind: "human").where.not(auto: "none").find_each do |membership|
          # Disable Auto without triggering SpaceMembership after_commit broadcasts.
          # HandleFailure is already the single source of truth for queue_updated here.
          membership.update_columns(auto: "none", auto_remaining_steps: nil, updated_at: now)
          disabled_auto_memberships << membership
        end
      end
    end
  end
end
