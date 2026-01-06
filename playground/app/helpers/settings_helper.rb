# frozen_string_literal: true

module SettingsHelper
  # Check if the current controller is within a specific settings section.
  # Handles nested controllers (e.g., settings/lorebooks/entries).
  #
  # @param section [Symbol] The settings section to check (:characters, :llm_providers, :presets, :lorebooks)
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
    else
      false
    end
  end
end
