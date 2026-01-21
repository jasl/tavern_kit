# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Starts a new round of conversation.
    #
    # Call this when:
    # - Auto without human is enabled
    # - Auto is enabled and no round active
    # - User manually triggers a new round
    #
    # The command:
    # 1. Cancels any existing queued runs
    # 2. Builds ordered queue of eligible participants
    # 3. Sets up scheduling state
    # 4. Schedules the first speaker's turn
    #
    class StartRound
      # New GitLab-style API: return a structured `ServiceResponse`.
      def self.execute(conversation:, trigger_message: nil, is_user_input: false, rng: Random)
        new(conversation, trigger_message, is_user_input, rng).execute
      end

      def initialize(conversation, trigger_message, is_user_input, rng)
        @conversation = conversation
        @space = conversation.space
        @trigger_message = trigger_message
        @is_user_input = is_user_input
        @rng = rng
      end

      # @return [ServiceResponse]
      def execute
        @conversation.with_lock do
          cancel_existing_runs!

          queue = Queries::ActivatedQueue.execute(
            conversation: @conversation,
            trigger_message: @trigger_message,
            is_user_input: @is_user_input,
            rng: @rng
          )
          queue_ids = queue.map(&:id)
          if queue_ids.empty?
            return ::ServiceResponse.success(reason: :no_eligible_speakers, payload: { started: false })
          end

          speaker = queue.first
          now = Time.current

          supersede_active_round!(at: now)
          round = create_round!(at: now)
          create_participants!(round: round, queue_ids: queue_ids, at: now)

          broadcast_queue_update
          ScheduleSpeaker.execute(conversation: @conversation, speaker: speaker, delay_ms: user_turn_debounce_ms, conversation_round: round)

          ::ServiceResponse.success(
            reason: :round_started,
            payload: {
              started: true,
              round_id: round.id,
              speaker_id: speaker.id,
              queue_size: queue_ids.size,
            }
          )
        end
      end

      private

      def cancel_existing_runs!
        @conversation.conversation_runs.queued.find_each do |run|
          broadcast_typing_off(run.speaker_space_membership_id)

          ConversationEvents::Emitter.emit(
            event_name: "conversation_run.canceled",
            conversation: @conversation,
            space: @space,
            conversation_round_id: run.conversation_round_id,
            conversation_run_id: run.id,
            trigger_message_id: run.debug["trigger_message_id"],
            speaker_space_membership_id: run.speaker_space_membership_id,
            reason: "start_round",
            payload: {
              canceled_by: "start_round",
              previous_status: run.status,
            }
          )

          run.update!(
            status: "canceled",
            finished_at: Time.current,
            debug: run.debug.merge(
              "canceled_by" => "start_round",
              "canceled_at" => Time.current.iso8601
            )
          )
        end
      end

      def broadcast_typing_off(membership_id)
        return unless membership_id

        speaker = @space.space_memberships.find_by(id: membership_id)
        ConversationChannel.broadcast_typing(@conversation, membership: speaker, active: false) if speaker
      end

      def broadcast_queue_update
        Broadcasts.queue_updated(@conversation)
      end

      def user_turn_debounce_ms
        return 0 unless @is_user_input

        @space.user_turn_debounce_ms.to_i
      end

      def supersede_active_round!(at:)
        active = @conversation.conversation_rounds.find_by(status: "active")
        return unless active

        ConversationEvents::Emitter.emit(
          event_name: "turn_scheduler.round_superseded",
          conversation: @conversation,
          space: @space,
          conversation_round_id: active.id,
          trigger_message_id: active.trigger_message_id,
          reason: "start_round",
          payload: {
            ended_reason: "superseded_by_start_round",
            previous_scheduling_state: active.scheduling_state,
          }
        )

        active.update!(
          status: "superseded",
          scheduling_state: nil,
          ended_reason: "superseded_by_start_round",
          finished_at: at
        )
      end

      def create_round!(at:)
        round = ConversationRound.create!(
          conversation: @conversation,
          status: "active",
          scheduling_state: "ai_generating",
          current_position: 0,
          trigger_message: @trigger_message,
          metadata: {
            "reply_order" => @space.reply_order,
            "is_user_input" => @is_user_input,
          },
          created_at: at,
          updated_at: at
        )

        ConversationEvents::Emitter.emit(
          event_name: "turn_scheduler.round_started",
          conversation: @conversation,
          space: @space,
          conversation_round_id: round.id,
          trigger_message_id: @trigger_message&.id,
          reason: @is_user_input ? "user_input" : "auto",
          payload: {
            reply_order: @space.reply_order,
            is_user_input: @is_user_input,
          }
        )

        round
      end

      def create_participants!(round:, queue_ids:, at:)
        queue_ids.each_with_index do |membership_id, idx|
          round.participants.create!(
            space_membership_id: membership_id,
            position: idx,
            status: "pending",
            created_at: at,
            updated_at: at
          )
        end
      end
    end
  end
end
