# frozen_string_literal: true

# Join model linking Conversations to Lorebooks.
#
# Mirrors SillyTavern's "Chat Lore" (chat-bound World Info) concept.
#
# Notes:
# - A conversation can attach multiple lorebooks (ordered by priority).
# - Ordering and insertion semantics are handled by PromptBuilder + TavernKit.
#
class ConversationLorebook < ApplicationRecord
  # Associations
  belongs_to :conversation
  belongs_to :lorebook

  # Validations
  validates :lorebook_id, uniqueness: { scope: :conversation_id, message: "is already attached to this conversation" }
  validates :priority, numericality: { only_integer: true }

  # Scopes
  scope :enabled, -> { where(enabled: true) }
  scope :by_priority, -> { order(:priority) }

  # Callbacks
  before_create :set_priority

  private

  def set_priority
    return if priority != 0

    max_priority = conversation.conversation_lorebooks.maximum(:priority) || -1
    self.priority = max_priority + 1
  end
end
