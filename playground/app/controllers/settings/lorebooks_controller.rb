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
      @entries = @lorebook.entries.ordered
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

      @entries = @lorebook.entries.ordered
    end

    def update
      if @lorebook.locked?
        redirect_to settings_lorebook_path(@lorebook), alert: t("lorebooks.locked", default: "Lorebook is locked.")
        return
      end

      if @lorebook.update(lorebook_params)
        redirect_to settings_lorebooks_path, notice: t("lorebooks.updated")
      else
        @entries = @lorebook.entries.ordered
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
      unless params[:file].present?
        redirect_to settings_lorebooks_path, alert: t("lorebooks.import_no_file")
        return
      end

      begin
        json_data = JSON.parse(params[:file].read)
        lorebook = Lorebook.import_from_json(json_data, name_override: params[:name].presence)
        lorebook.visibility = "public" # Imported lorebooks are public by default

        if lorebook.save
          redirect_to settings_lorebooks_path, notice: t("lorebooks.imported", count: lorebook.entries.count)
        else
          redirect_to settings_lorebooks_path, alert: t("lorebooks.import_failed", errors: lorebook.errors.full_messages.join(", "))
        end
      rescue JSON::ParserError => e
        redirect_to settings_lorebooks_path, alert: t("lorebooks.import_invalid_json", error: e.message)
      rescue StandardError => e
        redirect_to settings_lorebooks_path, alert: t("lorebooks.import_error", error: e.message)
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
  end
end
