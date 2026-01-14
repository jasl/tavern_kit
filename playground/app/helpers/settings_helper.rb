# frozen_string_literal: true

module SettingsHelper
  # Check if the current controller is within a specific settings section.
  # Handles nested controllers (e.g., settings/lorebooks/entries).
  #
  # @param section [Symbol] The settings section to check (:characters, :llm_providers, :presets, :lorebooks, :general)
  # @return [Boolean] true if the current controller is within the specified section
  def settings_section_active?(section)
    case section
    when :characters
      controller_path.start_with?("settings/characters")
    when :llm_providers
      controller_path.start_with?("settings/llm_providers")
    when :presets
      controller_path.start_with?("settings/presets")
    when :lorebooks
      controller_path.start_with?("settings/lorebooks")
    when :users
      controller_path.start_with?("settings/users")
    when :invite_codes
      controller_path.start_with?("settings/invite_codes")
    when :general
      controller_path.start_with?("settings/general")
    else
      false
    end
  end

  # DOM id for Settings list cards.
  #
  # Note: this is intentionally centralized so we can evolve id conventions
  # without chasing ad-hoc strings across templates/tests.
  def settings_card_dom_id(record)
    return nil unless record

    case record
    when LLMProvider
      "provider_#{record.id}"
    when Preset
      "preset_#{record.id}"
    when Lorebook
      "lorebook_#{record.id}"
    when User
      "user_#{record.id}"
    when InviteCode
      "invite_code_#{record.id}"
    else
      dom_id(record)
    end
  end

  # Determine the partial name for a schema field based on its control type.
  #
  # @param field [Hash] The field definition from FieldEnumerator
  # @return [String] The partial name (e.g., "text", "textarea", "toggle")
  def partial_for_field(field)
    control = field[:control].to_s

    case control
    when "slider" then "range"
    when "number" then "number"
    when "toggle" then "toggle"
    when "select" then "select"
    when "text" then "text"
    when "textarea" then "textarea"
    when "tags" then "tags"
    else
      # Fallback based on type
      if field[:type] == "boolean"
        "toggle"
      elsif field[:enum].present?
        "select"
      elsif field[:type].in?(%w[number integer])
        "number"
      else
        "text"
      end
    end
  end
end
