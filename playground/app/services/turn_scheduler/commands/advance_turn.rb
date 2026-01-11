# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Advances to the next turn after a message is created.
    #
    # Called by Message `after_create_commit`. This is the primary driver
    # of the scheduler - each message creation advances the queue.
    #
    # If no active round exists but the conversation allows auto-responses,
    # this will start a new round and schedule the next speaker.
    #
    class AdvanceTurn
      def self.call(conversation:, speaker_membership:, message_id: nil)
        new(conversation, speaker_membership, message_id).call
      end

      def initialize(conversation, speaker_membership, message_id)
        @conversation = conversation
        @space = conversation.space
        @speaker_membership = speaker_membership
        @message_id = message_id
      end

      # @return [Boolean] true if turn was advanced
      def call
        return false unless @speaker_membership

        @conversation.with_lock do
          # A queued "next round" may exist while a previous run is still finishing.
          # If a late message from a previous round arrives after the conversation's
          # current_round_id has advanced, we must ignore it to avoid canceling or
          # corrupting the new round's queued run (queue policy scenario).
          msg = trigger_message
          return false if stale_run_message?(msg)

          state = State::RoundState.new(@conversation)

          increment_turns_count
          decrement_speaker_resources

          if state.idle?
            return false unless should_start_round_from_message?

            # Start a fresh activated queue (ST-style).
            # is_user_input means "from a real human user", not "role is user".
            # Copilot users send role=user messages but they are AI-generated,
            # so we check that the sender cannot auto-respond (is a pure human).
            is_human_input = trigger_message&.user? && !trigger_message&.space_membership&.can_auto_respond?
            started = StartRound.call(
              conversation: @conversation,
              trigger_message: trigger_message,
              is_user_input: is_human_input || false
            )

            return started
          end

          mark_speaker_as_spoken

          if round_complete?
            handle_round_complete
          else
            advance_to_next_speaker
          end

          Broadcasts.queue_updated(@conversation)
          true
        end
      end

      private

      def trigger_message
        return nil unless @message_id

        @trigger_message ||= @conversation.messages.find_by(id: @message_id)
      end

      def stale_run_message?(msg)
        return false unless msg&.conversation_run_id

        current_round_id = @conversation.current_round_id
        return false if current_round_id.blank?

        run = ConversationRun.find_by(id: msg.conversation_run_id)
        run_round_id = run&.debug&.dig("round_id")
        return false if run_round_id.blank?

        run_round_id != current_round_id
      end

      def should_start_round_from_message?
        msg = trigger_message
        return false unless msg

        is_user_input = msg.user?

        # ST-like: manual mode does not auto-trigger on user input.
        return false if is_user_input && @space.reply_order == "manual"

        # When idle, don't start "AI-to-AI" scheduling from assistant messages unless
        # an explicit auto scheduler is enabled (auto-mode or copilot loop).
        return false if msg.assistant? && !auto_scheduling_enabled?

        @conversation.ai_respondable_participants.by_position.any?(&:can_auto_respond?)
      end

      def mark_speaker_as_spoken
        spoken_ids = @conversation.round_spoken_ids || []
        return if spoken_ids.include?(@speaker_membership.id)

        @conversation.update_column(:round_spoken_ids, spoken_ids + [@speaker_membership.id])
      end

      def increment_turns_count
        @conversation.increment!(:turns_count)
      end

      def decrement_speaker_resources
        return unless @speaker_membership

        @speaker_membership.decrement_copilot_remaining_steps! if @speaker_membership.copilot_full?
      end

      def round_complete?
        ids = @conversation.round_queue_ids || []
        position = @conversation.round_position.to_i
        position + 1 >= ids.size
      end

      def handle_round_complete
        @conversation.decrement_auto_mode_rounds! if @conversation.auto_mode_enabled?

        if auto_scheduling_enabled?
          StartRound.call(conversation: @conversation, is_user_input: false)
        else
          reset_to_idle
        end
      end

      def advance_to_next_speaker
        ids = @conversation.round_queue_ids || []
        idx = @conversation.round_position.to_i + 1

        while idx < ids.length
          candidate = @space.space_memberships.find_by(id: ids[idx])
          # Use can_be_scheduled? to filter out muted members that were added
          # to the queue before being muted
          if candidate&.can_be_scheduled?
            @conversation.update!(
              scheduling_state: determine_state_for(candidate),
              current_speaker_id: candidate.id,
              round_position: idx
            )
            ScheduleSpeaker.call(conversation: @conversation, speaker: candidate)
            return
          end

          idx += 1
        end

        handle_round_complete
      end

      def reset_to_idle
        @conversation.update!(
          scheduling_state: "idle",
          current_round_id: nil,
          current_speaker_id: nil,
          round_position: 0,
          round_spoken_ids: [],
          round_queue_ids: []
        )

        cancel_queued_runs
      end

      def cancel_queued_runs
        @conversation.conversation_runs.queued.find_each do |run|
          run.update!(
            status: "canceled",
            finished_at: Time.current,
            debug: run.debug.merge(
              "canceled_by" => "round_complete",
              "canceled_at" => Time.current.iso8601
            )
          )
        end
      end

      def auto_scheduling_enabled?
        @conversation.auto_mode_enabled? || any_copilot_active?
      end

      def any_copilot_active?
        @space.space_memberships.active.any? { |m| m.copilot_full? && m.can_auto_respond? }
      end

      def determine_state_for(speaker)
        return "idle" unless speaker

        if speaker.can_auto_respond?
          "ai_generating"
        elsif @conversation.auto_mode_enabled?
          "human_waiting"
        else
          "waiting_for_speaker"
        end
      end
    end
  end
end
