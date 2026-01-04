# frozen_string_literal: true

# Controller for managing space memberships.
#
# Handles adding/removing users and characters from playgrounds,
# and updating membership settings like persona, copilot settings.
#
# @example Add a character to a playground
#   POST /playgrounds/:playground_id/space_memberships
#
# @example Edit membership settings
#   GET /playgrounds/:playground_id/space_memberships/:id/edit
#
# @example Update membership settings
#   PATCH /playgrounds/:playground_id/space_memberships/:id
#
class SpaceMembershipsController < ApplicationController
  include Authorization

  before_action :set_playground
  before_action :set_membership, only: %i[edit update destroy]
  before_action :ensure_space_admin, only: %i[new create destroy]
  before_action :ensure_space_writable, only: %i[new create edit update destroy]
  before_action :ensure_can_edit_membership, only: %i[edit update]

  # GET /playgrounds/:playground_id/space_memberships/new
  # Shows form for adding a new member to the playground.
  def new
    # Get available characters (not already in the playground as standalone AI)
    existing_ai_character_ids = @playground.space_memberships.active.kind_character.pluck(:character_id)
    @available_characters = Character.ready.where.not(id: existing_ai_character_ids).order(:name)
  end

  # POST /playgrounds/:playground_id/space_memberships
  def create
    character = Character.ready.find_by(id: create_params[:character_id])
    unless character
      redirect_to new_playground_space_membership_url(@playground), alert: t("space_memberships.character_required", default: "Character is required")
      return
    end

    @playground.space_memberships.grant_to(character)

    # Redirect to conversation if exists, otherwise playground
    conversation = @playground.conversations.root.first
    redirect_to conversation ? conversation_url(conversation) : playground_url(@playground),
                notice: t("space_memberships.member_added", default: "Member added")
  end

  # GET /playgrounds/:playground_id/space_memberships/:id/edit
  def edit
    # Get available characters (not already in the playground as standalone AI)
    existing_ai_character_ids = @playground.space_memberships.active.kind_character.pluck(:character_id)
    # Include the current character if already set (so user can keep it)
    existing_ai_character_ids -= [@membership.character_id] if @membership.character_id
    @available_characters = Character.ready.where.not(id: existing_ai_character_ids).order(:name)
  end

  # PATCH /playgrounds/:playground_id/space_memberships/:id
  #
  # Supports two formats:
  # 1. Traditional form submission (HTML)
  # 2. JSON requests:
  #    a. Simple membership update: { "space_membership": { "copilot_mode": "full" } }
  #    b. Settings patch update: { "settings_version": 0, "settings": { ... } }
  def update
    return handle_json_update if json_request?

    handle_form_update
  end

  # DELETE /playgrounds/:playground_id/space_memberships/:id
  def destroy
    if @membership.kind_human?
      head :forbidden
      return
    end

    @membership.remove!(by_user: Current.user, reason: "Removed by user")

    # Redirect to conversation if exists, otherwise playground
    conversation = @playground.conversations.root.first
    redirect_to conversation ? conversation_url(conversation) : playground_url(@playground),
                notice: t("space_memberships.removed", default: "Member removed")
  end

  private

  def json_request?
    request.content_type&.include?("application/json")
  end

  def handle_json_update
    payload = parse_json_payload
    return render_parse_error unless payload.is_a?(Hash)

    # If payload has "space_membership" key, it's a simple membership update (e.g., copilot toggle)
    if payload.key?("space_membership")
      handle_json_membership_update(payload["space_membership"])
    else
      # Otherwise it's a settings patch update
      handle_json_patch_update(payload)
    end
  end

  def handle_json_patch_update(payload)
    result = SpaceMembership::SettingsPatch.new(@membership).call(payload)
    render json: result.body, status: result.status
  end

  def handle_json_membership_update(membership_payload)
    unless membership_payload.is_a?(Hash)
      return render json: { ok: false, errors: ["space_membership must be an object"] }, status: :bad_request
    end

    attrs = permitted_membership_attributes(membership_payload)
    was_copilot_none = @membership.copilot_none?
    new_copilot_mode = attrs[:copilot_mode]

    if @membership.update(attrs)
      # When enabling full copilot mode, kick any queued run so the playground responds immediately.
      kick_queued_run_if_needed(was_copilot_none, new_copilot_mode)

      render json: {
        ok: true,
        success: true,
        saved_at: Time.current.iso8601,
        space_membership: {
          id: @membership.id,
          status: @membership.status,
          participation: @membership.participation,
          persona: @membership.persona,
          copilot_mode: @membership.copilot_mode,
          character_id: @membership.character_id,
          position: @membership.position,
          llm_provider_id: @membership.llm_provider_id,
          provider_identification: @membership.provider_identification,
          settings_version: @membership.settings_version,
          settings: @membership.settings,
        },
      }
    else
      render json: { ok: false, success: false, errors: @membership.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def handle_form_update
    was_copilot_none = @membership.copilot_none?
    new_copilot_mode = update_params[:copilot_mode]

    if @membership.update(update_params)
      # When enabling full copilot mode, kick any queued run so the playground responds immediately.
      kick_queued_run_if_needed(was_copilot_none, new_copilot_mode)

      # Redirect to conversation page for full form updates, playground page for simple updates
      if params[:space_membership].keys.any? { |k| %w[persona copilot_mode character_id copilot_remaining_steps].include?(k.to_s) }
        conversation = @playground.conversations.first
        redirect_to conversation ? conversation_url(conversation) : playground_url(@playground),
                    notice: t("space_memberships.updated", default: "Membership updated")
      else
        redirect_to playground_url(@playground)
      end
    else
      @available_characters = Character.ready.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def permitted_membership_attributes(payload)
    permitted = %i[participation persona copilot_mode]
    permitted << :position if can_administer?(@space)
    permitted << :character_id if @membership&.kind_human?
    permitted << :copilot_remaining_steps if @membership&.kind_human?

    ActionController::Parameters.new(payload).permit(*permitted)
  end

  def parse_json_payload
    JSON.parse(request.body.read)
  rescue JSON::ParserError
    nil
  end

  def render_parse_error
    render json: { ok: false, errors: ["Invalid JSON payload"] }, status: :bad_request
  end

  def set_playground
    @playground = Current.user.spaces.playgrounds.find_by(id: params[:playground_id])
    # Also set @space for Authorization concern compatibility
    @space = @playground
    return if @playground

    redirect_to root_url, alert: t("playgrounds.not_found", default: "Playground not found")
  end

  def set_membership
    @membership = @playground.space_memberships.find(params[:id])
  end

  def create_params
    params.fetch(:space_membership, {}).permit(:character_id)
  end

  def update_params
    permitted = %i[participation position persona copilot_mode]
    # Allow setting character_id for human memberships (persona character)
    permitted << :character_id if @membership&.kind_human?
    permitted << :copilot_remaining_steps if @membership&.kind_human?
    params.require(:space_membership).permit(*permitted)
  end

  def ensure_can_edit_membership
    return if can_administer?(@space)

    # Non-admins can only edit their own user membership (not character memberships).
    head :forbidden unless @membership.user_id == Current.user.id
  end

  # Trigger generation when copilot mode is enabled.
  #
  # When a user enables full copilot mode:
  # - If there's an existing queued run, kick it to start immediately
  # - If there's no queued run, plan a new copilot start run
  #
  # @param was_copilot_none [Boolean] whether copilot was disabled before
  # @param new_copilot_mode [String, nil] the new copilot mode
  def kick_queued_run_if_needed(was_copilot_none, new_copilot_mode)
    return unless was_copilot_none && new_copilot_mode == "full"
    return unless @membership.character_id.present?
    return unless @playground.active?

    conversation = @playground.conversations.root.first
    return unless conversation

    queued = conversation.queued_run
    if queued
      Conversation::RunPlanner.kick!(queued)
    else
      # No queued run - plan a new copilot start run
      Conversation::RunPlanner.plan_copilot_start!(conversation: conversation, copilot_membership: @membership)
    end
  end
end
