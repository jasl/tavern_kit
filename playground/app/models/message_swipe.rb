# frozen_string_literal: true

# MessageSwipe represents a version of an AI response (swipe).
#
# A Message can have multiple swipes, allowing users to navigate between
# different AI-generated versions without changing the message's position
# in the conversation timeline.
#
# Content Storage (COW - Copy-on-Write):
# Content is stored in the `text_contents` table and shared across forked swipes.
# When editing a swipe whose content is shared (references_count > 1), a new
# TextContent record is created automatically. The `content` column is kept as
# a fallback for legacy data.
#
# @example Create a swipe for a message
#   message.message_swipes.create!(position: 0, content: "First version")
#
# @example Navigate swipes
#   message.select_swipe!(direction: :right)
#
class MessageSwipe < ApplicationRecord
  belongs_to :message, counter_cache: true
  belongs_to :conversation_run, optional: true

  # COW content storage - shared across forked swipes
  belongs_to :text_content, optional: true

  validates :position, presence: true,
                       numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :position, uniqueness: { scope: :message_id }

  # Callbacks for COW content management
  before_save :ensure_text_content_for_new_content
  after_destroy :decrement_text_content_references

  scope :ordered, -> { order(:position) }

  # --- Content helpers (COW-aware) ---

  # Get swipe content (COW-aware).
  #
  # Uses ActiveModel::Dirty to maintain standard attribute semantics:
  # - If content was changed (dirty), returns the new value from the column
  # - Otherwise reads from text_content (COW storage) or legacy column
  #
  # @return [String, nil]
  def content
    if content_changed?
      read_attribute(:content)
    else
      text_content&.content || read_attribute(:content)
    end
  end

  # Set swipe content (COW-aware).
  #
  # Writes directly to the content column to leverage ActiveModel::Dirty tracking.
  # The before_save callback handles COW logic using content_changed?.
  #
  # @param value [String, nil] the new content
  def content=(value)
    write_attribute(:content, value&.strip)
  end

  # Check if this swipe is the active one for its message.
  #
  # @return [Boolean]
  def active?
    message.active_message_swipe_id == id
  end

  # Check if this is the first swipe (leftmost).
  #
  # @return [Boolean]
  def first?
    position.zero?
  end

  # Check if this is the last swipe (rightmost).
  #
  # @return [Boolean]
  def last?
    position == message.message_swipes.maximum(:position)
  end

  private

  # Ensure text_content is created/updated before save (COW logic).
  #
  # Uses ActiveModel::Dirty to detect content changes:
  # - content_changed? indicates content= was called
  def ensure_text_content_for_new_content
    return unless content_changed?

    new_content = read_attribute(:content)

    # Handle nil/empty content
    if new_content.blank?
      if text_content_id.present?
        old_text_content = text_content
        self.text_content = nil
        old_text_content&.decrement_references! if old_text_content&.references_count&.positive?
      end
      return
    end

    # Check if content actually changed compared to text_content
    return if text_content&.content == new_content

    if text_content.present? && text_content.shared?
      # COW: content is shared, create new TextContent (and increment if existing)
      old_text_content = text_content
      self.text_content = TextContent.find_or_create_with_reference!(new_content)
      old_text_content.decrement_references!
    elsif text_content.present?
      # Not shared - check if new content already exists in another TextContent
      new_sha256 = Digest::SHA256.hexdigest(new_content)
      existing = TextContent.find_by(content_sha256: new_sha256)

      if existing && existing.id != text_content.id
        # Switch to existing TextContent and clean up old one
        old_text_content = text_content
        self.text_content = existing
        existing.increment_references!
        old_text_content.decrement_references!
      elsif text_content.update_if_not_shared!(new_content, new_sha256)
        # Atomic update succeeded - content was updated in place
        # No further action needed
      else
        # Atomic update failed - another process incremented references_count
        # (e.g., a concurrent fork operation). Fall back to COW.
        old_text_content = text_content
        self.text_content = TextContent.find_or_create_with_reference!(new_content)
        old_text_content.decrement_references!
      end
    else
      # New swipe or no text_content yet - use find_or_create_with_reference!
      # to correctly increment references_count if content already exists
      self.text_content = TextContent.find_or_create_with_reference!(new_content)
    end
  end

  # Decrement text_content references when swipe is destroyed.
  def decrement_text_content_references
    return unless text_content_id.present?

    TextContent.where(id: text_content_id).update_all("references_count = references_count - 1")
  end
end
