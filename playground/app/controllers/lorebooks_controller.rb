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
    lorebooks = Lorebook.accessible_to(Current.user)

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
    @entries = @lorebook.entries.ordered
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
    @entries = @lorebook.entries.ordered
  end

  # PATCH/PUT /lorebooks/:id
  # Update a user-owned lorebook.
  def update
    if @lorebook.update(lorebook_params)
      redirect_to lorebooks_path, notice: t("lorebooks.updated")
    else
      @entries = @lorebook.entries.ordered
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
    unless params[:file].present?
      redirect_to lorebooks_path, alert: t("lorebooks.import_no_file")
      return
    end

    begin
      json_data = JSON.parse(params[:file].read)
      lorebook = Lorebook.import_from_json(json_data, name_override: params[:name].presence)
      lorebook.user = Current.user
      lorebook.visibility = "private"

      if lorebook.save
        redirect_to lorebooks_path, notice: t("lorebooks.imported", count: lorebook.entries.count)
      else
        redirect_to lorebooks_path, alert: t("lorebooks.import_failed", errors: lorebook.errors.full_messages.join(", "))
      end
    rescue JSON::ParserError => e
      redirect_to lorebooks_path, alert: t("lorebooks.import_invalid_json", error: e.message)
    rescue StandardError => e
      redirect_to lorebooks_path, alert: t("lorebooks.import_error", error: e.message)
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
end
