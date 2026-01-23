# frozen_string_literal: true

module LorebookImport
  # Service for creating a placeholder Lorebook + LorebookUpload and enqueueing an async import job.
  #
  # This service contains no rendering/broadcasting logic. Callers can inject side-effects
  # via callbacks, keeping the service focused and controller-friendly.
  #
  class UploadEnqueuer
    Result = Data.define(:success?, :lorebook, :upload, :error, :error_code)

    # @param user [User] initiator used for the LorebookUpload record (used for UI broadcasts)
    # @param file [ActionDispatch::Http::UploadedFile, nil] uploaded file to attach and import
    # @param owner [User, nil] owner of the created lorebook (nil for global/system lorebooks)
    # @param visibility [String] visibility of the lorebook ("private" or "public")
    # @param name_override [String, nil] optional name override
    # @param job_class [Class] ActiveJob class used to perform the import
    # @param on_created [Proc, nil] callback called after records are created
    #   Receives (lorebook, upload) as arguments.
    # @param on_enqueued [Proc, nil] callback called after the import job is enqueued
    #   Receives (lorebook, upload) as arguments.
    # @param on_error [Proc, nil] callback called on failure
    #   Receives (error_code, error) as arguments.
    def initialize(user:, file:, owner: nil, visibility: "public", name_override: nil, job_class: LorebookImportJob,
                   on_created: nil, on_enqueued: nil, on_error: nil)
      @user = user
      @file = file
      @owner = owner
      @visibility = visibility
      @name_override = name_override
      @job_class = job_class
      @on_created = on_created
      @on_enqueued = on_enqueued
      @on_error = on_error
    end

    def execute
      call
    end

    private

    attr_reader :user, :file, :owner, :visibility, :name_override, :job_class, :on_created, :on_enqueued, :on_error

    def call
      return emit_error(no_file_result) if file.blank?

      filename = file.original_filename.to_s
      return emit_error(unsupported_format_result) unless supported?(filename)

      lorebook, upload = create_records!(filename)
      on_created&.call(lorebook, upload)

      job_class.perform_later(upload.id)
      on_enqueued&.call(lorebook, upload)

      Result.new(success?: true, lorebook: lorebook, upload: upload, error: nil, error_code: nil)
    rescue ActiveRecord::RecordInvalid => e
      emit_error(record_invalid_result(e))
    rescue StandardError => e
      emit_error(Result.new(success?: false, lorebook: nil, upload: nil, error: e.message, error_code: :error))
    end

    def supported?(filename)
      File.extname(filename).downcase == ".json"
    end

    def create_records!(filename)
      lorebook = nil
      upload = nil

      ActiveRecord::Base.transaction do
        base_name = File.basename(filename, ".*").presence || "Imported Lorebook"
        resolved_name = name_override.presence || base_name

        lorebook = Lorebook.create!(
          name: resolved_name,
          status: "pending",
          visibility: visibility,
          user: owner
        )

        upload = user.lorebook_uploads.create!(
          filename: filename,
          content_type: file.content_type,
          status: "pending",
          lorebook: lorebook
        )

        upload.file.attach(file)
      end

      [lorebook, upload]
    end

    def no_file_result
      Result.new(success?: false, lorebook: nil, upload: nil, error: "No file provided", error_code: :no_file)
    end

    def unsupported_format_result
      Result.new(success?: false, lorebook: nil, upload: nil, error: "Unsupported file format", error_code: :unsupported_format)
    end

    def record_invalid_result(error)
      Result.new(
        success?: false,
        lorebook: nil,
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
