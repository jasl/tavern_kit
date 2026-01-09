# frozen_string_literal: true

# TextContent stores message/swipe content for Copy-on-Write sharing.
#
# This model enables efficient conversation forking by allowing multiple
# Message and MessageSwipe records to share the same content. When content
# is edited, COW logic in the parent models creates a new TextContent only
# if the original is shared (references_count > 1).
#
# @example Find or create content
#   text_content = TextContent.find_or_create_for("Hello world")
#
# @example Check if content is shared
#   text_content.shared? # => true if references_count > 1
#
class TextContent < ApplicationRecord
  # Associations - restrict deletion if still referenced
  has_many :messages, dependent: :restrict_with_error
  has_many :message_swipes, dependent: :restrict_with_error

  # Validations
  validates :content, presence: true
  validates :content_sha256, presence: true, uniqueness: true

  # Callbacks
  before_validation :compute_sha256, on: :create

  # Find or create content by SHA256 hash (for deduplication).
  #
  # Uses upsert-style logic to handle concurrent creation:
  # first tries to find by SHA256, then creates if not found.
  #
  # @param content [String] the content to store
  # @return [TextContent] the found or created record
  def self.find_or_create_for(content)
    return nil if content.nil?

    sha256 = Digest::SHA256.hexdigest(content.to_s)

    # Try to find existing first (most common case for COW)
    existing = find_by(content_sha256: sha256)
    return existing if existing

    # Create new record
    create!(content: content, content_sha256: sha256)
  rescue ActiveRecord::RecordNotUnique
    # Concurrent creation - find the existing record
    find_by!(content_sha256: sha256)
  end

  # Find existing content by SHA256 (without creating).
  #
  # @param content [String] the content to look up
  # @return [TextContent, nil] the found record or nil
  def self.find_for(content)
    return nil if content.nil?

    sha256 = Digest::SHA256.hexdigest(content.to_s)
    find_by(content_sha256: sha256)
  end

  # Check if this content is shared by multiple records.
  #
  # @return [Boolean] true if references_count > 1
  def shared?
    references_count > 1
  end

  # Atomically increment the reference count.
  #
  # @param amount [Integer] amount to increment (default 1)
  # @return [void]
  def increment_references!(amount = 1)
    self.class.where(id: id).update_all(["references_count = references_count + ?", amount])
    reload
  end

  # Atomically decrement the reference count.
  #
  # @param amount [Integer] amount to decrement (default 1)
  # @return [void]
  def decrement_references!(amount = 1)
    self.class.where(id: id).update_all(["references_count = references_count - ?", amount])
    reload
  end

  # Batch increment reference counts for multiple IDs.
  #
  # @param ids [Array<Integer>] TextContent IDs to increment
  # @param amount [Integer] amount to increment per ID
  # @return [void]
  def self.batch_increment_references!(ids, amount = 1)
    return if ids.blank?

    where(id: ids.uniq.compact).update_all(["references_count = references_count + ?", amount])
  end

  # Batch decrement reference counts for multiple IDs.
  #
  # @param ids [Array<Integer>] TextContent IDs to decrement
  # @param amount [Integer] amount to decrement per ID
  # @return [void]
  def self.batch_decrement_references!(ids, amount = 1)
    return if ids.blank?

    where(id: ids.uniq.compact).update_all(["references_count = references_count - ?", amount])
  end

  private

  # Compute SHA256 hash of content before validation.
  #
  # @return [void]
  def compute_sha256
    self.content_sha256 ||= Digest::SHA256.hexdigest(content.to_s) if content.present?
  end
end
