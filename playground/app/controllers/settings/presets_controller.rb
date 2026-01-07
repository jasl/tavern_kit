# frozen_string_literal: true

module Settings
  # Controller for managing Presets in the Settings namespace.
  #
  # Provides CRUD operations for presets and utility actions like
  # duplicate and set_default.
  #
  class PresetsController < Settings::ApplicationController
    before_action :set_preset, only: %i[show edit update destroy duplicate set_default]

    # GET /settings/presets
    def index
      @presets = Preset.by_name
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
    end

    # POST /settings/presets
    def create
      @preset = Preset.new(preset_params)

      if @preset.save
        redirect_to settings_presets_path, notice: t("presets.created", default: "Preset created successfully.")
      else
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /settings/presets/:id
    def update
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
      new_preset = Preset.new(
        name: "#{@preset.name} (Copy)",
        description: @preset.description,
        llm_provider_id: @preset.llm_provider_id,
        generation_settings: @preset.generation_settings_as_hash,
        preset_settings: @preset.preset_settings_as_hash
      )

      if new_preset.save
        redirect_to settings_presets_path, notice: t("presets.duplicated", default: "Preset duplicated successfully.")
      else
        redirect_to settings_presets_path, alert: t("presets.duplicate_failed", default: "Failed to duplicate preset: #{new_preset.errors.full_messages.join(', ')}")
      end
    end

    # POST /settings/presets/:id/set_default
    def set_default
      Preset.set_default!(@preset)
      redirect_to settings_presets_path, notice: t("presets.set_default_success", default: "Default preset updated to '#{@preset.name}'.")
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
