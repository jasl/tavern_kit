# frozen_string_literal: true

# Presenter for group chat queue display.
#
# Encapsulates the business logic needed to display the group queue UI,
# keeping ERB templates clean and focused on presentation only.
#
# Usage:
#   presenter = GroupQueuePresenter.new(conversation: @conversation, space: @space)
#   presenter.queue_members  # => Array of SpaceMembership
#   presenter.current_speaker # => SpaceMembership or nil
#   presenter.idle?           # => true if scheduling is idle
#
class GroupQueuePresenter
  attr_reader :conversation, :space

  MAX_VISIBLE_QUEUE_MEMBERS = 3
  DEFAULT_QUEUE_LIMIT = 10

  def initialize(conversation:, space:, limit: DEFAULT_QUEUE_LIMIT)
    @conversation = conversation
    @space = space
    @limit = limit
  end

  # Returns the upcoming speakers from the turn scheduler.
  # @return [Array<SpaceMembership>]
  def queue_members
    @queue_members ||= TurnScheduler::Queries::QueuePreview.call(
      conversation: @conversation,
      limit: @limit
    )
  end

  # Returns the currently active run (queued or running).
  # Uses by_status_priority scope to prioritize running over queued.
  # @return [ConversationRun, nil]
  def active_run
    @active_run ||= @conversation.conversation_runs
      .active
      .by_status_priority
      .includes(:speaker_space_membership)
      .first
  end

  # Returns the current speaker membership.
  # @return [SpaceMembership, nil]
  def current_speaker
    @current_speaker ||= active_run&.speaker_space_membership || @conversation.current_speaker
  end

  # Returns the scheduling state string.
  # @return [String]
  def scheduling_state
    @conversation.scheduling_state
  end

  # @return [Boolean] true if scheduling is idle
  def idle?
    scheduling_state == "idle"
  end

  # @return [Boolean] true if AI is generating
  def ai_generating?
    scheduling_state == "ai_generating"
  end

  # @return [Boolean] true if waiting for human
  def human_waiting?
    scheduling_state == "human_waiting"
  end

  # @return [Boolean] true if in a failed state
  def failed?
    scheduling_state == "failed"
  end

  # @return [Boolean] true if there's a human turn in progress
  def human_turn?
    active_run&.human_turn?
  end

  # @return [Boolean] true if auto mode is enabled
  def auto_mode_enabled?
    @conversation.auto_mode_enabled?
  end

  # @return [Integer] remaining auto mode rounds
  def auto_mode_remaining_rounds
    @conversation.auto_mode_remaining_rounds
  end

  # Members visible in the queue display (limited for UI).
  # @return [Array<SpaceMembership>]
  def visible_queue_members
    queue_members.first(MAX_VISIBLE_QUEUE_MEMBERS)
  end

  # Count of additional members not shown.
  # @return [Integer]
  def remaining_queue_count
    [queue_members.size - MAX_VISIBLE_QUEUE_MEMBERS, 0].max
  end

  # @return [Boolean] true if there are members in queue
  def has_queue?
    queue_members.any?
  end

  # Monotonic revision for client-side out-of-order update protection.
  # @return [Integer]
  def render_seq
    @conversation.group_queue_revision.to_i
  end

  # DOM ID for the group queue element.
  # @return [String]
  def dom_id
    ActionView::RecordIdentifier.dom_id(@conversation, :group_queue)
  end
end
