# frozen_string_literal: true

# LorebookUpload tracks async lorebook import status.
#
# Used to provide progress feedback to users during lorebook import,
# which may take time for large World Info JSON files.
#
# @example Create and process an upload
#   upload = LorebookUpload.create!(user: current_user, filename: "lore.json")
#   LorebookImportJob.perform_later(upload.id)
#
class LorebookUpload < ApplicationRecord
  STATUSES = %w[pending processing completed failed].freeze

  belongs_to :user
  belongs_to :lorebook, optional: true

  has_one_attached :file

  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :recent, -> { order(created_at: :desc) }

  def mark_processing!
    update!(status: "processing")
  end

  def mark_completed!(lorebook)
    update!(status: "completed", lorebook: lorebook)
  end

  def mark_failed!(message)
    update!(status: "failed", error_message: message)
  end

  def pending?
    status == "pending"
  end

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end
end
