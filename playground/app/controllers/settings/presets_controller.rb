# frozen_string_literal: true

module Settings
  # Controller for managing Presets in the Settings namespace.
  #
  # Provides CRUD operations for presets and utility actions like
  # duplicate and set_default.
  #
  class PresetsController < Settings::ApplicationController
    before_action :set_preset, only: %i[show edit update destroy duplicate set_default lock unlock publish unpublish]

    # GET /settings/presets
    def index
      presets = Preset.by_name
      set_page_and_extract_portion_from presets, per_page: 20
      @default_preset = Preset.get_default
    end

    # GET /settings/presets/:id
    def show
      @default_preset = Preset.get_default
    end

    # GET /settings/presets/new
    def new
      @preset = Preset.new
      # Initialize with default values from schema (reuse ConversationSettings)
      @preset.generation_settings = ConversationSettings::LLM::GenerationSettings.new
      @preset.preset_settings = ConversationSettings::PresetSettings.new
    end

    # GET /settings/presets/:id/edit
    def edit
      # Redirect to show view if locked (read-only)
      if @preset.locked?
        redirect_to settings_preset_path(@preset)
        nil
      end
    end

    # POST /settings/presets
    def create
      @preset = Preset.new(preset_params)
      @preset.visibility = "public" # New presets are public by default

      if @preset.save
        redirect_to settings_presets_path, notice: t("presets.created", default: "Preset created successfully.")
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /settings/presets/:id
    def update
      if @preset.locked?
        redirect_to settings_preset_path(@preset), alert: t("presets.locked", default: "Preset is locked.")
        return
      end

      if @preset.update(preset_params)
        redirect_to settings_presets_path, notice: t("presets.updated", default: "Preset updated successfully.")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /settings/presets/:id
    def destroy
      # Prevent deleting the default preset
      default_preset = Preset.get_default
      if default_preset && @preset.id == default_preset.id
        redirect_to settings_presets_path, alert: t("presets.cannot_delete_default", default: "Cannot delete the default preset.")
        return
      end

      if @preset.locked?
        redirect_to settings_presets_path, alert: t("presets.cannot_delete_locked", default: "Cannot delete locked presets.")
        return
      end

      @preset.destroy!
      redirect_to settings_presets_path, notice: t("presets.deleted", default: "Preset deleted successfully.")
    end

    # POST /settings/presets/:id/duplicate
    def duplicate
      copy = @preset.create_copy(visibility: "public")
      if copy.persisted?
        redirect_to settings_presets_path, notice: t("presets.duplicated", default: "Preset duplicated successfully.")
      else
        redirect_to settings_presets_path, alert: t("presets.duplicate_failed", default: "Failed to duplicate preset: %{errors}", errors: copy.errors.full_messages.join(", "))
      end
    end

    # POST /settings/presets/:id/set_default
    def set_default
      Preset.set_default!(@preset)
      redirect_to settings_presets_path, notice: t("presets.set_default_success", default: "Default preset updated to '#{@preset.name}'.")
    end

    # POST /settings/presets/:id/lock
    def lock
      @preset.lock!
      redirect_to settings_presets_path, notice: t("presets.locked_success", default: "Preset locked.")
    end

    # POST /settings/presets/:id/unlock
    def unlock
      @preset.unlock!
      redirect_to settings_presets_path, notice: t("presets.unlocked", default: "Preset unlocked.")
    end

    # POST /settings/presets/:id/publish
    def publish
      @preset.publish!
      redirect_to settings_presets_path, notice: t("presets.published", default: "Preset published.")
    end

    # POST /settings/presets/:id/unpublish
    def unpublish
      @preset.unpublish!
      redirect_to settings_presets_path, notice: t("presets.unpublished", default: "Preset unpublished.")
    end

    private

    def set_preset
      @preset = Preset.find(params[:id])
    end

    def preset_params
      params.require(:preset).permit(
        :name,
        :description,
        :llm_provider_id,
        generation_settings: %i[
          max_context_tokens max_response_tokens temperature
          top_p top_k repetition_penalty
        ],
        preset_settings: %i[
          main_prompt post_history_instructions group_nudge_prompt
          continue_nudge_prompt new_chat_prompt new_group_chat_prompt
          new_example_chat replace_empty_message continue_prefill
          continue_postfix enhance_definitions auxiliary_prompt
          prefer_char_prompt prefer_char_instructions squash_system_messages
          examples_behavior message_token_overhead authors_note
          authors_note_frequency authors_note_position authors_note_depth
          authors_note_role wi_format scenario_format personality_format
        ]
      )
    end
  end
end
