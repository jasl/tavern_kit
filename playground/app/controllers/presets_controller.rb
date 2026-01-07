# frozen_string_literal: true

# Controller for managing LLM settings presets.
#
# Handles preset CRUD operations and applying presets to space memberships.
#
class PresetsController < ApplicationController
  include ActionView::RecordIdentifier
  include Authorization

  before_action :set_preset, only: %i[update destroy set_default]
  before_action :require_administrator, only: %i[set_default]

  # GET /presets
  # List all presets (system + user's own)
  def index
    @presets = Preset.for_select(user: Current.user)

    respond_to do |format|
      format.html
      format.json { render json: @presets }
    end
  end

  # POST /presets
  # Create a new preset from a membership's current settings
  def create
    membership = find_membership
    return head :not_found unless membership

    @preset = Preset.create_from_membership(
      membership,
      name: preset_params[:name],
      user: Current.user,
      description: preset_params[:description]
    )

    if @preset.persisted?
      # Update membership to use the new preset
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

  # PATCH/PUT /presets/:id
  # Update a preset from a membership's current settings
  def update
    membership = find_membership
    return head :not_found unless membership

    # Only allow updating user's own presets (not system presets)
    if @preset.system_preset?
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, alert: t("presets.cannot_update_system", default: "Cannot update system presets.") }
        format.json { render json: { error: "Cannot update system presets" }, status: :forbidden }
      end
      return
    end

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

  # DELETE /presets/:id
  # Delete a user preset
  def destroy
    # Only allow deleting user's own presets (not system presets)
    if @preset.system_preset?
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, alert: t("presets.cannot_delete_system", default: "Cannot delete system presets.") }
        format.json { render json: { error: "Cannot delete system presets" }, status: :forbidden }
      end
      return
    end

    @preset.destroy

    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, notice: t("presets.deleted", default: "Preset deleted.") }
      format.json { head :no_content }
    end
  end

  # POST /presets/:id/set_default
  # Set a preset as the default
  def set_default
    Preset.set_default!(@preset)

    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, notice: t("presets.set_default", default: "Default preset updated.") }
      format.json { render json: @preset }
    end
  end

  # POST /presets/apply
  # Apply a preset to a membership
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
      # 404 for invalid/unauthorized preset IDs (avoid leaking preset existence).
      format.html { head :not_found }
      # The preset selector uses fetch() and expects JSON on error, even when Accept includes turbo-stream.
      format.turbo_stream { render json: { error: "Preset not found" }, status: :not_found }
      format.json { render json: { error: "Preset not found" }, status: :not_found }
    end
  end

  private

  def set_preset
    @preset = accessible_presets.find(params[:id])
  end

  def preset_params
    params.require(:preset).permit(:name, :description)
  end

  # Presets visible to the current user:
  # - system presets (user_id=nil)
  # - the user's own presets
  def accessible_presets
    Preset.where(user_id: [nil, Current.user.id])
  end

  def find_membership
    # Try various param locations
    membership_id = params[:membership_id] ||
                    params.dig(:preset, :membership_id) ||
                    params.dig(:preset, "membership_id")
    return nil unless membership_id

    membership = SpaceMembership.includes(:space).find_by(id: membership_id)
    return nil unless membership

    space = membership.space
    return nil unless space

    # Ensure the current user can at least access this space (avoid leaking membership existence).
    has_space_access =
      can_administer?(space) ||
        (Current.user && Current.user.spaces.exists?(id: space.id))
    return nil unless has_space_access

    # Only space admins/owners can edit other memberships.
    return membership if can_administer?(space)

    # Non-admins can only apply/capture presets for their own human membership.
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
