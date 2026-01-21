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
      # New GitLab-style API: return a structured `ServiceResponse`.
      def self.execute(conversation:, speaker_membership:, message_id: nil)
        new(conversation, speaker_membership, message_id).execute
      end

      def initialize(conversation, speaker_membership, message_id)
        @conversation = conversation
        @space = conversation.space
        @speaker_membership = speaker_membership
        @message_id = message_id
      end

      # @return [ServiceResponse]
      def execute
        unless @speaker_membership
          return ::ServiceResponse.error(
            message: "Missing speaker membership",
            reason: :missing_speaker_membership,
            payload: { advanced: false }
          )
        end

        @conversation.with_lock do
          state = State::RoundState.new(@conversation)

          # A queued "next round" may exist while a previous run is still finishing.
          # If a late message from a previous round arrives after the conversation's
          # active round has advanced, we must ignore it to avoid canceling or
          # corrupting the new round's queued run (queue policy scenario).
          msg = trigger_message
          run = run_for_message(msg)
          if stale_run_message?(msg, run: run, active_round: state.round)
            ConversationEvents::Emitter.emit(
              event_name: "turn_scheduler.advance_turn_ignored",
              conversation: @conversation,
              space: @space,
              conversation_round_id: state.round&.id,
              conversation_run_id: run&.id,
              trigger_message_id: msg&.id,
              speaker_space_membership_id: @speaker_membership&.id,
              reason: "stale_run_message",
              payload: {
                active_round_id: state.round&.id,
                run_round_id: run&.conversation_round_id,
              }
            )
            return ::ServiceResponse.success(reason: :ignored_stale_run_message, payload: { advanced: false })
          end

          increment_turns_count
          decrement_speaker_resources

          # Failed state is a paused scheduler: do not auto-advance the queue.
          # Recovery happens via explicit actions (Retry/Stop/Skip).
          if state.failed?
            ConversationEvents::Emitter.emit(
              event_name: "turn_scheduler.advance_turn_noop",
              conversation: @conversation,
              space: @space,
              conversation_round_id: state.round&.id,
              conversation_run_id: run&.id,
              trigger_message_id: msg&.id,
              speaker_space_membership_id: @speaker_membership&.id,
              reason: "failed",
              payload: { scheduling_state: state.scheduling_state }
            )
            return ::ServiceResponse.success(reason: :noop_failed_state, payload: { advanced: false })
          end

          # Strong isolation: messages created by independent runs (e.g., force_talk/regenerate)
          # MUST NOT advance the active round. Only scheduler-managed runs (with round_id)
          # are allowed to mutate round state.
          if independent_run_message?(msg, run: run, active_round: state.round)
            ConversationEvents::Emitter.emit(
              event_name: "turn_scheduler.advance_turn_ignored",
              conversation: @conversation,
              space: @space,
              conversation_round_id: state.round&.id,
              conversation_run_id: run&.id,
              trigger_message_id: msg&.id,
              speaker_space_membership_id: @speaker_membership&.id,
              reason: "independent_run_message",
              payload: {
                run_present: run.present?,
                run_round_id: run&.conversation_round_id,
              }
            )
            return ::ServiceResponse.success(reason: :ignored_independent_run_message, payload: { advanced: false })
          end

          if state.idle?
            unless should_start_round_from_message?
              return ::ServiceResponse.success(reason: :noop_idle_no_trigger, payload: { advanced: false })
            end

            # Start a fresh activated queue (ST-style).
            # is_user_input means "from a real human user", not "role is user".
            # Auto users send role=user messages but they are AI-generated,
            # so we check that the sender cannot auto-respond (is a pure human).
            is_human_input = trigger_message&.user? && !trigger_message&.space_membership&.can_auto_respond?
            started = StartRound.execute(
              conversation: @conversation,
              trigger_message: trigger_message,
              is_user_input: is_human_input || false
            ).payload[:started]

            return ::ServiceResponse.success(
              reason: started ? :round_started : :round_not_started,
              payload: { advanced: started }
            )
          end

          mark_speaker_as_spoken(state.round)

          # Explicit pause: record the message, but do NOT schedule the next speaker.
          # This preserves round order while preventing auto-advancement until ResumeRound.
          if state.paused?
            advance_position_while_paused(state.round)

            ConversationEvents::Emitter.emit(
              event_name: "turn_scheduler.turn_advanced",
              conversation: @conversation,
              space: @space,
              conversation_round_id: state.round&.id,
              conversation_run_id: run&.id,
              trigger_message_id: msg&.id,
              speaker_space_membership_id: @speaker_membership&.id,
              reason: "paused",
              payload: {
                current_position: state.round&.current_position,
              }
            )

            Broadcasts.queue_updated(@conversation)
            return ::ServiceResponse.success(reason: :advanced_paused, payload: { advanced: true })
          end

          if round_complete?(state.round)
            handle_round_complete(state.round)
          else
            advance_to_next_speaker(state.round)
          end

          Broadcasts.queue_updated(@conversation)
          ::ServiceResponse.success(reason: :advanced, payload: { advanced: true })
        end
      end

      private

      def trigger_message
        return nil unless @message_id

        @trigger_message ||= @conversation.messages.find_by(id: @message_id)
      end

      def run_for_message(msg)
        return nil unless msg&.conversation_run_id

        @run_for_message ||= ConversationRun.find_by(id: msg.conversation_run_id)
      end

      def stale_run_message?(msg, run:, active_round:)
        return false unless msg&.conversation_run_id
        return false unless active_round

        run_round_id = run&.conversation_round_id
        return false if run_round_id.blank?

        run_round_id != active_round.id
      end

      def independent_run_message?(msg, run:, active_round:)
        return false unless msg&.conversation_run_id
        return false unless active_round

        # If the run record is missing (shouldn't happen), fail closed and avoid
        # mutating round state based on an untrusted association.
        return true unless run

        run.conversation_round_id.blank?
      end

      def should_start_round_from_message?
        msg = trigger_message
        return false unless msg

        is_user_input = msg.user?

        # ST-like: manual mode does not auto-trigger on user input.
        return false if is_user_input && @space.reply_order == "manual"

        # When idle, don't start "AI-to-AI" scheduling from assistant messages unless
        # an explicit scheduler is enabled (auto_without_human or Auto).
        return false if msg.assistant? && !auto_scheduling_enabled?

        @conversation.ai_respondable_participants.by_position.any?(&:can_auto_respond?)
      end

      def mark_speaker_as_spoken(active_round)
        mark_participant_as_spoken(active_round)
      end

      def increment_turns_count
        @conversation.increment!(:turns_count)
      end

      def decrement_speaker_resources
        return unless @speaker_membership

        @speaker_membership.decrement_auto_remaining_steps! if @speaker_membership.auto_enabled?
      end

      def round_complete?(active_round)
        return true unless active_round

        position = active_round.current_position.to_i
        position + 1 >= ordered_participants(active_round).size
      end

      def handle_round_complete(active_round)
        @conversation.decrement_auto_without_human_rounds! if @conversation.auto_without_human_enabled?

        finish_round(active_round, ended_reason: "round_complete")

        if auto_scheduling_enabled?
          started = StartRound.execute(conversation: @conversation, is_user_input: false).payload[:started]
          reset_to_idle unless started
        else
          reset_to_idle
        end
      end

      def advance_to_next_speaker(active_round)
        return handle_round_complete(active_round) unless active_round

        participants = ordered_participants(active_round)
        idx = active_round.current_position.to_i + 1

        while idx < participants.length
          participant = participants[idx]
          membership_id = participant.space_membership_id
          candidate = @space.space_memberships.find_by(id: membership_id)
          # Use can_be_scheduled? to filter out muted members that were added
          # to the queue before being muted
          if candidate&.can_be_scheduled?
            active_round.update!(
              scheduling_state: determine_state_for(candidate),
              current_position: idx
            )
            ScheduleSpeaker.execute(conversation: @conversation, speaker: candidate, conversation_round: active_round)
            return
          end

          mark_participant_skipped(participant, reason: "not_schedulable")
          idx += 1
        end

        handle_round_complete(active_round)
      end

      def reset_to_idle
        cancel_queued_runs
      end

      def cancel_queued_runs
        @conversation.conversation_runs.queued.find_each do |run|
          ConversationEvents::Emitter.emit(
            event_name: "conversation_run.canceled",
            conversation: @conversation,
            space: @space,
            conversation_round_id: run.conversation_round_id,
            conversation_run_id: run.id,
            trigger_message_id: run.debug["trigger_message_id"],
            speaker_space_membership_id: run.speaker_space_membership_id,
            reason: "round_complete",
            payload: {
              canceled_by: "round_complete",
              previous_status: run.status,
            }
          )

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
        @conversation.auto_without_human_enabled? || any_auto_active?
      end

      def any_auto_active?
        @space.space_memberships
          .active
          .where(kind: "human", auto: "auto")
          .where("auto_remaining_steps > 0")
          .exists?
      end

      def determine_state_for(speaker)
        return "idle" unless speaker

        "ai_generating"
      end

      def mark_participant_as_spoken(active_round)
        return unless active_round

        participant = active_round.participants.find_by(position: active_round.current_position.to_i)
        return unless participant
        return if participant.spoken?
        return if participant.space_membership_id != @speaker_membership.id

        participant.update!(status: "spoken", spoken_at: Time.current)

        ConversationEvents::Emitter.emit(
          event_name: "turn_scheduler.participant_spoken",
          conversation: @conversation,
          space: @space,
          conversation_round_id: active_round.id,
          trigger_message_id: @message_id,
          speaker_space_membership_id: participant.space_membership_id,
          reason: "message_created",
          payload: {
            position: participant.position,
          }
        )
      end

      def advance_position_while_paused(active_round)
        return unless active_round

        participants = ordered_participants(active_round)
        idx = active_round.current_position.to_i + 1

        while idx < participants.length
          participant = participants[idx]
          unless participant.spoken? || participant.skipped?
            active_round.update!(current_position: idx)
            return
          end

          idx += 1
        end
      end

      def mark_participant_skipped(participant, reason:)
        return unless participant
        return if participant.skipped? || participant.spoken?

        participant.update!(status: "skipped", skipped_at: Time.current, skip_reason: reason.to_s)

        ConversationEvents::Emitter.emit(
          event_name: "turn_scheduler.participant_skipped",
          conversation: @conversation,
          space: @space,
          conversation_round_id: participant.conversation_round_id,
          speaker_space_membership_id: participant.space_membership_id,
          reason: reason.to_s,
          payload: {
            position: participant.position,
          }
        )
      end

      def finish_round(active_round, ended_reason:)
        return unless active_round

        previous_scheduling_state = active_round.scheduling_state

        active_round.update!(
          status: "finished",
          scheduling_state: nil,
          ended_reason: ended_reason,
          finished_at: Time.current
        )

        ConversationEvents::Emitter.emit(
          event_name: "turn_scheduler.round_finished",
          conversation: @conversation,
          space: @space,
          conversation_round_id: active_round.id,
          trigger_message_id: @message_id,
          reason: ended_reason,
          payload: {
            previous_scheduling_state: previous_scheduling_state,
          }
        )
      end

      def ordered_participants(active_round)
        return [] unless active_round

        @ordered_participants ||= active_round.participants.order(:position).to_a
      end
    end
  end
end
