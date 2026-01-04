# frozen_string_literal: true

# Helper methods for rendering chat messages.
#
# Provides consistent message formatting including sender names,
# role badges, timestamps, and CSS classes for different message types.
module MessageHelper
  # Get the display name for a message sender.
  #
  # @param message [Message] the message
  # @return [String] the sender's display name
  def message_sender_name(message)
    message.sender_display_name
  end

  # Render badges indicating the message role and membership status.
  #
  # @param message [Message] the message
  # @return [String, nil] HTML for the badges or nil
  def message_role_badge(message)
    badges = []

    if message.space_membership.removed?
      badges << content_tag(:span, t("messages.role.removed", default: "Removed"), class: "badge badge-xs badge-error badge-outline")
    end

    if message.system?
      badges << content_tag(:span, t("messages.role.system", default: "System"), class: "badge badge-xs badge-ghost")
    end

    safe_join(badges, " ") if badges.any?
  end

  # Format a message timestamp.
  #
  # @param message [Message] the message
  # @param format [Symbol] :relative, :time, :full
  # @return [String] formatted timestamp
  def message_timestamp(message, format: :relative)
    return "" unless message.created_at

    case format
    when :relative
      time_ago_in_words(message.created_at)
    when :time
      message.created_at.strftime("%H:%M")
    when :full
      l(message.created_at, format: :long)
    else
      message.created_at.strftime("%H:%M")
    end
  end

  # Get the chat alignment class for daisyUI chat component.
  #
  # User messages (including those from persona characters) appear on the right.
  # AI character messages appear on the left.
  #
  # @param message [Message] the message
  # @return [String] "chat-start" or "chat-end"
  def message_chat_alignment(message)
    message.space_membership.user? ? "chat-end" : "chat-start"
  end

  # Get the chat bubble color class.
  #
  # Distinguishes between:
  # - User manual input: primary color (right side)
  # - User AI-generated (full copilot): accent color (right side, different shade)
  # - AI character: secondary color (left side)
  # - System: neutral color
  # - Errored: error color (any role)
  #
  # @param message [Message] the message
  # @return [String] CSS class for bubble color
  def message_bubble_class(message)
    # Errored messages get error styling regardless of role
    return "chat-bubble-error" if message.errored?

    # User participant messages (including persona characters via full copilot)
    if message.space_membership.user?
      if message.ai_generated?
        # AI-generated message for user's persona - use accent to distinguish
        "chat-bubble-accent"
      else
        # User's manual input
        "chat-bubble-primary"
      end
    elsif message.system?
      "chat-bubble-neutral"
    else
      # AI character messages
      "chat-bubble-secondary"
    end
  end
end
