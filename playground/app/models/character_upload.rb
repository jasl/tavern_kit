# frozen_string_literal: true

# CharacterUpload tracks async character import status.
#
# Used to provide progress feedback to users during character import,
# which may take time for large CharX files with many assets.
#
# @example Create and process an upload
#   upload = CharacterUpload.create!(user: current_user, filename: file.original_filename)
#   CharacterImportJob.perform_later(upload.id)
#
class CharacterUpload < ApplicationRecord
  # Upload status values
  STATUSES = %w[pending processing completed failed].freeze

  # Associations
  belongs_to :user
  belongs_to :character, optional: true

  # File attachment for the uploaded file
  has_one_attached :file

  # Validations
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :processing, -> { where(status: "processing") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :recent, -> { order(created_at: :desc) }

  # Mark as processing.
  #
  # @return [Boolean]
  def mark_processing!
    update!(status: "processing")
  end

  # Mark as completed with the imported character.
  #
  # @param character [Character] the imported character
  # @return [Boolean]
  def mark_completed!(character)
    update!(status: "completed", character: character)
  end

  # Mark as failed with an error message.
  #
  # @param message [String] error description
  # @return [Boolean]
  def mark_failed!(message)
    update!(status: "failed", error_message: message)
  end

  # Check if upload is pending.
  #
  # @return [Boolean]
  def pending?
    status == "pending"
  end

  # Check if upload is processing.
  #
  # @return [Boolean]
  def processing?
    status == "processing"
  end

  # Check if upload is completed.
  #
  # @return [Boolean]
  def completed?
    status == "completed"
  end

  # Check if upload failed.
  #
  # @return [Boolean]
  def failed?
    status == "failed"
  end
end
