# frozen_string_literal: true

module CharacterImport
  # Service for creating a placeholder Character + CharacterUpload and enqueueing an async import job.
  #
  # This service contains no rendering/broadcasting logic. Callers can inject side-effects
  # via callbacks, keeping the service focused and controller-friendly.
  #
  # @example Basic usage (controller)
  #   result = CharacterImport::UploadEnqueuer.new(user: Current.user, file: params[:file]).call
  #   if result.success?
  #     redirect_to settings_characters_path, notice: t("characters.create.queued")
  #   else
  #     redirect_to settings_characters_path, alert: t("characters.create.unsupported_format")
  #   end
  #
  # @example Hook points (optional)
  #   CharacterImport::UploadEnqueuer.new(
  #     user: Current.user,
  #     file: params[:file],
  #     on_created: ->(character, upload) {
  #       Rails.logger.info("Created placeholder character=#{character.id} upload=#{upload.id}")
  #     },
  #     on_enqueued: ->(character, upload) {
  #       # e.g. metrics
  #     },
  #     on_error: ->(error_code, error) {
  #       # e.g. error reporting
  #     }
  #   ).call
  #
  class UploadEnqueuer
    Result = Data.define(:success?, :character, :upload, :error, :error_code)

    # @param user [User] initiator used for the CharacterUpload record (used for UI broadcasts)
    # @param file [ActionDispatch::Http::UploadedFile, nil] uploaded file to attach and import
    # @param job_class [Class] ActiveJob class used to perform the import
    # @param on_created [Proc, nil] callback called after records are created
    #   Receives (character, upload) as arguments.
    # @param on_enqueued [Proc, nil] callback called after the import job is enqueued
    #   Receives (character, upload) as arguments.
    # @param on_error [Proc, nil] callback called on failure
    #   Receives (error_code, error) as arguments.
    def self.call(user:, file:, job_class: CharacterImportJob, on_created: nil, on_enqueued: nil, on_error: nil)
      new(
        user: user,
        file: file,
        job_class: job_class,
        on_created: on_created,
        on_enqueued: on_enqueued,
        on_error: on_error
      ).call
    end

    def initialize(user:, file:, job_class: CharacterImportJob, on_created: nil, on_enqueued: nil, on_error: nil)
      @user = user
      @file = file
      @job_class = job_class
      @on_created = on_created
      @on_enqueued = on_enqueued
      @on_error = on_error
    end

    # Executes the upload enqueue flow.
    #
    # @return [Result]
    def call
      return emit_error(no_file_result) if file.blank?

      filename = file.original_filename.to_s
      return emit_error(unsupported_format_result) unless Detector.supported?(filename)

      character, upload = create_records!(filename)
      on_created&.call(character, upload)

      job_class.perform_later(upload.id)
      on_enqueued&.call(character, upload)

      Result.new(success?: true, character: character, upload: upload, error: nil, error_code: nil)
    rescue ActiveRecord::RecordInvalid => e
      emit_error(record_invalid_result(e))
    rescue StandardError => e
      emit_error(Result.new(success?: false, character: nil, upload: nil, error: e.message, error_code: :error))
    end

    private

    attr_reader :user, :file, :job_class, :on_created, :on_enqueued, :on_error

    def create_records!(filename)
      character = nil
      upload = nil

      ActiveRecord::Base.transaction do
        placeholder_name = File.basename(filename, ".*").presence || "Untitled"

        character = Character.create!(
          name: placeholder_name,
          status: "pending",
          user: nil
        )

        upload = user.character_uploads.create!(
          filename: filename,
          content_type: file.content_type,
          status: "pending",
          character: character
        )

        upload.file.attach(file)
      end

      [character, upload]
    end

    def no_file_result
      Result.new(success?: false, character: nil, upload: nil, error: "No file provided", error_code: :no_file)
    end

    def unsupported_format_result
      Result.new(success?: false, character: nil, upload: nil, error: "Unsupported file format", error_code: :unsupported_format)
    end

    def record_invalid_result(error)
      Result.new(
        success?: false,
        character: nil,
        upload: nil,
        error: error.record.errors.full_messages.to_sentence,
        error_code: :invalid
      )
    end

    def emit_error(result)
      on_error&.call(result.error_code, result.error)
      result
    end
  end
end
