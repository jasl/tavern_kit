# frozen_string_literal: true

module Playgrounds
  # Controller for generating copilot candidate replies.
  #
  # Allows users with a persona character to generate suggested replies
  # without automatically sending them.
  #
  # @example Generate candidates
  #   POST /playgrounds/:playground_id/copilot_candidates
  #
  class CopilotCandidatesController < Playgrounds::ApplicationController
    include Authorization

    before_action :ensure_space_writable

    # POST /playgrounds/:playground_id/copilot_candidates
    #
    # Enqueues a job to generate candidate replies for the current user.
    #
    # @param candidate_count [Integer] number of candidates to generate (1-4, default 1)
    # @return [JSON] generation_id for tracking the request
    def create
      user_membership = @playground.space_memberships.active.find_by(user: Current.user, kind: "human")

      # Validate user can use copilot suggestions
      unless user_membership&.character_id.present?
        return render json: { error: "Copilot requires a persona character" }, status: :forbidden
      end

      if user_membership.copilot_full?
        return render json: { error: "Copilot suggestions disabled in full mode" }, status: :forbidden
      end

      # Get the root conversation for this playground
      conversation = @playground.conversations.root.first
      unless conversation
        return render json: { error: "No conversation found for this playground" }, status: :not_found
      end

      # Use client-provided generation_id or generate new one
      generation_id = params[:generation_id].presence || SecureRandom.uuid
      candidate_count = (params[:candidate_count] || 1).to_i.clamp(1, 4)

      CopilotCandidateJob.perform_later(
        conversation.id,
        user_membership.id,
        generation_id: generation_id,
        candidate_count: candidate_count
      )

      render json: { generation_id: generation_id }
    end
  end
end
