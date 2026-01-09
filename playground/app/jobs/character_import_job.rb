# frozen_string_literal: true

# Background job for processing character imports.
#
# Takes a CharacterUpload ID and processes the attached file through
# the appropriate importer based on file format detection.
#
# @example Enqueue an import
#   upload = CharacterUpload.create!(user: current_user, filename: "char.json")
#   upload.file.attach(io: file, filename: "char.json")
#   CharacterImportJob.perform_later(upload.id)
#
class CharacterImportJob < ApplicationJob
  queue_as :default

  # Retry on transient errors
  retry_on ActiveStorage::FileNotFoundError, wait: :polynomially_longer, attempts: 3
  retry_on ActiveRecord::Deadlocked, wait: :polynomially_longer, attempts: 3

  # Discard if upload no longer exists
  discard_on ActiveRecord::RecordNotFound

  # Process the character upload.
  #
  # @param upload_id [Integer] the CharacterUpload ID to process
  def perform(upload_id)
    upload = CharacterUpload.find(upload_id)

    # Skip if already processed or no file attached
    return unless upload.pending?
    return mark_failed(upload, "No file attached") unless upload.file.attached?

    upload.mark_processing!

    # Download and process the file
    process_upload(upload)
  rescue CharacterImport::InvalidCardError => e
    mark_failed(upload, "Invalid character card: #{e.message}")
  rescue CharacterImport::UnsupportedFormatError => e
    mark_failed(upload, "Unsupported format: #{e.message}")
  rescue JSON::ParserError => e
    mark_failed(upload, "Invalid JSON: #{e.message}")
  rescue StandardError => e
    mark_failed(upload, "Import failed: #{e.message}")
    raise # Re-raise for retry mechanism
  end

  private

  # Process the uploaded file through the import pipeline.
  #
  # @param upload [CharacterUpload] the upload to process
  def process_upload(upload)
    placeholder_character = upload.character

    # Download the attached file to a tempfile
    upload.file.open do |tempfile|
      result = CharacterImport::Detector.import(
        tempfile,
        filename: upload.filename,
        character: placeholder_character
      )

      if result.success?
        upload.mark_completed!(result.character)
        # Ensure updated_at is fresh for cache busting (portrait may have been attached)
        result.character.touch
        result.character.reload
        # Broadcast update to replace pending card with ready card
        broadcast_character_replace(upload.user, result.character)
        # Broadcast success toast notification
        broadcast_toast(upload.user, I18n.t("characters.import.success", name: result.character.name), :success)
      elsif result.duplicate?
        # Destroy placeholder if it's different from the duplicate, then broadcast removal
        # Order matters: destroy first to ensure UI/DB consistency
        if placeholder_character && placeholder_character != result.character
          placeholder_character_id = placeholder_character.id
          placeholder_character.destroy
          # Broadcast removal AFTER successful destroy
          broadcast_character_remove(upload.user, placeholder_character_id)
        end
        # Link to existing character on duplicate
        upload.mark_completed!(result.character)
        # Broadcast duplicate toast notification
        broadcast_toast(upload.user, I18n.t("characters.import.duplicate", name: result.character.name), :warning)
      else
        # Mark placeholder character as failed
        placeholder_character&.mark_failed!(result.error)
        # Broadcast update to show failed state
        broadcast_character_replace(upload.user, placeholder_character) if placeholder_character
        mark_failed(upload, result.error || "Unknown import error")
      end
    end
  end

  # Mark the upload as failed with an error message.
  #
  # @param upload [CharacterUpload] the upload to mark failed
  # @param message [String] error description
  def mark_failed(upload, message)
    # Also mark placeholder character as failed
    upload.character&.mark_failed!(message)
    upload.mark_failed!(message)
  end

  # Broadcast a character card replacement via Turbo Streams.
  #
  # @param user [User] the user to broadcast to
  # @param character [Character] the character to render
  def broadcast_character_replace(user, character)
    return unless user && character

    target = ActionView::RecordIdentifier.dom_id(character)

    # Broadcast to Settings page (admin view)
    Turbo::StreamsChannel.broadcast_replace_to(
      [user, :characters],
      target: target,
      partial: "settings/characters/character",
      locals: { character: character }
    )

    # Broadcast to user-facing Characters page
    Turbo::StreamsChannel.broadcast_replace_to(
      [user, :characters_public],
      target: target,
      partial: "characters/character_card",
      locals: { character: character }
    )
  end

  # Broadcast a character card removal via Turbo Streams.
  #
  # @param user [User] the user to broadcast to
  # @param character_or_id [Character, Integer] the character or its ID to remove
  def broadcast_character_remove(user, character_or_id)
    return unless user && character_or_id

    target =
      if character_or_id.is_a?(Integer)
        "character_#{character_or_id}"
      else
        ActionView::RecordIdentifier.dom_id(character_or_id)
      end

    # Remove from Settings page
    Turbo::StreamsChannel.broadcast_remove_to(
      [user, :characters],
      target: target
    )

    # Remove from user-facing Characters page
    Turbo::StreamsChannel.broadcast_remove_to(
      [user, :characters_public],
      target: target
    )
  end

  # Broadcast a toast notification via Turbo Streams.
  #
  # @param user [User] the user to broadcast to
  # @param message [String] the notification message
  # @param type [Symbol] the notification type (:success, :error, :warning, :info)
  def broadcast_toast(user, message, type = :info)
    return unless user && message.present?

    # Broadcast to Settings page
    Turbo::StreamsChannel.broadcast_action_to(
      [user, :characters],
      action: :show_toast,
      target: nil,
      partial: "shared/toast",
      locals: { message: message, type: type }
    )

    # Broadcast to user-facing Characters page
    Turbo::StreamsChannel.broadcast_action_to(
      [user, :characters_public],
      action: :show_toast,
      target: nil,
      partial: "shared/toast",
      locals: { message: message, type: type }
    )
  end
end
