# frozen_string_literal: true

# Service for soft-deleting (hiding) messages from a conversation.
#
# Hiding a message sets `messages.visibility = "hidden"` and ensures scheduler safety:
# - Hidden messages are not shown in UI
# - Hidden messages are excluded from prompt building
# - Hidden messages do not participate in TurnScheduler epoch/last-speaker semantics
#
# Rollback semantics (scheduler reliability):
# - If there is an active run (queued/running) or an active round, we treat the operation
#   as a potential rollback boundary and apply safety actions.
# - If a run is running, we request cancel (Stop generating, discard output).
# - If the hidden message is the current scheduler-visible tail OR it is the active round's trigger_message,
#   we cancel the active round and cancel any downstream queued run that is tied to the old state.
#
class Messages::Hider
  Result = Data.define(:success?, :error, :error_code, :effects)

  def initialize(message:, conversation:, on_hidden: nil)
    @message = message
    @conversation = conversation
    @on_hidden = on_hidden
  end

  # @return [Result]
  def call
    return fork_point_protected_result if message.fork_point?
    return success_result if message.visibility_hidden?

    effects = {
      rollback: false,
      requested_cancel_running: false,
      canceled_queued_runs: 0,
      canceled_round: false,
    }

    conversation.with_lock do
      active_round = conversation.conversation_rounds.find_by(status: "active")
      # Lock active runs inside the conversation lock to prevent a queued run from
      # being claimed concurrently (queued → running) while we are deciding whether
      # to cancel/stop generation.
      active_runs = ConversationRun.active.where(conversation_id: conversation.id).lock.to_a

      if active_runs.empty? && active_round.nil?
        # Non-rollback: no scheduling state to clean up.
        hide_message!
        next
      end

      # Rollback safety actions
      effects[:rollback] = true

      canceled_running = request_cancel_running_runs!(active_runs)
      effects[:requested_cancel_running] = canceled_running.positive?

      if cancel_round_and_queue_needed?(active_round: active_round)
        effects[:canceled_queued_runs] = cancel_downstream_queued_runs!(active_runs)
        effects[:canceled_round] = cancel_active_round!(active_round, ended_reason: "message_hidden")
      end

      hide_message!
    end

    on_hidden&.call(message, conversation)

    success_result(effects: effects)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(
      success?: false,
      error: e.record&.errors&.full_messages&.to_sentence.presence || e.message,
      error_code: :validation_failed,
      effects: {}
    )
  end

  private

  attr_reader :message, :conversation, :on_hidden

  def hide_message!
    message.update!(visibility: "hidden")
  end

  def request_cancel_running_runs!(active_runs)
    canceled = 0

    active_runs.each do |run|
      next unless run.running?
      run.request_cancel!
      canceled += 1
    end

    canceled
  end

  def cancel_round_and_queue_needed?(active_round:)
    # Evaluate tail BEFORE we hide the message.
    tail_id =
      Message
        .where(conversation_id: conversation.id)
        .scheduler_visible
        .order(seq: :desc, id: :desc)
        .limit(1)
        .pick(:id)

    return true if tail_id.to_i == message.id

    active_round&.trigger_message_id.to_i == message.id
  end

  def cancel_downstream_queued_runs!(active_runs)
    now = Time.current
    canceled = 0

    active_runs.each do |run|
      next unless run.queued?

      debug = run.debug || {}

      cancel =
        debug["scheduled_by"] == "turn_scheduler" ||
          (debug["trigger"] == "user_message" && debug["user_message_id"].to_i == message.id)

      next unless cancel

      run.update!(
        status: "canceled",
        finished_at: now,
        debug: debug.merge(
          "canceled_by" => "message_hidden",
          "canceled_at" => now.iso8601
        )
      )

      canceled += 1
    end

    canceled
  end

  def cancel_active_round!(active_round, ended_reason:)
    return unless active_round

    now = Time.current
    active_round.update!(
      status: "canceled",
      scheduling_state: nil,
      ended_reason: ended_reason.to_s,
      finished_at: now,
      updated_at: now
    )

    true
  end

  def success_result(effects: {})
    Result.new(success?: true, error: nil, error_code: nil, effects: effects || {})
  end

  def fork_point_protected_result
    Result.new(
      success?: false,
      error: "This message is a fork point for other conversations and cannot be deleted.",
      error_code: :fork_point_protected,
      effects: {}
    )
  end
end
