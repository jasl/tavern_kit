# frozen_string_literal: true

# Presenter for Lorebook cards in index pages (public + settings).
#
# Goals:
# - Keep ERB free of permission/path logic
# - Avoid SQL in views (use counter_cache entries_count)
class LorebookCardPresenter
  include Rails.application.routes.url_helpers

  attr_reader :lorebook

  def initialize(lorebook:, mode: :public)
    @lorebook = lorebook
    @mode = mode.to_sym
  end

  def settings_mode?
    @mode == :settings
  end

  def global?
    lorebook.user_id.nil?
  end

  def owner?
    lorebook.user_id == Current.user&.id
  end

  # Whether this lorebook has a duplicate name among the current user's own lorebooks.
  #
  # We intentionally ignore:
  # - system/global lorebooks (fallback + admin-maintained)
  # - other users' lorebooks (avoid leaking information about private records)
  def duplicate_name?
    return false unless owner?

    @duplicate_name ||= Lorebook.where(user_id: lorebook.user_id, name: lorebook.name).where.not(id: lorebook.id).exists?
  end

  def locked?
    lorebook.locked?
  end

  def pending?
    lorebook.respond_to?(:pending?) && lorebook.pending?
  end

  def ready?
    !lorebook.respond_to?(:ready?) || lorebook.ready?
  end

  def failed?
    lorebook.respond_to?(:failed?) && lorebook.failed?
  end

  def draft?
    lorebook.draft?
  end

  def recursive?
    lorebook.recursive_scanning == true
  end

  def can_edit?
    return false unless ready?
    return !locked? if settings_mode?

    owner? && !locked?
  end

  def title_path
    return settings_lorebook_path(lorebook) if settings_mode? && locked?
    return edit_settings_lorebook_path(lorebook) if settings_mode? && can_edit?

    lorebook_path(lorebook)
  end

  def primary_action_path
    return settings_lorebook_path(lorebook) if settings_mode? && locked?
    return edit_settings_lorebook_path(lorebook) if settings_mode? && can_edit?

    can_edit? ? edit_lorebook_path(lorebook) : lorebook_path(lorebook)
  end

  def primary_action_label
    (settings_mode? && can_edit?) || (!settings_mode? && can_edit?) ? I18n.t("common.edit", default: "Edit") : I18n.t("common.view", default: "View")
  end

  def duplicate_path
    settings_mode? ? duplicate_settings_lorebook_path(lorebook) : duplicate_lorebook_path(lorebook)
  end

  def export_path
    settings_mode? ? export_settings_lorebook_path(lorebook) : export_lorebook_path(lorebook)
  end

  def delete_path
    settings_mode? ? settings_lorebook_path(lorebook) : lorebook_path(lorebook)
  end

  def can_delete?
    return false if locked?
    return true if settings_mode?

    owner?
  end

  # Settings-only actions
  def can_toggle_lock?
    settings_mode?
  end

  def lock_toggle_path
    locked? ? unlock_settings_lorebook_path(lorebook) : lock_settings_lorebook_path(lorebook)
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
    draft? ? publish_settings_lorebook_path(lorebook) : unpublish_settings_lorebook_path(lorebook)
  end

  def publish_toggle_label
    draft? ? I18n.t("common.publish", default: "Publish") : I18n.t("common.unpublish", default: "Unpublish")
  end

  def publish_toggle_icon
    draft? ? "eye" : "eye-off"
  end

  def created_by_label
    return lorebook.user.name.to_s if lorebook.user.present?

    I18n.t("common.system", default: "System")
  end

  def entries_count
    lorebook.entries_count.to_i
  end

  def character_usage_count
    lorebook.approximate_character_usage_count(user: Current.user)
  end
end
