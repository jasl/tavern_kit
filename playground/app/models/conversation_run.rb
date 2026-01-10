# frozen_string_literal: true

# Base class for conversation runs (AI response generation tasks).
#
# Uses Rails STI (Single Table Inheritance) with the `type` column.
# Subclasses define specific behavior for different run types:
# - AutoTurn: AI character responds automatically
# - CopilotTurn: AI responds as a human user (copilot mode)
# - HumanTurn: Tracks human's turn in auto mode (can be skipped)
# - Regenerate: Regenerate an existing message (add swipe)
# - ForceTalk: Force a specific character to speak
#
# ## Status Lifecycle
#
# queued → running → succeeded/failed/canceled
#               ↘ skipped (for HumanTurn only)
#
# ## Concurrency
#
# Database has unique partial indexes ensuring:
# - Only one queued run per conversation
# - Only one running run per conversation
#
class ConversationRun < ApplicationRecord
  STATUSES = %w[queued running succeeded failed canceled skipped].freeze
  # Safety net timeout - only kills runs that have been stuck for a very long time
  # Users get a stuck warning UI after 30 seconds, so this is a last resort
  # for runs that get truly stuck without user interaction (e.g., background processes)
  STALE_TIMEOUT = 10.minutes
  STALE_HEARTBEAT_THRESHOLD = 30.seconds # More aggressive for cleanup job

  belongs_to :conversation
  belongs_to :speaker_space_membership, class_name: "SpaceMembership", optional: true

  has_many :messages, dependent: :nullify

  enum :status, STATUSES.index_by(&:itself)

  validates :status, inclusion: { in: STATUSES }
  validates :reason, presence: true

  scope :queued, -> { where(status: "queued") }
  scope :running, -> { where(status: "running") }
  scope :active, -> { where(status: %w[queued running]) }
  scope :finished, -> { where(status: %w[succeeded failed canceled skipped]) }

  # STI type mapping for human-readable labels
  TYPE_LABELS = {
    "ConversationRun::AutoTurn" => "Auto Turn",
    "ConversationRun::CopilotTurn" => "Copilot Turn",
    "ConversationRun::HumanTurn" => "Human Turn",
    "ConversationRun::Regenerate" => "Regenerate",
    "ConversationRun::ForceTalk" => "Force Talk",
  }.freeze

  # ============================================================================
  # Status Queries
  # ============================================================================

  def ready_to_run?(now = Time.current)
    run_after.nil? || run_after <= now
  end

  def cancel_requested?
    cancel_requested_at.present?
  end

  def active?
    queued? || running?
  end

  def finished?
    succeeded? || failed? || canceled? || skipped?
  end

  # Can this run be canceled by the user?
  #
  # @return [Boolean]
  def can_cancel?
    active?
  end

  # Is this run stale (no heartbeat for too long)?
  #
  # @param now [Time] current time
  # @param timeout [ActiveSupport::Duration] stale threshold
  # @return [Boolean]
  def stale?(now: Time.current, timeout: STALE_TIMEOUT)
    return false unless running?

    last = heartbeat_at || started_at
    return false unless last

    last < now - timeout
  end

  # ============================================================================
  # Status Transitions
  # ============================================================================

  def request_cancel!(at: Time.current)
    update!(cancel_requested_at: at) unless cancel_requested_at
  end

  def queued!(run_after: nil, **attrs)
    update!({ status: "queued", run_after: run_after }.merge(attrs))
  end

  def running!(at: Time.current, **attrs)
    update!({ status: "running", started_at: at, finished_at: nil, heartbeat_at: at }.merge(attrs))
  end

  def succeeded!(at: Time.current, **attrs)
    update!({ status: "succeeded", finished_at: at }.merge(attrs))
  end

  def failed!(at: Time.current, error: nil, **attrs)
    update!({ status: "failed", finished_at: at, error: (error || {}) }.merge(attrs))
  end

  def canceled!(at: Time.current, **attrs)
    update!({ status: "canceled", finished_at: at }.merge(attrs))
  end

  def skipped!(at: Time.current, **attrs)
    update!({ status: "skipped", finished_at: at }.merge(attrs))
  end

  # Update heartbeat timestamp (called periodically during generation).
  #
  # @param at [Time] heartbeat time
  # @return [Boolean] true if updated
  def heartbeat!(at: Time.current)
    return false unless running?

    update_column(:heartbeat_at, at)
    true
  end

  # ============================================================================
  # Type Helpers
  # ============================================================================

  # Get human-readable label for this run's type.
  #
  # @return [String]
  def type_label
    TYPE_LABELS[type] || type&.demodulize&.underscore&.humanize || kind&.humanize || "Unknown"
  end

  # Is this run an AI-generated response?
  #
  # @return [Boolean]
  def ai_response?
    is_a?(ConversationRun::AutoTurn) || is_a?(ConversationRun::CopilotTurn) || is_a?(ConversationRun::ForceTalk)
  end

  # Is this run tracking a human turn?
  #
  # @return [Boolean]
  def human_turn?
    is_a?(ConversationRun::HumanTurn)
  end

  # Should this run be shown in the UI by default?
  #
  # @return [Boolean]
  def visible_in_ui?
    !human_turn? || skipped?
  end

  # ============================================================================
  # Subclass Hooks
  # ============================================================================

  # Override in subclasses to define execution behavior.
  # Base class does nothing - this allows HumanTurn to not execute.
  #
  # @return [Boolean] true if execution should proceed
  def should_execute?
    true
  end
end
