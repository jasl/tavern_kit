# frozen_string_literal: true

# User-facing preset controller for managing LLM settings presets.
#
# Provides two modes of operation:
#
# 1. Management UI (user-facing):
#    - List with filtering (ownership) and pagination
#    - View preset details
#    - Create new presets (standalone form or from membership snapshot)
#    - Edit/update user-owned presets
#    - Delete user-owned presets
#    - Duplicate any accessible preset
#
# 2. API-style operations (for conversation UI integration):
#    - Apply preset to membership
#    - Create/update preset from membership snapshot
#
# Global presets (user_id = nil) are read-only but can be duplicated.
# User-owned presets have full CRUD access.
#
class PresetsController < ApplicationController
  include ActionView::RecordIdentifier
  include Authorization

  before_action :set_preset, only: %i[show edit update destroy duplicate set_default export]
  before_action :require_editable, only: %i[edit update destroy]
  before_action :require_administrator, only: %i[set_default]

  # GET /presets
  # List all accessible presets with optional filtering.
  def index
    presets = Preset.accessible_to(Current.user).includes(:llm_provider)

    # Ownership filter
    presets = apply_ownership_filter(presets)

    # Ordering
    presets = presets.by_name

    respond_to do |format|
      format.html do
        set_page_and_extract_portion_from presets, per_page: 20
        @default_preset = Preset.get_default
      end
      format.json { render json: presets }
    end
  end

  # GET /presets/:id
  # Show preset details.
  def show
    @default_preset = Preset.get_default
  end

  # GET /presets/new
  # Show create form.
  def new
    @preset = Preset.new
    @preset.generation_settings = ConversationSettings::LLM::GenerationSettings.new
    @preset.preset_settings = ConversationSettings::PresetSettings.new
    @llm_providers = LLMProvider.enabled.order(:name)
  end

  # POST /presets
  # Create a new preset (standalone or from membership snapshot).
  def create
    # Check if this is a membership snapshot request (API-style)
    if membership_id_provided?
      membership = find_membership
      return head :not_found unless membership

      create_from_membership(membership)
    else
      create_standalone
    end
  end

  # GET /presets/:id/edit
  # Show edit form for user-owned preset.
  def edit
    @llm_providers = LLMProvider.enabled.order(:name)
  end

  # PATCH/PUT /presets/:id
  # Update a user-owned preset (standalone or from membership snapshot).
  def update
    # Check if this is a membership snapshot request (API-style)
    if membership_id_provided?
      membership = find_membership
      return head :not_found unless membership

      update_from_membership(membership)
    else
      update_standalone
    end
  end

  # DELETE /presets/:id
  # Delete a user-owned preset.
  def destroy
    # Prevent deleting the default preset
    default_preset = Preset.get_default
    if default_preset && @preset.id == default_preset.id
      redirect_to presets_path, alert: t("presets.cannot_delete_default", default: "Cannot delete the default preset.")
      return
    end

    @preset.destroy!

    respond_to do |format|
      format.html { redirect_to presets_path, notice: t("presets.deleted", default: "Preset deleted.") }
      format.json { head :no_content }
    end
  end

  # POST /presets/:id/duplicate
  # Create a copy of any accessible preset.
  def duplicate
    copy = @preset.create_copy(user: Current.user, visibility: "private")
    if copy.persisted?
      redirect_to presets_path, notice: t("presets.duplicated", default: "Preset duplicated successfully.")
    else
      redirect_to presets_path, alert: t("presets.duplicate_failed", default: "Failed to duplicate preset: %{errors}", errors: copy.errors.full_messages.join(", "))
    end
  end

  # POST /presets/:id/set_default
  # Set a preset as the default (admin only).
  def set_default
    Preset.set_default!(@preset)

    respond_to do |format|
      format.html { redirect_to presets_path, notice: t("presets.set_default", default: "Default preset updated.") }
      format.json { render json: @preset }
    end
  end

  # GET /presets/:id/export
  # Export a preset to JSON file.
  def export
    export_hash = Presets::Exporter.new.to_hash(@preset)
    filename = "#{@preset.name.parameterize}-preset.json"

    send_data JSON.pretty_generate(export_hash),
              filename: filename,
              type: "application/json",
              disposition: "attachment"
  end

  # POST /presets/import
  # Import a preset from uploaded JSON file.
  def import
    file = params[:file]

    if file.blank?
      redirect_to presets_path, alert: t("presets.import_no_file", default: "Please select a file to import.")
      return
    end

    result = Presets::Importer::Detector.new.call(file, user: Current.user)

    if result.success?
      redirect_to presets_path, notice: t("presets.imported", default: "Preset '%{name}' imported successfully.", name: result.preset.name)
    else
      redirect_to presets_path, alert: t("presets.import_failed", default: "Import failed: %{error}", error: result.error)
    end
  end

  # POST /presets/apply
  # Apply a preset to a membership (API-style).
  def apply
    membership = find_membership
    return head :not_found unless membership

    preset = accessible_presets.find(params[:preset_id])
    preset.apply_to(membership)

    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, notice: t("presets.applied", default: "Preset applied.") }
      format.json { render json: { success: true, preset: preset, membership_id: membership.id } }
      format.turbo_stream { render_turbo_stream_refresh(membership) }
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { head :not_found }
      format.turbo_stream do
        render_toast_turbo_stream(message: "Preset not found", type: "error", duration: 5000, status: :not_found)
      end
      format.json { render json: { error: "Preset not found" }, status: :not_found }
    end
  end

  private

  def set_preset
    @preset = accessible_presets.find(params[:id])
  end

  def require_editable
    return if editable?(@preset)

    respond_to do |format|
      format.html { redirect_to preset_path(@preset), alert: t("presets.not_editable", default: "You cannot edit this preset.") }
      format.json { render json: { error: "Cannot edit this preset" }, status: :forbidden }
    end
  end

  def editable?(preset)
    preset.user_id == Current.user&.id && !preset.locked?
  end

  def global?(preset)
    preset.user_id.nil?
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
        continue_nudge_prompt impersonation_prompt new_chat_prompt
        new_group_chat_prompt new_example_chat replace_empty_message
        continue_prefill continue_postfix enhance_definitions auxiliary_prompt
        prefer_char_prompt prefer_char_instructions squash_system_messages
        examples_behavior message_token_overhead authors_note
        authors_note_frequency authors_note_position authors_note_depth
        authors_note_role authors_note_allow_wi_scan wi_format scenario_format
        personality_format
      ]
    )
  end

  def accessible_presets
    Preset.accessible_to(Current.user)
  end

  # Standalone preset creation (from form)
  def create_standalone
    @preset = Preset.new(preset_params)
    @preset.user = Current.user
    @preset.visibility = "private"

    if @preset.save
      redirect_to presets_path, notice: t("presets.created", default: "Preset created successfully.")
    else
      @llm_providers = LLMProvider.enabled.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  # Create preset from membership snapshot (API-style)
  def create_from_membership(membership)
    @preset = Preset.create_from_membership(
      membership,
      name: preset_params[:name],
      user: Current.user,
      description: preset_params[:description],
      visibility: "private"
    )

    if @preset.persisted?
      membership.update!(preset_id: @preset.id)

      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, notice: t("presets.created", default: "Preset created.") }
        format.json { render json: @preset, status: :created }
        format.turbo_stream { render_turbo_stream_refresh(membership) }
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, alert: @preset.errors.full_messages.join(", ") }
        format.json { render json: { errors: @preset.errors }, status: :unprocessable_entity }
      end
    end
  end

  # Standalone preset update (from form)
  def update_standalone
    if @preset.update(preset_params)
      redirect_to presets_path, notice: t("presets.updated", default: "Preset updated successfully.")
    else
      @llm_providers = LLMProvider.enabled.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  # Update preset from membership snapshot (API-style)
  def update_from_membership(membership)
    if @preset.update_from_membership(membership)
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, notice: t("presets.updated", default: "Preset updated.") }
        format.json { render json: @preset }
        format.turbo_stream { render_turbo_stream_refresh(membership) }
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, alert: @preset.errors.full_messages.join(", ") }
        format.json { render json: { errors: @preset.errors }, status: :unprocessable_entity }
      end
    end
  end

  def membership_id_provided?
    params[:membership_id].present? || params.dig(:preset, :membership_id).present?
  end

  def find_membership
    membership_id = params[:membership_id] || params.dig(:preset, :membership_id)
    return nil unless membership_id

    membership = SpaceMembership.includes(:space).find_by(id: membership_id)
    return nil unless membership

    space = membership.space
    return nil unless space

    has_space_access =
      can_administer?(space) ||
        (Current.user && Current.user.spaces.merge(Space.accessible_to(Current.user)).exists?(id: space.id))
    return nil unless has_space_access

    return membership if can_administer?(space)

    membership.user_id == Current.user&.id ? membership : nil
  end

  def render_turbo_stream_refresh(membership)
    conversation = membership.space.conversations.root.first
    render turbo_stream: turbo_stream.replace(
      dom_id(conversation, :right_sidebar),
      partial: "conversations/right_sidebar",
      locals: { conversation: conversation, space: membership.space, membership: membership }
    )
  end
end
