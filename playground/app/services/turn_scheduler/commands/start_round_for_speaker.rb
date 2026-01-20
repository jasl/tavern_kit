# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Starts a new active round with a single, explicitly chosen speaker.
    #
    # Used by the group chat toolbar "Add speaker" when the conversation is idle.
    #
    # - Creates an active round
    # - Persists a one-slot participant queue (position 0)
    # - Schedules the speaker immediately (no auto_without_human_delay_ms)
    #
    # @return [ConversationRun, nil] the created run (queued), or nil if not started
    class StartRoundForSpeaker
      def self.call(conversation:, speaker_id:, reason: "start_round_for_speaker")
        new(conversation, speaker_id, reason).call
      end

      def initialize(conversation, speaker_id, reason)
        @conversation = conversation
        @space = conversation.space
        @speaker_id = speaker_id
        @reason = reason.to_s
      end

      def call
        run = nil

        @conversation.with_lock do
          cancel_existing_runs!

          speaker = @space.space_memberships.find_by(id: @speaker_id)
          next nil unless speaker&.can_be_scheduled?

          now = Time.current

          supersede_active_round!(at: now)
          round = create_round!(at: now, speaker_id: speaker.id)
          create_participant!(round: round, speaker_id: speaker.id, at: now)

          run = ScheduleSpeaker.call(
            conversation: @conversation,
            speaker: speaker,
            conversation_round: round,
            include_auto_without_human_delay: false
          )

          Broadcasts.queue_updated(@conversation)
        end

        run
      end

      private

      def cancel_existing_runs!
        @conversation.conversation_runs.queued.find_each do |run|
          run.update!(
            status: "canceled",
            finished_at: Time.current,
            debug: (run.debug || {}).merge(
              "canceled_by" => @reason,
              "canceled_at" => Time.current.iso8601
            )
          )
        end
      end

      def supersede_active_round!(at:)
        active = @conversation.conversation_rounds.find_by(status: "active")
        return unless active

        active.update!(
          status: "superseded",
          scheduling_state: nil,
          ended_reason: "superseded_by_#{@reason}",
          finished_at: at
        )
      end

      def create_round!(at:, speaker_id:)
        ConversationRound.create!(
          conversation: @conversation,
          status: "active",
          scheduling_state: "ai_generating",
          current_position: 0,
          metadata: {
            "reply_order" => @space.reply_order,
            "started_by" => @reason,
            "explicit_speaker_id" => speaker_id,
          },
          created_at: at,
          updated_at: at
        )
      end

      def create_participant!(round:, speaker_id:, at:)
        round.participants.create!(
          space_membership_id: speaker_id,
          position: 0,
          status: "pending",
          created_at: at,
          updated_at: at
        )
      end
    end
  end
end
