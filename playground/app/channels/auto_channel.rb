# frozen_string_literal: true

# Channel for Auto-related real-time events (suggestions + status updates).
#
# Handles:
# - auto_candidate: Generated suggestion text
# - auto_candidate_error: Suggestion generation failed
# - auto_disabled: Auto was disabled (e.g., remaining steps exhausted)
# - auto_steps_updated: Remaining auto steps count changed
#
# Streams per-membership (not per-conversation) to ensure Auto events are unicast
# to the requesting user only, preventing data leakage in multi-user spaces.
#
# @example Subscribe from JavaScript
#   cable.subscribeTo({ channel: "AutoChannel", space_membership_id: 456 })
#
class AutoChannel < ApplicationCable::Channel
  def subscribed
    @conversation = find_conversation
    @space_membership = find_space_membership

    if @space_membership && can_use_auto?
      if @conversation && @conversation.space_id != @space_membership.space_id
        reject
        return
      end

      stream_for @space_membership
    else
      reject
    end
  end

  private

  def find_conversation
    return nil unless params[:conversation_id].present?

    Conversation.find_by(id: params[:conversation_id])
  end

  # Find the space membership, validating it belongs to the current user.
  #
  # @return [SpaceMembership, nil]
  def find_space_membership
    membership_id = params[:space_membership_id].presence || params[:participant_id].presence
    return nil unless membership_id

    current_user.space_memberships.active.find_by(id: membership_id)
  end

  def can_use_auto?
    true
  end
end
