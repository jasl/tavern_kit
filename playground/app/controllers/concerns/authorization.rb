# frozen_string_literal: true

# Authorization concern for resource access control.
#
# Provides helper methods for checking if the current user can
# administer spaces, messages, and other resources.
#
# @example Restrict action to room administrators
#   before_action :ensure_can_administer, only: %i[edit update destroy]
#
module Authorization
  extend ActiveSupport::Concern

  private

  # Ensure current user can administer the given resource.
  #
  # For spaces: user must be the creator or an administrator.
  # For messages: user must own the message or be an administrator.
  #
  # @param resource [Space, Conversation, Message] the resource to check
  # @return [Boolean] true if authorized
  # @raise [Head :forbidden] if not authorized
  def ensure_can_administer(resource = nil)
    resource ||= @space || @conversation || @message
    head :forbidden unless can_administer?(resource)
  end

  # Check if current user can administer a resource.
  #
  # @param resource [Space, Conversation, Message, nil] the resource to check
  # @return [Boolean] true if user can administer
  def can_administer?(resource)
    return false unless Current.user

    case resource
    when Space
      resource.owner_id == Current.user.id || Current.user.administrator?
    when Conversation
      resource.space.owner_id == Current.user.id || Current.user.administrator?
    when Message
      resource.space_membership.user_id == Current.user.id ||
        resource.conversation.space.owner_id == Current.user.id ||
        Current.user.administrator?
    else
      Current.user.administrator?
    end
  end

  # Check if current user can moderate (manage messages, conversations).
  #
  # @return [Boolean] true if user can moderate
  def can_moderate?
    Current.user&.can_moderate?
  end

  # Ensure current user is the space creator or administrator.
  #
  # Used for actions like editing space settings.
  def ensure_space_admin
    head :forbidden unless can_administer?(@space)
  end

  # Ensure space is writable (active).
  #
  # Non-active spaces (archived/deleting) are treated as read-only:
  # all write operations are forbidden.
  def ensure_space_writable
    head :forbidden unless @space&.active?
  end

  # Ensure current user owns the message or is an administrator.
  #
  # Used for editing and deleting messages.
  def ensure_message_owner
    head :forbidden unless can_administer?(@message)
  end
end
