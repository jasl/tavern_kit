# frozen_string_literal: true

# TranslationRun represents an asynchronous translation task.
#
# MVP usage: assistant output translation (Message/MessageSwipe) for Translate both.
# Also used for: user input canonicalization (Translate both internal language).
# Future usage: rewrite fallback, external providers, etc.
#
# ## Status Lifecycle
#
# queued → running → succeeded/failed/canceled
#
class TranslationRun < ApplicationRecord
  STATUSES = %w[queued running succeeded failed canceled].freeze
  KINDS = %w[message_translation user_canonicalization].freeze

  belongs_to :conversation
  belongs_to :message
  belongs_to :message_swipe, optional: true

  enum :status, STATUSES.index_by(&:itself)
  enum :kind, KINDS.index_by(&:itself)

  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS }
  validates :target_lang, presence: true
  validates :internal_lang, presence: true

  validate :swipe_belongs_to_message

  scope :queued, -> { where(status: "queued") }
  scope :running, -> { where(status: "running") }
  scope :active, -> { where(status: %w[queued running]) }
  scope :finished, -> { where(status: %w[succeeded failed canceled]) }

  def active?
    queued? || running?
  end

  def finished?
    succeeded? || failed? || canceled?
  end

  def can_cancel?
    active?
  end

  def request_cancel!(at: Time.current)
    update!(cancel_requested_at: at) unless cancel_requested_at
  end

  def queued!(**attrs)
    update!({ status: "queued" }.merge(attrs))
  end

  def running!(at: Time.current, **attrs)
    update!({ status: "running", started_at: at, finished_at: nil }.merge(attrs))
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

  def target_record
    message_swipe || message
  end

  private

  def swipe_belongs_to_message
    return unless message_swipe
    return if message_swipe.message_id == message_id

    errors.add(:message_swipe_id, "must belong to the same message")
  end
end
