# frozen_string_literal: true

# Background job for generating a single Auto suggestion candidate.
#
# Each candidate is generated in its own job, allowing SolidQueue to
# parallelize them naturally using the llm queue's thread pool.
#
# Frontend tracks completion by counting received candidates, so no
# server-side coordination is needed.
#
# @example Generate 3 candidate replies (enqueue 3 jobs)
#   generation_id = SecureRandom.uuid
#   3.times do |i|
#     AutoCandidateJob.perform_later(
#       conversation.id, membership.id,
#       generation_id: generation_id, index: i
#     )
#   end
#
class AutoCandidateJob < ApplicationJob
  queue_as :llm

  discard_on ActiveRecord::RecordNotFound

  # Generate a single candidate reply.
  #
  # @param conversation_id [Integer] the Conversation ID
  # @param space_membership_id [Integer] the SpaceMembership ID (human)
  # @param generation_id [String] unique ID for this generation batch
  # @param index [Integer] the candidate index (0-based)
  def perform(conversation_id, space_membership_id, generation_id:, index:)
    conversation = Conversation.find(conversation_id)
    membership = conversation.space.space_memberships.find(space_membership_id)

    Conversations::AutoCandidateGenerator.generate_single(
      conversation: conversation,
      participant: membership,
      generation_id: generation_id,
      index: index
    )
  end
end
