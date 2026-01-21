# frozen_string_literal: true

module TurnScheduler
  module Queries
    # Returns a structured snapshot of the current scheduling domain state.
    #
    # This is intended for:
    # - UI/debug panels
    # - presenters (to avoid ad-hoc queries and state inference)
    # - tests (as an assertable contract instead of string logs)
    #
    # It intentionally returns a simple immutable Struct with small helper methods.
    class DebugSnapshot
      Snapshot = Struct.new(
        :conversation,
        :space,
        :turn_state,
        :active_round,
        :participants,
        :active_run,
        :queue_members,
        :any_auto_active,
        keyword_init: true
      ) do
        def scheduling_state
          turn_state.scheduling_state
        end

        def current_speaker
          turn_state.current_speaker || active_run&.speaker_space_membership
        end

        def idle?
          scheduling_state == "idle"
        end

        def ai_generating?
          scheduling_state == "ai_generating"
        end

        def failed?
          scheduling_state == "failed"
        end

        def paused?
          scheduling_state == "paused"
        end

        def automation_active?
          conversation.auto_without_human_enabled? || any_auto_active
        end

        def resume_blocked?
          paused? && active_run.present?
        end
      end

      def self.execute(conversation:, limit: 10)
        new(conversation, limit).execute
      end

      def initialize(conversation, limit)
        @conversation = conversation
        @space = conversation.space
        @limit = limit
      end

      def execute
        state = TurnScheduler.state(@conversation)

        Instrumentation.profile(
          "DebugSnapshot",
          conversation_id: @conversation.id,
          reply_order: @space.reply_order,
          scheduling_state: state.scheduling_state,
          limit: @limit
        ) do
          active_round = @conversation.conversation_rounds.find_by(status: "active")
          participants =
            if active_round
              # Used by manage-round modal; eager load to avoid N+1.
              active_round.participants
                .includes(space_membership: %i[user character])
                .order(:position)
                .to_a
            else
              []
            end

          active_run = @conversation.conversation_runs
            .active
            .by_status_priority
            .includes(:speaker_space_membership)
            .first

          queue_members = TurnScheduler::Queries::QueuePreview.execute(conversation: @conversation, limit: @limit)

          any_auto_active = @space.space_memberships
            .active
            .where(kind: "human", auto: "auto")
            .where("auto_remaining_steps > 0")
            .exists?

          Snapshot.new(
            conversation: @conversation,
            space: @space,
            turn_state: state,
            active_round: active_round,
            participants: participants,
            active_run: active_run,
            queue_members: queue_members,
            any_auto_active: any_auto_active
          )
        end
      end
    end
  end
end
