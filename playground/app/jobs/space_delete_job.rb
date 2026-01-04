# frozen_string_literal: true

# Background job for deleting spaces and their associated data.
#
# Marks the space as "deleting" to prevent concurrent operations,
# then deletes runs + messages in batches to avoid long locks/timeouts.
#
# @example Enqueue a deletion
#   SpaceDeleteJob.perform_later(space.id)
#
class SpaceDeleteJob < ApplicationJob
  queue_as :default

  # Discard if space no longer exists (already deleted)
  discard_on ActiveRecord::RecordNotFound

  # Delete the space and all associated data.
  #
  # @param space_id [Integer] the Space ID to delete
  # @param batch_size [Integer] messages per delete batch
  # @param max_batches [Integer] max batches per job run (re-enqueues if more remain)
  def perform(space_id, batch_size: 1000, max_batches: 20)
    space = Space.find(space_id)

    # Mark as deleting to prevent concurrent operations
    space.mark_deleting! unless space.deleting?

    conversation_ids = Conversation.where(space_id: space_id).pluck(:id)

    # Delete runs first and rely on FK nullification for messages.conversation_run_id.
    ConversationRun.where(conversation_id: conversation_ids).delete_all if conversation_ids.any?

    delete_messages_in_batches(conversation_ids, batch_size: batch_size, max_batches: max_batches)

    # If messages still remain, re-enqueue to continue deletion later.
    if conversation_ids.any? && Message.exists?(conversation_id: conversation_ids)
      SpaceDeleteJob.perform_later(space_id, batch_size: batch_size, max_batches: max_batches)
      return
    end

    # SpaceMemberships reference space and messages reference space_memberships; delete after messages.
    SpaceMembership.where(space_id: space_id).delete_all

    Conversation.where(space_id: space_id).delete_all

    # Finally, delete the space record itself.
    Space.where(id: space_id).delete_all
  end

  private

  def delete_messages_in_batches(conversation_ids, batch_size:, max_batches:)
    return if conversation_ids.blank?

    batches_deleted = 0

    Message.where(conversation_id: conversation_ids).in_batches(of: batch_size) do |relation|
      relation.delete_all
      batches_deleted += 1
      break if batches_deleted >= max_batches
    end
  end
end
