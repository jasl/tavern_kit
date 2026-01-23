# frozen_string_literal: true

module Settings
  # Controller for managing standalone World Info / Lorebook files.
  #
  # Provides CRUD operations for lorebooks and import/export functionality.
  #
  class LorebooksController < Settings::ApplicationController
    before_action :set_lorebook, only: %i[show edit update destroy duplicate export lock unlock publish unpublish]

    def index
      # Note: Don't use with_entries_count here as it uses GROUP BY which breaks geared_pagination's count
      # The entries_count can be loaded via counter_cache or N+1 query in the view if needed
      lorebooks = Lorebook.ordered.includes(:user)

      # Ownership filter
      lorebooks = apply_ownership_filter(lorebooks)

      # Name search
      lorebooks = lorebooks.where("LOWER(name) LIKE ?", "%#{params[:q].downcase}%") if params[:q].present?

      set_page_and_extract_portion_from lorebooks, per_page: 20
    end

    def show
      @entries = @lorebook.entries.ordered.to_a
    end

    def new
      @lorebook = Lorebook.new
    end

    def create
      @lorebook = Lorebook.new(lorebook_params)
      @lorebook.visibility = "public" # New lorebooks are public by default

      if @lorebook.save
        redirect_to edit_settings_lorebook_path(@lorebook), notice: t("lorebooks.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      # Redirect to show view if locked (read-only)
      if @lorebook.locked?
        redirect_to settings_lorebook_path(@lorebook)
        return
      end

      @entries = @lorebook.entries.ordered.to_a
    end

    def update
      if @lorebook.locked?
        redirect_to settings_lorebook_path(@lorebook), alert: t("lorebooks.locked", default: "Lorebook is locked.")
        return
      end

      updates = lorebook_params.to_h
      updates[:file_sha256] = nil if @lorebook.file_sha256.present?

      if @lorebook.update(updates)
        redirect_to settings_lorebooks_path, notice: t("lorebooks.updated")
      else
        @entries = @lorebook.entries.ordered.to_a
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @lorebook.locked?
        redirect_to settings_lorebooks_path, alert: t("lorebooks.locked", default: "Lorebook is locked.")
        return
      end

      @lorebook.destroy!
      redirect_to settings_lorebooks_path, notice: t("lorebooks.deleted")
    end

    def duplicate
      copy = @lorebook.create_copy(visibility: "public")
      if copy.persisted?
        redirect_to settings_lorebooks_path, notice: t("lorebooks.duplicated")
      else
        redirect_to settings_lorebooks_path, alert: t("lorebooks.duplicate_failed")
      end
    end

    def export
      json_data = @lorebook.export_to_json
      filename = "#{@lorebook.name.parameterize.presence || 'lorebook'}.json"

      send_data JSON.pretty_generate(json_data),
                filename: filename,
                type: "application/json",
                disposition: "attachment"
    end

    def import
      files = Array(params[:file]).compact_blank

      if files.empty?
        message = t("lorebooks.import_no_file")
        respond_to do |format|
          format.html { redirect_to settings_lorebooks_path, alert: message }
          format.turbo_stream { render_turbo_stream_error(message) }
        end
        return
      end

      successes = []
      failures = []

      files.each do |file|
        name_override = resolve_import_name(files_count: files.size, file: file)

        result = LorebookImport::UploadEnqueuer.new(
          user: Current.user,
          file: file,
          owner: nil,
          visibility: "public",
          name_override: name_override
        ).execute

        if result.success?
          successes << result.lorebook
        else
          filename = file.respond_to?(:original_filename) ? file.original_filename.to_s : file.to_s
          failures << { filename: filename, message: import_error_message(result) }
        end
      end

      if successes.empty?
        details =
          failures.first(3).map { |f| "#{f[:filename]}: #{f[:message]}" }.join("; ")
        details += "; +#{failures.size - 3} more" if failures.size > 3
        message = t("lorebooks.import_error", error: details.presence || "Unknown error")

        respond_to do |format|
          format.html { redirect_to settings_lorebooks_path, alert: message }
          format.turbo_stream { render_turbo_stream_error(message) }
        end
        return
      end

      notice_message =
        if files.one? && failures.empty?
          "Lorebook import started. This may take a moment."
        else
          parts = []
          parts << "Queued #{successes.size} lorebook import#{'s' if successes.size != 1}."
          if failures.any?
            parts << "Failed to queue #{failures.size} file#{'s' if failures.size != 1}."
          end
          parts.join(" ")
        end

      respond_to do |format|
        format.html do
          flash = { notice: notice_message }
          if failures.any?
            details =
              failures.first(3).map { |f| "#{f[:filename]}: #{f[:message]}" }.join("; ")
            details += "; +#{failures.size - 3} more" if failures.size > 3
            flash[:alert] = details
          end
          redirect_to settings_lorebooks_path, flash: flash
        end
        format.turbo_stream do
          streams = []
          streams << turbo_stream.remove("lorebooks_empty_state")
          successes.reverse_each do |lorebook|
            streams << turbo_stream.prepend("lorebooks_list", partial: "lorebook_card", locals: { lorebook: lorebook })
          end
          streams << turbo_stream.action(:close_modal, "import_modal")
          streams << turbo_stream.action(:show_toast, nil) do
            render_to_string(partial: "shared/toast", locals: { message: notice_message, type: :info })
          end

          if failures.any?
            details =
              failures.first(3).map { |f| "#{f[:filename]}: #{f[:message]}" }.join("; ")
            details += "; +#{failures.size - 3} more" if failures.size > 3
            streams << turbo_stream.action(:show_toast, nil) do
              render_to_string(partial: "shared/toast", locals: { message: details, type: :warning })
            end
          end

          render turbo_stream: streams
        end
      end
    end

    # POST /settings/lorebooks/:id/lock
    def lock
      @lorebook.lock!
      redirect_to settings_lorebooks_path, notice: t("lorebooks.locked_success", default: "Lorebook locked.")
    end

    # POST /settings/lorebooks/:id/unlock
    def unlock
      @lorebook.unlock!
      redirect_to settings_lorebooks_path, notice: t("lorebooks.unlocked", default: "Lorebook unlocked.")
    end

    # POST /settings/lorebooks/:id/publish
    def publish
      @lorebook.publish!
      redirect_to settings_lorebooks_path, notice: t("lorebooks.published", default: "Lorebook published.")
    end

    # POST /settings/lorebooks/:id/unpublish
    def unpublish
      @lorebook.unpublish!
      redirect_to settings_lorebooks_path, notice: t("lorebooks.unpublished", default: "Lorebook unpublished.")
    end

    private

    def set_lorebook
      @lorebook = Lorebook.find(params[:id])
    end

    def lorebook_params
      params.require(:lorebook).permit(
        :name, :description, :scan_depth, :token_budget, :recursive_scanning
      )
    end

    def apply_ownership_filter(scope)
      case params[:filter]
      when "global"
        scope.where(user_id: nil)
      when "mine"
        scope.where(user_id: Current.user&.id)
      else
        scope
      end
    end

    def resolve_import_name(files_count:, file:)
      raw = file.respond_to?(:original_filename) ? file.original_filename.to_s : file.to_s
      base = File.basename(raw, ".*").presence || "Imported Lorebook"
      name = params[:name].to_s.strip

      if files_count <= 1
        name.presence || base
      else
        name.present? ? "#{name} #{base}" : base
      end
    end

    def import_error_message(result)
      case result.error_code
      when :no_file
        t("lorebooks.import_no_file")
      when :unsupported_format
        "Unsupported file format. Please upload a JSON file."
      else
        result.error.presence || "Unknown error"
      end
    end

    def render_turbo_stream_error(message)
      render turbo_stream: turbo_stream.action(:show_toast, nil) {
        render_to_string(partial: "shared/toast", locals: { message: message, type: :error })
      }
    end
  end
end
