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
  # NOTE: This method does NOT increment references_count for existing records.
  # Use find_or_create_with_reference! when establishing a new reference to content.
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

  # Find or create content AND increment the reference count.
  #
  # Use this method when establishing a new reference to content (e.g., creating
  # a new Message or MessageSwipe). This ensures references_count is correct:
  # - If existing content is found, references_count is incremented
  # - If new content is created, references_count starts at 1 (correct for one reference)
  #
  # @param content [String] the content to store
  # @return [TextContent] the found or created record with reference counted
  def self.find_or_create_with_reference!(content)
    return nil if content.nil?

    sha256 = Digest::SHA256.hexdigest(content.to_s)

    # Try to find existing first
    existing = find_by(content_sha256: sha256)
    if existing
      existing.increment_references!
      return existing
    end

    # Create new record (starts with references_count = 1)
    create!(content: content, content_sha256: sha256)
  rescue ActiveRecord::RecordNotUnique
    # Concurrent creation - find and increment
    found = find_by!(content_sha256: sha256)
    found.increment_references!
    found
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
  # Uses tally to correctly handle duplicate IDs - if the same text_content_id
  # appears multiple times (e.g., multiple messages sharing content), each
  # occurrence increments the count.
  #
  # @param ids [Array<Integer>] TextContent IDs to increment (may contain duplicates)
  # @return [void]
  def self.batch_increment_references!(ids)
    return if ids.blank?

    id_counts = ids.compact.tally
    id_counts.each do |tc_id, count|
      where(id: tc_id).update_all(["references_count = references_count + ?", count])
    end
  end

  # Batch decrement reference counts for multiple IDs.
  #
  # Uses tally to correctly handle duplicate IDs - if the same text_content_id
  # appears multiple times, each occurrence decrements the count.
  #
  # @param ids [Array<Integer>] TextContent IDs to decrement (may contain duplicates)
  # @return [void]
  def self.batch_decrement_references!(ids)
    return if ids.blank?

    id_counts = ids.compact.tally
    id_counts.each do |tc_id, count|
      where(id: tc_id).update_all(["references_count = references_count - ?", count])
    end
  end

  # Clean up orphaned TextContent records (references_count <= 0).
  #
  # These records are no longer referenced by any Message or MessageSwipe.
  # This can happen after:
  # - Messages/Swipes are deleted
  # - Conversations are destroyed
  # - Bugs causing double-decrement (references_count < 0)
  #
  # @param batch_size [Integer] number of records to delete per batch (default 1000)
  # @return [Integer] total number of records deleted
  #
  # @example Manual cleanup
  #   TextContent.cleanup_orphans!
  #
  # @example With custom batch size
  #   TextContent.cleanup_orphans!(batch_size: 500)
  #
  def self.cleanup_orphans!(batch_size: 1000)
    total_deleted = 0

    loop do
      # Delete in batches to avoid long-running transactions
      deleted_count = where("references_count <= 0").limit(batch_size).delete_all
      total_deleted += deleted_count

      break if deleted_count < batch_size
    end

    total_deleted
  end

  # Count orphaned TextContent records.
  #
  # @return [Integer] number of orphaned records
  def self.orphan_count
    where("references_count <= 0").count
  end

  private

  # Compute SHA256 hash of content before validation.
  #
  # @return [void]
  def compute_sha256
    self.content_sha256 ||= Digest::SHA256.hexdigest(content.to_s) if content.present?
  end
end
