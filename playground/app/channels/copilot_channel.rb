# frozen_string_literal: true

# Channel for copilot-related real-time events.
#
# Handles:
# - copilot_candidate: Generated suggestion text
# - copilot_complete: Generation finished
# - copilot_error: Generation failed
# - copilot_disabled: Full mode auto-disabled due to error
#
# Follows Campfire's pattern of separating concerns:
# - Turbo Streams handle DOM updates (messages)
# - Custom channels handle application-specific events (copilot)
#
# Streams per-participant (not per-conversation) to ensure copilot events are
# unicast to the requesting user only, preventing data leakage in
# multi-user spaces.
#
# @example Subscribe from JavaScript
#   cable.subscribeTo({ channel: "CopilotChannel", conversation_id: 123, space_membership_id: 456 })
#
class CopilotChannel < ApplicationCable::Channel
  def subscribed
    @conversation = find_conversation
    @space_membership = find_space_membership

    if @space_membership && can_use_copilot?
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

  def can_use_copilot?
    # Allow all authenticated space participants to subscribe.
    # Note: Copilot events are only broadcast when copilot_mode is enabled,
    # and the SpaceMembership model already validates that copilot requires
    # both user_id and character_id (human with persona).
    true
  end
end
