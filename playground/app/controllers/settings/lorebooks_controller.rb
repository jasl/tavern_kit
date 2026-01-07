# frozen_string_literal: true

module Settings
  # Controller for managing standalone World Info / Lorebook files.
  #
  # Provides CRUD operations for lorebooks and import/export functionality.
  #
  class LorebooksController < Settings::ApplicationController
    before_action :set_lorebook, only: %i[show edit update destroy duplicate export]

    def index
      @lorebooks = Lorebook.with_entries_count.ordered
    end

    def show
      @entries = @lorebook.entries.ordered
    end

    def new
      @lorebook = Lorebook.new
    end

    def create
      @lorebook = Lorebook.new(lorebook_params)
      @lorebook.user = Current.user

      if @lorebook.save
        redirect_to edit_settings_lorebook_path(@lorebook), notice: t("lorebooks.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @entries = @lorebook.entries.ordered
    end

    def update
      if @lorebook.update(lorebook_params)
        respond_to do |format|
          format.html { redirect_to edit_settings_lorebook_path(@lorebook), notice: t("lorebooks.updated") }
          format.turbo_stream { render turbo_stream: turbo_stream.replace("lorebook_header", partial: "header", locals: { lorebook: @lorebook }) }
        end
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
      new_lorebook = Lorebook.new(
        name: "#{@lorebook.name} (Copy)",
        description: @lorebook.description,
        scan_depth: @lorebook.scan_depth,
        token_budget: @lorebook.token_budget,
        recursive_scanning: @lorebook.recursive_scanning,
        settings: @lorebook.settings.deep_dup
      )
      new_lorebook.user = Current.user

      @lorebook.entries.ordered.each do |entry|
        new_lorebook.entries.build(entry.attributes.except("id", "lorebook_id", "created_at", "updated_at"))
      end

      if new_lorebook.save
        redirect_to edit_settings_lorebook_path(new_lorebook), notice: t("lorebooks.duplicated")
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
        lorebook.user = Current.user

        if lorebook.save
          redirect_to edit_settings_lorebook_path(lorebook), notice: t("lorebooks.imported", count: lorebook.entries.count)
        else
          redirect_to settings_lorebooks_path, alert: t("lorebooks.import_failed", errors: lorebook.errors.full_messages.join(", "))
        end
      rescue JSON::ParserError => e
        redirect_to settings_lorebooks_path, alert: t("lorebooks.import_invalid_json", error: e.message)
      rescue StandardError => e
        redirect_to settings_lorebooks_path, alert: t("lorebooks.import_error", error: e.message)
      end
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
  end
end
