# frozen_string_literal: true

# Controller for managing playground spaces (solo roleplay).
#
# Playgrounds are single-human spaces with AI characters.
# Conversation timelines live under conversations.
#
# @example Access a playground
#   GET /playgrounds/:id
#
# @example Create a new playground
#   POST /playgrounds
#
class PlaygroundsController < ApplicationController
  include Authorization
  include TrackedSpaceVisit

  before_action :set_playground, only: %i[show edit update destroy]
  before_action :remember_last_space_visited, only: :show
  before_action :ensure_space_writable, only: %i[edit update]
  before_action :ensure_space_admin, only: %i[destroy]

  # GET /playgrounds/:id
  # Shows a playground and its conversations.
  def show
    @current_membership = @playground.space_memberships.active.find_by(user_id: Current.user.id, kind: "human")
    @space_memberships = @playground.space_memberships.includes(:user, :character).order(:position, :id)
    @conversations = @playground.conversations
      .includes(:forked_from_message)
      .order(:created_at, :id)
    @available_characters = Character.accessible_to(Current.user).ready.ordered
  end

  # GET /playgrounds/new
  # Shows form for creating a new playground.
  # Character selection is handled via the character picker Turbo Frame component.
  def new
    @playground = Spaces::Playground.new
  end

  # POST /playgrounds
  # Creates a new playground.
  #
  # When creating a playground, this also creates the owner human SpaceMembership.
  # If characters are selected, creates the full chat setup with conversation and first messages.
  def create
    character_ids = Array(params[:character_ids]).map(&:to_i).reject(&:zero?)
    characters = Character.accessible_to(Current.user).ready.where(id: character_ids)

    if characters.any?
      # Full flow: create playground with characters, conversation, and first messages
      @playground = Spaces::Playground.create_for(playground_params, user: Current.user, characters: characters)
      redirect_to conversation_url(@playground.conversations.first)
    else
      # Simple flow (for form without character selection or API)
      @playground = Spaces::Playground.new(playground_params)
      @playground.owner = Current.user

      Spaces::Playground.transaction do
        @playground.save!
        SpaceMemberships::Grant.call(space: @playground, actors: Current.user, role: "owner")
      end

      redirect_to playground_url(@playground)
    end
  rescue ActiveRecord::RecordInvalid => e
    @playground = e.record
    render :new, status: :unprocessable_entity
  end

  # GET /playgrounds/:id/edit
  # Shows form for editing playground settings.
  # Character selection is handled via the character picker Turbo Frame component.
  def edit
  end

  # PATCH /playgrounds/:id
  # Updates a playground's settings.
  def update
    if @playground.update(playground_params)
      respond_to do |format|
        format.turbo_stream do
          conversation = @playground.conversations.root.first
          if conversation
            # Inline update from group queue - re-render just the queue
            queue_members = TurnScheduler::Queries::QueuePreview.call(conversation: conversation, limit: 10)
            active_run = conversation.conversation_runs.active.includes(:speaker_space_membership).order(
              Arel.sql("CASE status WHEN 'running' THEN 0 WHEN 'queued' THEN 1 ELSE 2 END"),
              created_at: :desc
            ).first
            render turbo_stream: turbo_stream.replace(
              helpers.dom_id(conversation, :group_queue),
              partial: "messages/group_queue",
              locals: { conversation: conversation, space: @playground, queue_members: queue_members, active_run: active_run }
            )
          else
            redirect_to playground_url(@playground), notice: t("playgrounds.updated", default: "Playground updated")
          end
        end
        format.html do
          conversation = @playground.conversations.root.first
          redirect_to conversation ? conversation_url(conversation) : playground_url(@playground),
                      notice: t("playgrounds.updated", default: "Playground updated")
        end
      end
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::StaleObjectError
    message = t("playgrounds.update.conflict", default: "Playground settings have changed. Please reload and try again.")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: render_to_string(
          partial: "shared/toast_turbo_stream",
          locals: { message: message, type: "warning", duration: 5000 }
        ), status: :conflict
      end
      format.html { redirect_to edit_playground_url(@playground), alert: message }
    end
  end

  # DELETE /playgrounds/:id
  # Deletes a playground and all its associated data.
  def destroy
    @playground.update!(status: "deleting")
    # Queue background job to actually delete data
    # SpaceCleanupJob.perform_later(@playground.id)

    redirect_to conversations_url, notice: t("playgrounds.deleted", default: "Playground is being deleted")
  end

  private

  # Set the current playground from params, ensuring user has access.
  def set_playground
    @playground = Current.user.spaces.playgrounds.merge(Space.accessible_to(Current.user)).find_by(id: params[:id])
    # Also set @space for Authorization concern compatibility
    @space = @playground

    unless @playground
      redirect_to root_url, alert: t("playgrounds.not_found", default: "Playground not found")
      return
    end

    return unless @playground.deleting?

    redirect_to conversations_url, alert: t("playgrounds.deleting", default: "This playground is being deleted.")
  end

  # Permitted playground parameters.
  def playground_params
    permitted = params.require(:playground).permit(
      :name,
      :settings_version,
      :reply_order,
      :card_handling_mode,
      :allow_self_responses,
      :relax_message_trim,
      :auto_mode_delay_ms,
      :during_generation_user_input_policy,
      :user_turn_debounce_ms,
      :group_regenerate_mode,
      prompt_settings: [
        preset: %i[
          auxiliary_prompt
          authors_note
          authors_note_allow_wi_scan
          authors_note_depth
          authors_note_frequency
          authors_note_position
          authors_note_role
          continue_nudge_prompt
          continue_postfix
          continue_prefill
          enhance_definitions
          examples_behavior
          group_nudge_prompt
          main_prompt
          message_token_overhead
          new_chat_prompt
          new_example_chat
          new_group_chat_prompt
          personality_format
          post_history_instructions
          prefer_char_instructions
          prefer_char_prompt
          scenario_format
          squash_system_messages
          wi_format
        ],
      ]
    )

    attrs = permitted.to_h
    preset = attrs.dig("prompt_settings", "preset")
    if preset.is_a?(Hash)
      %w[authors_note_depth authors_note_frequency message_token_overhead].each do |key|
        next unless preset.key?(key)

        preset[key] = coerce_integer(preset[key])
      end

      # Coerce boolean
      if preset.key?("authors_note_allow_wi_scan")
        preset["authors_note_allow_wi_scan"] = coerce_boolean(preset["authors_note_allow_wi_scan"])
      end
    end

    attrs
  end

  def coerce_boolean(value)
    return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)

    %w[true 1 yes on].include?(value.to_s.downcase)
  end

  def coerce_integer(value)
    return value if value.nil? || value.is_a?(Integer)

    v = value.to_s.strip
    return nil if v.empty?

    Integer(v)
  rescue ArgumentError, TypeError
    value
  end
end
