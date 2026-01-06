# frozen_string_literal: true

# Join model linking Characters to Lorebooks.
#
# Allows attaching standalone lorebooks to characters for use in prompt generation.
# This mirrors SillyTavern's "Link to World Info" (primary) and
# "Extra World Info" (additional) functionality.
#
# A character can have:
# - One primary lorebook (exported with the character)
# - Multiple additional lorebooks (not exported, local only)
#
# @example Link a primary lorebook
#   character.character_lorebooks.create!(lorebook: lorebook, source: "primary")
#
# @example Link additional lorebooks
#   character.character_lorebooks.create!(lorebook: book1, source: "additional")
#   character.character_lorebooks.create!(lorebook: book2, source: "additional", priority: 1)
#
class CharacterLorebook < ApplicationRecord
  # Source types matching SillyTavern behavior
  SOURCES = %w[primary additional].freeze

  # Associations
  belongs_to :character
  belongs_to :lorebook

  # Validations
  validates :lorebook_id, uniqueness: { scope: :character_id, message: "is already linked to this character" }
  validates :source, inclusion: { in: SOURCES }
  validates :priority, numericality: { only_integer: true }
  validate :only_one_primary_per_character, if: -> { source == "primary" }

  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :primary, -> { where(source: "primary") }
  scope :additional, -> { where(source: "additional") }
  scope :by_priority, -> { order(:priority) }

  # Callbacks
  before_create :set_priority

  private

  # Ensure only one primary lorebook per character.
  # The database has a partial unique index for this, but we validate in Ruby
  # for better error messages.
  def only_one_primary_per_character
    existing = CharacterLorebook.where(character_id: character_id, source: "primary")
    existing = existing.where.not(id: id) if persisted?

    if existing.exists?
      errors.add(:source, "can only have one primary lorebook per character")
    end
  end

  # Auto-set priority for new records within the same source type.
  def set_priority
    return if priority != 0

    max_priority = character&.character_lorebooks&.where(source: source)&.maximum(:priority) || -1
    self.priority = max_priority + 1
  end
end
