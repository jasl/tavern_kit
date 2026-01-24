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

  # Render badge for messages excluded from AI context.
  #
  # Shows a warning badge when a message is marked as excluded from the prompt.
  # The message will still be visible in chat but won't be sent to the LLM.
  #
  # @param message [Message] the message
  # @return [String, nil] HTML for the excluded badge or nil
  def message_excluded_badge(message)
    return unless message.visibility_excluded?

    content_tag(
      :span,
      t("messages.excluded_from_context", default: "Excluded"),
      class: "badge badge-xs badge-warning badge-outline gap-1",
      title: t("messages.excluded_from_context_hint", default: "This message is not sent to the AI")
    )
  end

  # Format a message timestamp.
  #
  # @param message [Message] the message
  # @param format [Symbol] :relative, :time, :full, :full_date_time
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
    when :full_date_time
      # SillyTavern style: "January 10, 2026 12:31 AM"
      message.created_at.strftime("%B %d, %Y %l:%M %p")
    else
      message.created_at.strftime("%H:%M")
    end
  end

  def message_translation_text(message, space:)
    settings = space.prompt_settings&.i18n
    return nil unless settings
    return nil unless settings.mode == "translate_both"

    target_lang = settings.target_lang.to_s
    return nil if target_lang.blank?

    if message.active_message_swipe
      message.active_message_swipe&.metadata&.dig("i18n", "translations", target_lang, "text")&.presence
    else
      message.metadata&.dig("i18n", "translations", target_lang, "text")&.presence
    end
  end

  def message_translation_error(message, space:)
    settings = space.prompt_settings&.i18n
    return nil unless settings
    return nil unless settings.mode == "translate_both"

    target_lang = settings.target_lang.to_s
    return nil if target_lang.blank?

    error =
      if message.active_message_swipe
        message.active_message_swipe&.metadata&.dig("i18n", "last_error")
      else
        message.metadata&.dig("i18n", "last_error")
      end
    return nil unless error.is_a?(Hash)
    return nil unless error["target_lang"].to_s == target_lang

    error
  end

  def message_translation_pending?(message, space:)
    settings = space.prompt_settings&.i18n
    return false unless settings
    return false unless settings.mode == "translate_both"

    target_lang = settings.target_lang.to_s
    return false if target_lang.blank?

    if message.active_message_swipe
      message.active_message_swipe&.metadata&.dig("i18n", "translation_pending", target_lang) == true
    else
      message.metadata&.dig("i18n", "translation_pending", target_lang) == true
    end
  end

  def message_display_text(message, space:)
    settings = space.prompt_settings&.i18n
    return message.content.to_s unless settings&.mode == "translate_both"
    return message.content.to_s unless message.assistant?

    message_translation_text(message, space: space) || message.content.to_s
  end
end
