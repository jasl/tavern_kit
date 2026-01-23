# frozen_string_literal: true

# Background job for processing lorebook imports.
#
# Takes a LorebookUpload ID and processes the attached JSON file,
# updating the placeholder Lorebook and broadcasting UI updates.
#
class LorebookImportJob < ApplicationJob
  queue_as :uploads

  retry_on ActiveStorage::FileNotFoundError, wait: :polynomially_longer, attempts: 3
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  discard_on ActiveRecord::RecordNotFound

  def perform(upload_id)
    upload = LorebookUpload.find(upload_id)

    return unless upload.pending?
    return mark_failed(upload, "No file attached") unless upload.file.attached?
    return mark_failed(upload, "No placeholder lorebook") unless upload.lorebook

    upload.mark_processing!
    process_upload(upload)
  rescue JSON::ParserError => e
    mark_failed(upload, "Invalid JSON: #{e.message}")
  rescue StandardError => e
    mark_failed(upload, "Import failed: #{e.message}")
    raise
  end

  private

  def process_upload(upload)
    placeholder = upload.lorebook

    upload.file.open do |tempfile|
      content = tempfile.read
      file_sha256 = Digest::SHA256.hexdigest(content)

      if (existing = find_duplicate(file_sha256, lorebook: placeholder))
        placeholder_id = placeholder.id
        upload.mark_completed!(existing)
        placeholder.destroy

        broadcast_lorebook_remove(upload.user, placeholder_id)
        broadcast_toast(
          upload.user,
          I18n.t("lorebooks.import_duplicate",
                 name: existing.name,
                 default: "Lorebook '%{name}' already exists (skipped duplicate)."),
          :warning
        )
        next
      end

      json_data = JSON.parse(content)

      imported = Lorebook.import_from_json(json_data, name_override: placeholder.name)
      apply_import!(placeholder, imported, file_sha256: file_sha256)

      placeholder.mark_ready!
      placeholder.reload

      upload.mark_completed!(placeholder)

      broadcast_lorebook_replace(upload.user, placeholder)
      broadcast_toast(upload.user, I18n.t("lorebooks.imported", count: placeholder.entries_count), :success)
    end
  end

  def apply_import!(placeholder, imported, file_sha256:)
    now = Time.current

    ActiveRecord::Base.transaction do
      LorebookEntry.where(lorebook_id: placeholder.id).delete_all

      placeholder.assign_attributes(
        description: imported.description,
        scan_depth: imported.scan_depth,
        token_budget: imported.token_budget,
        recursive_scanning: imported.recursive_scanning,
        settings: imported.settings || {},
        file_sha256: file_sha256
      )
      placeholder.save!

      entries =
        imported.entries.map { |e|
          e.attributes
           .except("id", "lorebook_id", "created_at", "updated_at")
           .merge(
             "lorebook_id" => placeholder.id,
             "created_at" => now,
             "updated_at" => now
           )
        }

      LorebookEntry.insert_all!(entries) if entries.any?
      placeholder.update_column(:entries_count, entries.size)
    end
  end

  def find_duplicate(file_sha256, lorebook:)
    return nil if file_sha256.blank?

    scope = Lorebook.where(file_sha256: file_sha256, user_id: lorebook&.user_id)
    scope = scope.where.not(id: lorebook.id) if lorebook&.persisted?

    scope.first
  end

  def mark_failed(upload, message)
    upload.lorebook&.mark_failed!(message)
    upload.mark_failed!(message)

    broadcast_lorebook_replace(upload.user, upload.lorebook) if upload.lorebook
    broadcast_toast(upload.user, I18n.t("lorebooks.import_error", error: message), :error)
  end

  def broadcast_lorebook_replace(user, lorebook)
    return unless user && lorebook

    ensure_routes_loaded_for_rendering!

    target = ActionView::RecordIdentifier.dom_id(lorebook)

    Turbo::StreamsChannel.broadcast_replace_to(
      [user, :lorebooks],
      target: target,
      partial: "settings/lorebooks/lorebook_card",
      locals: { lorebook: lorebook }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [user, :lorebooks_public],
      target: target,
      partial: "lorebooks/lorebook_card",
      locals: { lorebook: lorebook }
    )
  end

  def broadcast_lorebook_remove(user, lorebook_or_id)
    return unless user && lorebook_or_id

    target =
      if lorebook_or_id.is_a?(Integer)
        "lorebook_#{lorebook_or_id}"
      else
        ActionView::RecordIdentifier.dom_id(lorebook_or_id)
      end

    Turbo::StreamsChannel.broadcast_remove_to(
      [user, :lorebooks],
      target: target
    )

    Turbo::StreamsChannel.broadcast_remove_to(
      [user, :lorebooks_public],
      target: target
    )
  end

  def broadcast_toast(user, message, type = :info)
    return unless user && message.present?

    Turbo::StreamsChannel.broadcast_action_to(
      [user, :lorebooks],
      action: :show_toast,
      target: nil,
      partial: "shared/toast",
      locals: { message: message, type: type }
    )

    Turbo::StreamsChannel.broadcast_action_to(
      [user, :lorebooks_public],
      action: :show_toast,
      target: nil,
      partial: "shared/toast",
      locals: { message: message, type: type }
    )
  end
end
