# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Starts a new round of conversation.
    #
    # Call this when:
    # - Auto mode is enabled
    # - Copilot is enabled and no round active
    # - User manually triggers a new round
    #
    # The command:
    # 1. Cancels any existing queued runs
    # 2. Builds ordered queue of eligible participants
    # 3. Sets up scheduling state
    # 4. Schedules the first speaker's turn
    #
    class StartRound
      def self.call(conversation:, trigger_message: nil, is_user_input: false, rng: Random)
        new(conversation, trigger_message, is_user_input, rng).call
      end

      def initialize(conversation, trigger_message, is_user_input, rng)
        @conversation = conversation
        @space = conversation.space
        @trigger_message = trigger_message
        @is_user_input = is_user_input
        @rng = rng
      end

      # @return [Boolean] true if round was started successfully
      def call
        @conversation.with_lock do
          cancel_existing_runs!

          round_id = SecureRandom.uuid
          queue = Queries::ActivatedQueue.call(
            conversation: @conversation,
            trigger_message: @trigger_message,
            is_user_input: @is_user_input,
            rng: @rng
          )
          queue_ids = queue.map(&:id)
          return false if queue_ids.empty?

          position = 0
          spoken_ids = []
          speaker = queue.first

          @conversation.update!(
            scheduling_state: determine_initial_state(speaker),
            current_round_id: round_id,
            current_speaker_id: speaker.id,
            round_position: position,
            round_spoken_ids: spoken_ids,
            round_queue_ids: queue_ids
          )

          broadcast_queue_update
          ScheduleSpeaker.call(conversation: @conversation, speaker: speaker, delay_ms: user_turn_debounce_ms)

          true
        end
      end

      private

      def cancel_existing_runs!
        @conversation.conversation_runs.queued.find_each do |run|
          broadcast_typing_off(run.speaker_space_membership_id)
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

      def determine_initial_state(speaker)
        # Note: TurnScheduler only queues auto-respondable speakers (AI + Copilot full),
        # so speaker.can_auto_respond? should always be true here.
        speaker.can_auto_respond? ? "ai_generating" : "waiting_for_speaker"
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
    end
  end
end
