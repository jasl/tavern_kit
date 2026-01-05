# frozen_string_literal: true

# Join model linking Spaces to Lorebooks.
#
# Allows attaching standalone lorebooks to spaces for use in prompt generation.
# Multiple lorebooks can be attached with different priorities.
#
class SpaceLorebook < ApplicationRecord
  # Source types
  SOURCES = %w[global character_primary character_additional].freeze

  # Associations
  belongs_to :space
  belongs_to :lorebook

  # Validations
  validates :lorebook_id, uniqueness: { scope: :space_id, message: "is already attached to this space" }
  validates :source, inclusion: { in: SOURCES }
  validates :priority, numericality: { only_integer: true }

  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :by_priority, -> { order(:priority) }
  scope :global, -> { where(source: "global") }

  # Callbacks
  before_create :set_priority

  private

  def set_priority
    max_priority = space.space_lorebooks.maximum(:priority) || -1
    self.priority = max_priority + 1
  end
end
