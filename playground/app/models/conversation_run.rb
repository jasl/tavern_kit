# frozen_string_literal: true

class ConversationRun < ApplicationRecord
  KINDS = %w[user_turn auto_mode regenerate force_talk].freeze
  STATUSES = %w[queued running succeeded failed canceled skipped].freeze
  STALE_TIMEOUT = 2.minutes

  belongs_to :conversation
  belongs_to :speaker_space_membership, class_name: "SpaceMembership", optional: true

  has_many :messages, dependent: :nullify

  enum :status, STATUSES.index_by(&:itself)
  enum :kind, KINDS.index_by(&:itself)

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :reason, presence: true

  scope :queued, -> { where(status: "queued") }
  scope :running, -> { where(status: "running") }

  def ready_to_run?(now = Time.current)
    run_after.nil? || run_after <= now
  end

  def cancel_requested?
    cancel_requested_at.present?
  end

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

  def stale?(now: Time.current, timeout: STALE_TIMEOUT)
    return false unless running?

    last = heartbeat_at || started_at
    return false unless last

    last < now - timeout
  end
end
