# frozen_string_literal: true

# Controller for managing space memberships.
#
# Handles adding/removing users and characters from playgrounds,
# and updating membership settings like persona and Auto settings.
#
# @example Add a character to a playground
#   POST /playgrounds/:playground_id/memberships
#
# @example Edit membership settings
#   GET /playgrounds/:playground_id/memberships/:id/edit
#
# @example Update membership settings
#   PATCH /playgrounds/:playground_id/memberships/:id
#
class Playgrounds::MembershipsController < Playgrounds::ApplicationController
  include Authorization

  before_action :set_membership, only: %i[edit update destroy]
  before_action :ensure_space_admin, only: %i[new create destroy]
  before_action :ensure_space_writable, only: %i[new create edit update destroy]
  before_action :ensure_can_edit_membership, only: %i[edit update]

  # GET /playgrounds/:playground_id/memberships/new
  # Shows form for adding a new member to the playground.
  # Uses the character picker component which loads characters via Turbo Frame.
  def new
  end

  # POST /playgrounds/:playground_id/memberships
  # Adds one or more characters via character_ids[] (multi-select).
  def create
    character_ids = extract_character_ids
    if character_ids.empty?
      redirect_to new_playground_membership_url(@playground),
                  alert: t("space_memberships.character_required", default: "Please select at least one character")
      return
    end

    characters = Character.accessible_to(Current.user).ready.where(id: character_ids)
    if characters.empty?
      redirect_to new_playground_membership_url(@playground),
                  alert: t("space_memberships.character_required", default: "Please select at least one character")
      return
    end

    # Filter out characters that are already members (race condition protection)
    existing_character_ids = @playground.space_memberships.active.where.not(character_id: nil).pluck(:character_id)
    new_characters = characters.reject { |c| existing_character_ids.include?(c.id) }

    if new_characters.empty?
      redirect_to new_playground_membership_url(@playground),
                  alert: t("space_memberships.already_members", default: "Selected characters are already members of this space")
      return
    end

    # Grant membership to all new characters
    new_characters.each do |character|
      SpaceMemberships::Grant.execute(space: @playground, actors: character)
    end

    # Redirect to conversation if exists, otherwise playground
    conversation = @playground.conversations.root.first
    notice_message = if new_characters.size == 1
                       t("space_memberships.member_added", default: "Member added")
    else
                       t("space_memberships.members_added",
                         default: "%{count} members added",
                         count: new_characters.size)
    end
    redirect_to conversation ? conversation_url(conversation) : playground_url(@playground),
                notice: notice_message
  end

  # GET /playgrounds/:playground_id/memberships/:id/edit
  def edit
    # Get available characters (not already in the playground as standalone AI)
    existing_ai_character_ids = @playground.space_memberships.active.kind_character.pluck(:character_id)
    # Include the current character if already set (so user can keep it)
    existing_ai_character_ids -= [@membership.character_id] if @membership.character_id
    @available_characters = Character.accessible_to(Current.user).ready.where.not(id: existing_ai_character_ids).order(:name)
  end

  # PATCH /playgrounds/:playground_id/memberships/:id
  #
  # Supports two formats:
  # 1. Traditional form submission (HTML)
  # 2. JSON requests:
  #    a. Simple membership update: { "space_membership": { "auto": "auto" } }
  #    b. Settings patch update: { "settings_version": 0, "settings": { ... } }
  def update
    return handle_json_update if json_request?

    handle_form_update
  end

  # DELETE /playgrounds/:playground_id/memberships/:id
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

    # If payload has "space_membership" key, it's a simple membership update (e.g., auto toggle)
    if payload.key?("space_membership")
      handle_json_membership_update(payload["space_membership"])
    else
      # Otherwise it's a settings patch update
      handle_json_patch_update(payload)
    end
  end

  def handle_json_patch_update(payload)
    result = SpaceMemberships::SettingsPatch.new(@membership).call(payload)
    render json: result.body, status: result.status
  end

  def handle_json_membership_update(membership_payload)
    unless membership_payload.is_a?(Hash)
      return render json: { ok: false, errors: ["space_membership must be an object"] }, status: :bad_request
    end

    attrs = permitted_membership_attributes(membership_payload)
    was_auto_none = @membership.auto_none?
    new_auto = attrs[:auto]

    if @membership.update(attrs)
      # When enabling Auto mode, kick any queued run so the playground responds immediately.
      # This also disables Auto-without-human if active (they are mutually exclusive).
      auto_without_human_disabled = kick_queued_run_if_needed(was_auto_none, new_auto)

      conversation = @playground.conversations.root.first

      render json: {
        ok: true,
        success: true,
        saved_at: Time.current.iso8601,
        auto_remaining_steps: @membership.auto_remaining_steps,
        auto_without_human_disabled: auto_without_human_disabled,
        auto_without_human_remaining_rounds: conversation&.auto_without_human_remaining_rounds || 0,
        space_membership: {
          id: @membership.id,
          status: @membership.status,
          participation: @membership.participation,
          persona: @membership.persona,
          auto: @membership.auto,
          auto_remaining_steps: @membership.auto_remaining_steps,
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
    was_auto_none = @membership.auto_none?
    new_auto = update_params[:auto]

    if @membership.update(update_params)
      # When enabling Auto mode, kick any queued run so the playground responds immediately.
      kick_queued_run_if_needed(was_auto_none, new_auto)

      respond_to do |format|
        format.turbo_stream do
          conversation = @playground.conversations.first
          render turbo_stream: turbo_stream.replace(
            "left_sidebar_member_#{@membership.id}",
            partial: "conversations/left_sidebar_member",
            locals: { membership: @membership, space: @playground, conversation: conversation }
          )
        end
        format.html do
          redirect_to safe_return_to || playground_url(@playground),
                      notice: t("space_memberships.updated", default: "Membership updated")
        end
      end
    else
      @available_characters = Character.accessible_to(Current.user).ready.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def permitted_membership_attributes(payload)
    permitted = %i[participation persona auto talkativeness_factor]
    permitted << :position if can_administer?(@space)
    permitted << :character_id if @membership&.kind_human?
    permitted << :auto_remaining_steps if @membership&.kind_human?

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

  def set_membership
    @membership = @playground.space_memberships.find(params[:id])
  end

  # Extract character IDs from params (multi-select: character_ids[]).
  def extract_character_ids
    Array(params[:character_ids]).map(&:to_i).reject(&:zero?)
  end

  def update_params
    permitted = %i[participation position persona auto talkativeness_factor]
    # Allow setting character_id for human memberships (persona character)
    permitted << :character_id if @membership&.kind_human?
    permitted << :auto_remaining_steps if @membership&.kind_human?
    params.require(:space_membership).permit(*permitted)
  end

  def ensure_can_edit_membership
    return if can_administer?(@space)

    # Non-admins can only edit their own user membership (not character memberships).
    head :forbidden unless @membership.user_id == Current.user.id
  end

  # Only allow same-origin, relative return paths to avoid open redirects.
  def safe_return_to
    rt = params[:return_to].to_s
    return nil if rt.blank?
    return nil unless rt.start_with?("/")

    rt
  end

  # Trigger generation when auto mode is enabled.
  #
  # When a user enables Auto mode, the scheduler handles the turn flow.
  # If there's already a queued run, kick it. Otherwise, start a new round
  # via the unified scheduler.
  #
  # Also ensures Auto-without-human and Auto are mutually exclusive - disables
  # Auto-without-human when Auto is enabled.
  #
  # @param was_auto_none [Boolean] whether auto was disabled before
  # @param new_auto [String, nil] the new auto value
  # @return [Boolean] true if Auto-without-human was disabled, false otherwise
  def kick_queued_run_if_needed(was_auto_none, new_auto)
    return false unless was_auto_none && new_auto == "auto"
    return false unless @membership.auto_capable?
    return false unless @playground.active?

    conversation = @playground.conversations.root.first
    return false unless conversation

    auto_without_human_disabled = false

    # Auto-without-human and Auto are mutually exclusive - disable auto-without-human if active
    if conversation.auto_without_human_enabled?
      conversation.stop_auto_without_human!
      auto_without_human_disabled = true
      Rails.logger.info "[MembershipsController] Disabled Auto-without-human for conversation #{conversation.id} (Auto enabled)"
    end

    # Stop any existing runs then start a new round for the Auto speaker to speak
    TurnScheduler.stop!(conversation)
    TurnScheduler.start_round!(conversation)

    auto_without_human_disabled
  end
end
