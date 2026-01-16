# frozen_string_literal: true

# Presenter for Preset cards in index pages (public + settings).
#
# Goals:
# - Keep ERB free of permission/path logic
# - Keep UI consistent between namespaces
class PresetCardPresenter
  include Rails.application.routes.url_helpers

  attr_reader :preset, :default_preset

  def initialize(preset:, default_preset: nil, mode: :public)
    @preset = preset
    @default_preset = default_preset
    @mode = mode.to_sym
  end

  def settings_mode?
    @mode == :settings
  end

  def default?
    default_preset&.id == preset.id
  end

  def global?
    preset.user_id.nil?
  end

  def owner?
    preset.user_id == Current.user&.id
  end

  def locked?
    preset.locked?
  end

  def draft?
    preset.draft?
  end

  def can_edit?
    return !locked? if settings_mode?

    owner? && !locked?
  end

  def title_path
    return settings_preset_path(preset) if settings_mode? && locked?
    return edit_settings_preset_path(preset) if settings_mode? && can_edit?

    preset_path(preset)
  end

  def primary_action_path
    return settings_preset_path(preset) if settings_mode? && locked?
    return edit_settings_preset_path(preset) if settings_mode? && can_edit?

    can_edit? ? edit_preset_path(preset) : preset_path(preset)
  end

  def primary_action_label
    (settings_mode? && can_edit?) || (!settings_mode? && can_edit?) ? I18n.t("common.edit", default: "Edit") : I18n.t("common.view", default: "View")
  end

  def duplicate_path
    settings_mode? ? duplicate_settings_preset_path(preset) : duplicate_preset_path(preset)
  end

  def export_path
    settings_mode? ? export_settings_preset_path(preset) : export_preset_path(preset)
  end

  def delete_path
    settings_mode? ? settings_preset_path(preset) : preset_path(preset)
  end

  def can_delete?
    return false if locked? || default?
    return true if settings_mode?

    owner?
  end

  # Settings-only actions
  def can_set_default?
    settings_mode? && !default?
  end

  def set_default_path
    set_default_settings_preset_path(preset)
  end

  def can_toggle_lock?
    settings_mode?
  end

  def lock_toggle_path
    locked? ? unlock_settings_preset_path(preset) : lock_settings_preset_path(preset)
  end

  def lock_toggle_label
    locked? ? I18n.t("common.unlock", default: "Unlock") : I18n.t("common.lock", default: "Lock")
  end

  def lock_toggle_icon
    locked? ? "unlock" : "lock"
  end

  def can_toggle_publish?
    settings_mode?
  end

  def publish_toggle_path
    draft? ? publish_settings_preset_path(preset) : unpublish_settings_preset_path(preset)
  end

  def publish_toggle_label
    draft? ? I18n.t("common.publish", default: "Publish") : I18n.t("common.unpublish", default: "Unpublish")
  end

  def publish_toggle_icon
    draft? ? "eye" : "eye-off"
  end

  def created_by_label
    return preset.user.name.to_s if preset.user.present?

    I18n.t("common.system", default: "System")
  end

  def effective_provider
    preset.effective_llm_provider
  end
end
