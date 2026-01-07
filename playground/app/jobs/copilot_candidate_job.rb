# frozen_string_literal: true

# Background job for generating copilot candidate replies.
#
# Delegates to Conversations::CopilotCandidateGenerator to keep the job thin.
#
# @example Generate 2 candidate replies
#   CopilotCandidateJob.perform_later(conversation.id, participant.id, generation_id: SecureRandom.uuid, candidate_count: 2)
#
class CopilotCandidateJob < ApplicationJob
  queue_as :default

  # Discard if conversation or participant no longer exists
  discard_on ActiveRecord::RecordNotFound

  # Generate candidate replies for the given conversation and participant.
  #
  # @param conversation_id [Integer] the Conversation ID
  # @param space_membership_id [Integer] the SpaceMembership ID (user+character)
  # @param generation_id [String] unique ID for this generation request
  # @param candidate_count [Integer] number of candidates to generate (1-4)
  def perform(conversation_id, space_membership_id, generation_id:, candidate_count: 1)
    conversation = Conversation.find(conversation_id)
    membership = conversation.space.space_memberships.find(space_membership_id)

    Conversations::CopilotCandidateGenerator.new(
      conversation: conversation,
      participant: membership,
      generation_id: generation_id,
      candidate_count: candidate_count
    ).call
  end
end
