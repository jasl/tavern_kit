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
    lorebook_ids = Array(params[:lorebook_ids]).map(&:to_i).reject(&:zero?)
    characters = Character.accessible_to(Current.user).ready.where(id: character_ids)

    if characters.empty?
      @playground = Spaces::Playground.new(playground_params)
      @playground.errors.add(:base, t("playgrounds.character_required", default: "Please select at least one AI character"))
      render :new, status: :unprocessable_entity
      return
    end

    owner_membership = owner_membership_attributes
    validate_owner_membership!(owner_membership)

    if owner_membership[:persona_character_id].present? && character_ids.include?(owner_membership[:persona_character_id])
      invalid = Spaces::Playground.new(playground_params)
      invalid.errors.add(:base, "Persona character cannot also be selected as an AI participant")
      raise ActiveRecord::RecordInvalid, invalid
    end

    @playground =
      Spaces::Playground.create_for(
        playground_params,
        user: Current.user,
        characters: characters,
        owner_membership: owner_membership,
        lorebook_ids: lorebook_ids
      )

    redirect_to conversation_url(@playground.conversations.root.first)
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
    previous_i18n = @playground.prompt_settings&.i18n
    previous_translation_needed = previous_i18n&.translation_needed? == true

    attrs = playground_params
    attrs["prompt_settings"] = merge_prompt_settings(@playground.prompt_settings, attrs["prompt_settings"]) if attrs.key?("prompt_settings")

    if @playground.update(attrs)
      current_i18n = @playground.prompt_settings&.i18n
      current_translation_needed = current_i18n&.translation_needed? == true

      if previous_translation_needed && !current_translation_needed
        Translation::RunCanceler.cancel_active_for_space!(space: @playground, reason: "disabled")
      end

      respond_to do |format|
        format.turbo_stream do
          conversation = @playground.conversations.root.first
          if conversation
            # Broadcast a queue_updated payload so open conversation tabs can update
            # scheduling UI state (including during_generation policy) without reload.
            TurnScheduler::Broadcasts.queue_updated(conversation)

            render turbo_stream: turbo_stream.replace(
              ActionView::RecordIdentifier.dom_id(@playground, :token_limit_status),
              partial: "conversations/right_sidebar/token_limit_status",
              locals: { space: @playground }
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
        render_toast_turbo_stream(message: message, type: "warning", duration: 5000, status: :conflict)
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
      :auto_without_human_delay_ms,
      :during_generation_user_input_policy,
      :user_turn_debounce_ms,
      :group_regenerate_mode,
      :token_limit,
      prompt_settings: [
        i18n: [
          :mode,
          :internal_lang,
          :target_lang,
          :source_lang,
          :auto_vibe_target_lang,
          :prompt_preset,
          {
            provider: %i[
              kind
              llm_provider_id
              model_override
            ],
            chunking: %i[
              max_chars
            ],
            cache: %i[
              enabled
              ttl_seconds
              scope
            ],
            masking: %i[
              enabled
              protect_code_blocks
              protect_inline_code
              protect_urls
              protect_handlebars
            ],
            glossary: %i[
              enabled
              entries_json
            ],
            ntl: %i[
              enabled
              entries_json
            ],
            translator_prompts: %i[
              system_prompt
              user_prompt_template
              repair_system_prompt
              repair_user_prompt_template
            ],
          },
        ],
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

    # internal_lang is intentionally not user-editable after initial configuration.
    # We keep it as a persisted field for future non-en support, but treat it as
    # read-only in the UI/API for existing spaces to avoid confusing state/caches.
    attrs.dig("prompt_settings", "i18n")&.delete("internal_lang") if action_name == "update"

    # Coerce integer fields (empty string becomes default value)
    if attrs.key?("token_limit")
      attrs["token_limit"] = coerce_integer(attrs["token_limit"]) || 0
    end
    if attrs.key?("auto_without_human_delay_ms")
      attrs["auto_without_human_delay_ms"] = coerce_integer(attrs["auto_without_human_delay_ms"]) || 5000
    end
    if attrs.key?("user_turn_debounce_ms")
      attrs["user_turn_debounce_ms"] = coerce_integer(attrs["user_turn_debounce_ms"]) || 0
    end

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

    i18n = attrs.dig("prompt_settings", "i18n")
    if i18n.is_a?(Hash)
      provider = i18n["provider"]
      provider["llm_provider_id"] = coerce_integer(provider["llm_provider_id"]) if provider.is_a?(Hash) && provider.key?("llm_provider_id")

      chunking = i18n["chunking"]
      chunking["max_chars"] = coerce_integer(chunking["max_chars"]) if chunking.is_a?(Hash) && chunking.key?("max_chars")

      cache = i18n["cache"]
      if cache.is_a?(Hash)
        cache["enabled"] = coerce_boolean(cache["enabled"]) if cache.key?("enabled")
        cache["ttl_seconds"] = coerce_integer(cache["ttl_seconds"]) if cache.key?("ttl_seconds")
      end

      masking = i18n["masking"]
      if masking.is_a?(Hash)
        %w[enabled protect_code_blocks protect_inline_code protect_urls protect_handlebars].each do |key|
          next unless masking.key?(key)

          masking[key] = coerce_boolean(masking[key])
        end
      end

      glossary = i18n["glossary"]
      glossary["enabled"] = coerce_boolean(glossary["enabled"]) if glossary.is_a?(Hash) && glossary.key?("enabled")

      ntl = i18n["ntl"]
      ntl["enabled"] = coerce_boolean(ntl["enabled"]) if ntl.is_a?(Hash) && ntl.key?("enabled")

      if i18n.key?("auto_vibe_target_lang")
        i18n["auto_vibe_target_lang"] = coerce_boolean(i18n["auto_vibe_target_lang"])
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

  def owner_membership_attributes
    sm = params[:space_membership]
    return {} unless sm.is_a?(ActionController::Parameters)

    permitted = sm.permit(:persona, :character_id, :name_override)
    persona = permitted[:persona].to_s.strip.presence
    name_override = permitted[:name_override].to_s.strip.presence
    persona_character_id = permitted[:character_id].to_i
    persona_character_id = nil unless persona_character_id.positive?

    {
      name_override: name_override,
      persona: persona,
      persona_character_id: persona_character_id,
    }
  end

  def validate_owner_membership!(owner_membership)
    persona_character_id = owner_membership[:persona_character_id]
    return if persona_character_id.blank?

    available =
      Character
        .accessible_to(Current.user)
        .ready
        .where(id: persona_character_id)
        .exists?

    return if available

    invalid = Spaces::Playground.new(playground_params)
    invalid.errors.add(:base, "Persona character is not available")
    raise ActiveRecord::RecordInvalid, invalid
  end

  def merge_prompt_settings(current_settings, incoming_settings)
    return incoming_settings unless incoming_settings.is_a?(Hash)

    current_hash =
      if current_settings.respond_to?(:to_h)
        current_settings.to_h
      elsif current_settings.is_a?(Hash)
        current_settings
      else
        {}
      end

    current_hash.deep_stringify_keys.deep_merge(incoming_settings.deep_stringify_keys)
  end
end
