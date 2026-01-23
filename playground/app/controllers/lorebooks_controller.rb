# frozen_string_literal: true

# User-facing lorebook controller for managing World Info files.
#
# Provides:
# - List with filtering (ownership, name search) and pagination
# - View lorebook details and entries
# - Create new lorebooks
# - Import lorebooks from JSON
# - Edit/update user-owned lorebooks
# - Delete user-owned lorebooks
# - Duplicate any accessible lorebook
# - Export lorebook as JSON
#
# Global lorebooks (user_id = nil) are read-only but can be duplicated.
# User-owned lorebooks have full CRUD access.
#
class LorebooksController < ApplicationController
  before_action :set_lorebook, only: %i[show edit update destroy duplicate export]
  before_action :require_editable, only: %i[edit update destroy]

  # GET /lorebooks
  # List all accessible lorebooks with optional filtering.
  def index
    lorebooks = Lorebook.accessible_to(Current.user).includes(:user)

    # Ownership filter
    lorebooks = apply_ownership_filter(lorebooks)

    # Name search
    lorebooks = lorebooks.where("LOWER(name) LIKE ?", "%#{params[:q].downcase}%") if params[:q].present?

    # Ordering
    lorebooks = lorebooks.ordered

    set_page_and_extract_portion_from lorebooks, per_page: 20
  end

  # GET /lorebooks/:id
  # Show lorebook details and entries.
  def show
    @entries = @lorebook.entries.ordered.to_a
  end

  # GET /lorebooks/new
  # Show create form.
  def new
    @lorebook = Lorebook.new
  end

  # POST /lorebooks
  # Create a new lorebook.
  def create
    @lorebook = Lorebook.new(lorebook_params)
    @lorebook.user = Current.user
    @lorebook.visibility = "private"

    if @lorebook.save
      redirect_to edit_lorebook_path(@lorebook), notice: t("lorebooks.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # GET /lorebooks/:id/edit
  # Show edit form for user-owned lorebook.
  def edit
    @entries = @lorebook.entries.ordered.to_a
  end

  # PATCH/PUT /lorebooks/:id
  # Update a user-owned lorebook.
  def update
    updates = lorebook_params.to_h
    updates[:file_sha256] = nil if @lorebook.file_sha256.present?

    if @lorebook.update(updates)
      redirect_to lorebooks_path, notice: t("lorebooks.updated")
    else
      @entries = @lorebook.entries.ordered.to_a
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /lorebooks/:id
  # Delete a user-owned lorebook.
  def destroy
    @lorebook.destroy!
    redirect_to lorebooks_path, notice: t("lorebooks.deleted")
  end

  # POST /lorebooks/:id/duplicate
  # Create a copy of any accessible lorebook.
  def duplicate
    copy = @lorebook.create_copy(user: Current.user, visibility: "private")
    if copy.persisted?
      redirect_to lorebooks_path, notice: t("lorebooks.duplicated")
    else
      redirect_to lorebooks_path, alert: t("lorebooks.duplicate_failed")
    end
  end

  # GET /lorebooks/:id/export
  # Export lorebook as JSON file.
  def export
    json_data = @lorebook.export_to_json
    filename = "#{@lorebook.name.parameterize.presence || 'lorebook'}.json"

    send_data JSON.pretty_generate(json_data),
              filename: filename,
              type: "application/json",
              disposition: "attachment"
  end

  # POST /lorebooks/import
  # Import lorebook from JSON file.
  def import
    files = Array(params[:file]).compact_blank

    if files.empty?
      message = t("lorebooks.import_no_file")
      respond_to do |format|
        format.html { redirect_to lorebooks_path, alert: message }
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
        owner: Current.user,
        visibility: "private",
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
        format.html { redirect_to lorebooks_path, alert: message }
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
        redirect_to lorebooks_path, flash: flash
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

  private

  def set_lorebook
    @lorebook = Lorebook.accessible_to(Current.user).find(params[:id])
  end

  def require_editable
    return if editable?(@lorebook)

    redirect_to lorebook_path(@lorebook),
                alert: t("lorebooks.not_editable", default: "You cannot edit this lorebook.")
  end

  def editable?(lorebook)
    lorebook.user_id == Current.user&.id && !lorebook.locked?
  end

  def global?(lorebook)
    lorebook.user_id.nil?
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

  def lorebook_params
    params.require(:lorebook).permit(
      :name, :description, :scan_depth, :token_budget, :recursive_scanning
    )
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
