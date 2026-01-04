# frozen_string_literal: true

# Background job for deleting characters and their associated data.
#
# Marks the character as "deleting" to prevent concurrent operations,
# then purges all attachments and destroys the record.
#
# @example Enqueue a deletion
#   CharacterDeleteJob.perform_later(character.id)
#
class CharacterDeleteJob < ApplicationJob
  queue_as :default

  # Discard if character no longer exists (already deleted)
  discard_on ActiveRecord::RecordNotFound

  # Delete the character and all associated data.
  #
  # @param character_id [Integer] the Character ID to delete
  def perform(character_id)
    character = Character.find(character_id)

    # Mark as deleting to prevent concurrent operations
    character.mark_deleting!

    now = Time.current

    # Preserve chat history but mark memberships as removed.
    # Uses status: removed and participation: muted for the new lifecycle model.
    SpaceMembership.where(kind: "character", character_id: character.id).update_all(
      status: "removed",
      participation: "muted",
      removed_at: now,
      removed_reason: "Character deleted",
      copilot_mode: "none",
      unread_at: nil,
      updated_at: now
    )

    # If a user was using this character as a persona (copilot), disable copilot mode.
    SpaceMembership.where(kind: "human", character_id: character.id).update_all(
      copilot_mode: "none",
      copilot_remaining_steps: 0,
      updated_at: now
    )

    asset_blob_ids = character.character_assets.distinct.pluck(:blob_id)

    # Purge portrait attachment (character assets handled after destroy)
    character.portrait.purge if character.portrait.attached?

    # Note: Chat history is preserved - participants will have character_id set to null
    # via dependent: :nullify on the Character model

    # Destroy the character (cascades to character_assets via dependent: :destroy)
    character.destroy!

    purge_unused_asset_blobs(asset_blob_ids)
  end

  private

  # Purge asset blobs only when they are no longer referenced.
  #
  # Character assets deduplicate blobs across characters; purging a blob
  # while still referenced would break other characters' assets.
  #
  # @param blob_ids [Array<Integer>] asset blob IDs to consider for purging
  def purge_unused_asset_blobs(blob_ids)
    Array(blob_ids).uniq.each do |blob_id|
      next if CharacterAsset.exists?(blob_id: blob_id)

      blob = ActiveStorage::Blob.find_by(id: blob_id)
      next unless blob
      next if blob.attachments.exists?

      blob.purge
    end
  end
end
