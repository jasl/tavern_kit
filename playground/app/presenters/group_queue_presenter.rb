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

  def snapshot
    @snapshot ||= TurnScheduler::Queries::DebugSnapshot.execute(conversation: @conversation, limit: @limit)
  end

  # Returns the upcoming speakers from the turn scheduler.
  # @return [Array<SpaceMembership>]
  def queue_members
    snapshot.queue_members
  end

  # Returns the currently active run (queued or running).
  # Uses by_status_priority scope to prioritize running over queued.
  # @return [ConversationRun, nil]
  def active_run
    snapshot.active_run
  end

  # Returns the current speaker membership.
  #
  # Prioritizes turn_state.current_speaker because during the transition window
  # (message created but run not yet finalized), the active_run might be stale
  # (from the previous speaker) while the round has already advanced to the next speaker.
  #
  # @return [SpaceMembership, nil]
  def current_speaker
    snapshot.current_speaker
  end

  # Returns the scheduling state string.
  # @return [String]
  def scheduling_state
    snapshot.scheduling_state
  end

  # @return [Boolean] true if scheduling is idle
  def idle?
    snapshot.idle?
  end

  # @return [Boolean] true if AI is generating
  def ai_generating?
    snapshot.ai_generating?
  end

  # @return [Boolean] true if in a failed state
  def failed?
    snapshot.failed?
  end

  # @return [Boolean] true if in a paused state
  def paused?
    snapshot.paused?
  end

  # @return [Boolean] true if auto-without-human is enabled
  def auto_without_human_enabled?
    @conversation.auto_without_human_enabled?
  end

  # @return [Integer] remaining auto-without-human rounds
  def auto_without_human_remaining_rounds
    @conversation.auto_without_human_remaining_rounds
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

  # @return [Boolean] true if any automation is active (auto-without-human or auto)
  def automation_active?
    snapshot.automation_active?
  end

  # @return [Boolean] true if pause/resume controls should be shown
  def show_pause_controls?
    automation_active? && (ai_generating? || paused?)
  end

  # @return [Boolean] true if resume is blocked by a running generation
  def resume_blocked?
    snapshot.resume_blocked?
  end

  def turn_state
    snapshot.turn_state
  end
end
