# frozen_string_literal: true

# Authorization concern for resource access control.
#
# Provides helper methods for checking if the current user can
# administer spaces, messages, and other resources.
#
# @example Restrict action to space administrators
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
  # @return [void] Renders/redirects if not authorized
  def ensure_can_administer(resource = nil)
    resource ||= @space || @conversation || @message
    return if can_administer?(resource)

    deny_access!(
      message: t("authorization.not_authorized", default: "You are not authorized to perform this action."),
      status: :forbidden
    )
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
    return if can_administer?(@space)

    deny_access!(
      message: t("authorization.space_admin_required", default: "You are not authorized to manage this space."),
      status: :forbidden
    )
  end

  # Ensure space is writable (active).
  #
  # Non-active spaces (archived/deleting) are treated as read-only:
  # all write operations are forbidden.
  def ensure_space_writable
    return if @space&.active?

    message = if @space&.archived?
      t("spaces.archived_read_only", default: "This chat is archived and read-only.")
    elsif @space&.deleting?
      t("spaces.deleting_read_only", default: "This chat is being deleted and is temporarily unavailable.")
    else
      t("spaces.read_only", default: "This chat is read-only.")
    end

    deny_access!(message: message, status: :forbidden)
  end

  # Ensure current user owns the message or is an administrator.
  #
  # Used for editing and deleting messages.
  def ensure_message_owner
    return if can_administer?(@message)

    deny_access!(
      message: t("authorization.message_owner_required", default: "You are not authorized to modify this message."),
      status: :forbidden
    )
  end

  def deny_access!(message:, status: :forbidden)
    respond_to do |format|
      format.turbo_stream do
        render_toast_turbo_stream(message: message, type: "error", duration: 5000, status: status)
      end
      format.html { render plain: message, status: status }
      format.json { head status }
      format.any { head status }
    end
  end
end
