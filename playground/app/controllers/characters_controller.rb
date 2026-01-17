# frozen_string_literal: true

# User-facing character controller for managing characters.
#
# Provides:
# - List with filtering (ownership, name search, tags) and pagination
# - View character details
# - Import new characters (file upload)
# - Edit/update user-owned characters
# - Delete user-owned characters
# - Duplicate any accessible character
#
# Global characters (user_id = nil) are read-only but can be duplicated.
# User-owned characters have full CRUD access.
#
class CharactersController < ApplicationController
  before_action :set_character, only: %i[show edit update destroy duplicate portrait quick_start]
  before_action :require_editable, only: %i[edit update destroy]

  # GET /characters
  # List all accessible characters with optional filtering.
  def index
    characters = base_scope

    # NSFW filtering (default: hide NSFW)
    characters = characters.sfw unless params[:include_nsfw] == "1"

    # Ownership filter
    characters = apply_ownership_filter(characters)

    # Name search
    characters = characters.where("LOWER(name) LIKE ?", "%#{params[:q].downcase}%") if params[:q].present?

    # Tag filtering
    characters = characters.with_tag(params[:tag]) if params[:tag].present?

    # Spec version filtering
    characters = characters.by_spec_version(params[:version].to_i) if params[:version].present?

    # Ordering (recent or popular)
    characters = apply_sort_order(characters)

    characters = characters.includes(portrait_attachment: :blob)

    set_page_and_extract_portion_from characters, per_page: 20

    # Collect unique tags for filter dropdown (respect NSFW filter)
    tag_scope = Character.accessible_to(Current.user).ready
    tag_scope = tag_scope.sfw unless params[:include_nsfw] == "1"
    @available_tags = tag_scope.where.not(tags: [])
                               .pluck(:tags)
                               .flatten
                               .uniq
                               .sort
  end

  # GET /characters/:id
  # Show character details.
  def show
  end

  # GET /characters/new
  # Show import form.
  def new
  end

  # POST /characters
  # Create a character by importing a file.
  # Characters uploaded here belong to the current user and are private.
  def create
    result = CharacterImport::UploadEnqueuer.new(
      user: Current.user,
      file: params[:file],
      owner: Current.user,
      visibility: "private"
    ).call

    unless result.success?
      message = import_error_message(result)
      respond_to do |format|
        format.html { redirect_to characters_path, alert: message }
        format.turbo_stream { render_turbo_stream_error(message) }
      end
      return
    end

    respond_to do |format|
      format.html { redirect_to characters_path, notice: t("characters.create.queued") }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.prepend("characters_list", partial: "character_card", locals: { character: result.character }),
          turbo_stream.action(:close_modal, "import_modal"),
          turbo_stream.action(:show_toast, nil) do
            render_to_string(partial: "shared/toast", locals: { message: t("characters.create.queued"), type: :info })
          end,
        ]
      end
    end
  end

  # GET /characters/:id/edit
  # Show edit form for user-owned character.
  def edit
    # Keep the datalist lightweight; full autocomplete is tracked in BACKLOGS.md.
    @lorebooks = Lorebook.accessible_to(Current.user).ordered.limit(20)
  end

  # PATCH/PUT /characters/:id
  # Update a user-owned character.
  def update
    if json_request?
      handle_json_update
    else
      handle_form_update
    end
  end

  # DELETE /characters/:id
  # Delete a user-owned character.
  def destroy
    @character.mark_deleting!
    CharacterDeleteJob.perform_later(@character.id)
    redirect_to characters_path, notice: t("characters.destroy.queued")
  end

  # POST /characters/:id/duplicate
  # Create a copy of any accessible character.
  def duplicate
    copy = @character.create_copy(user: Current.user, visibility: "private")
    if copy.persisted?
      redirect_to characters_path,
                  notice: t("characters.duplicated", default: "Character duplicated successfully.")
    else
      redirect_to characters_path,
                  alert: t("characters.duplicate_failed",
                           default: "Failed to duplicate character: %{errors}",
                           errors: copy.errors.full_messages.join(", "))
    end
  end

  # POST /characters/:id/quick_start
  # Create a new playground with this character and redirect directly to the conversation.
  def quick_start
    unless @character.ready?
      redirect_to characters_path, alert: t("characters.quick_start.not_ready", default: "Character is not ready yet.")
      return
    end

    playground = Spaces::Playground.create_for(
      { name: @character.name },
      user: Current.user,
      characters: [@character]
    )

    redirect_to conversation_path(playground.conversations.first)
  end

  # GET /characters/:id/portrait
  # Redirect to the signed portrait URL for consistent caching.
  def portrait
    redirect_to fresh_character_portrait_path(@character)
  end

  # GET /characters/picker
  # Turbo Frame endpoint for character picker component.
  # Supports filtering by ownership, name search, tags, NSFW, and pagination.
  def picker
    characters = Character.accessible_to(Current.user).ready

    # NSFW filtering (default: hide NSFW)
    characters = characters.sfw unless params[:include_nsfw] == "1"

    # Ownership filter
    characters = apply_ownership_filter(characters)

    # Name search
    characters = characters.where("LOWER(name) LIKE ?", "%#{params[:q].downcase}%") if params[:q].present?

    # Tag filtering
    characters = characters.with_tag(params[:tag]) if params[:tag].present?

    # Exclude specified IDs (e.g., characters already in the space)
    if params[:excluded].present?
      excluded_ids = Array(params[:excluded]).map(&:to_i).reject(&:zero?)
      characters = characters.where.not(id: excluded_ids) if excluded_ids.any?
    end

    # Ordering (recent or popular)
    characters = apply_sort_order(characters)

    characters = characters.includes(portrait_attachment: :blob)

    set_page_and_extract_portion_from characters, per_page: 8

    # Collect unique tags for filter dropdown (respect NSFW filter)
    tag_scope = Character.accessible_to(Current.user).ready
    tag_scope = tag_scope.sfw unless params[:include_nsfw] == "1"
    @available_tags = tag_scope.where.not(tags: [])
                               .pluck(:tags)
                               .flatten
                               .uniq
                               .sort

    # Track selected character IDs (passed back for state preservation)
    @selected_ids = Array(params[:selected]).map(&:to_i)
    @excluded_ids = Array(params[:excluded]).map(&:to_i)
    @field_name = params[:field_name].presence || "character_ids[]"

    render layout: false
  end

  private

  def base_scope
    Character.accessible_to(Current.user).where(status: %w[pending ready failed])
  end

  def set_character
    @character = base_scope.find(params[:id])
  end

  def require_editable
    return if editable?(@character)

    redirect_to character_path(@character),
                alert: t("characters.not_editable", default: "You cannot edit this character.")
  end

  def editable?(character)
    character.user_id == Current.user&.id && !character.locked?
  end

  def global?(character)
    character.user_id.nil?
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

  def apply_sort_order(scope)
    case params[:sort]
    when "popular"
      scope.by_popularity
    else
      scope.order(created_at: :desc)
    end
  end

  def character_params
    params.require(:character).permit(:name, :nickname)
  end

  def data_params
    params.require(:character).permit(
      data: [
        :description, :personality, :scenario, :first_mes, :mes_example,
        :system_prompt, :post_history_instructions, :creator_notes,
        :creator, :character_version,
        { tags: [], alternate_greetings: [], group_only_greetings: [] },
        { extensions: [:talkativeness, :world, :extra_worlds, { extra_worlds: [] }] },
      ]
    )[:data] || {}
  end

  def authors_note_params
    params.require(:character).permit(
      authors_note_settings: %i[
        use_character_authors_note
        authors_note
        authors_note_position
        authors_note_depth
        authors_note_role
        character_authors_note_position
      ]
    )
  end

  def character_form_params
    attrs = character_params.to_h
    current_data = @character.data&.to_h&.deep_symbolize_keys || {}

    if params[:character]&.key?(:data)
      new_data = data_params.to_h.deep_symbolize_keys
      new_data[:tags] = new_data[:tags]&.reject(&:blank?) || []
      new_data[:alternate_greetings] = new_data[:alternate_greetings]&.reject(&:blank?) || []
      new_data[:group_only_greetings] = new_data[:group_only_greetings]&.reject(&:blank?) || []

      # Handle extensions merge with type coercion
      if new_data[:extensions].present?
        current_extensions = current_data[:extensions]&.deep_symbolize_keys || {}
        new_extensions = coerce_extensions_params(new_data[:extensions])
        new_data[:extensions] = current_extensions.merge(new_extensions)
      end

      current_data = current_data.merge(new_data)
    end

    current_data[:name] = attrs[:name] if attrs.key?(:name)
    current_data[:nickname] = attrs[:nickname].presence if attrs.key?(:nickname)

    result = {
      data: current_data,
      file_sha256: nil,
    }

    if params[:character]&.key?(:authors_note_settings)
      an_params = authors_note_params[:authors_note_settings]&.to_h || {}
      an_params["authors_note_depth"] = an_params["authors_note_depth"].to_i if an_params["authors_note_depth"].present?
      an_params["use_character_authors_note"] = an_params["use_character_authors_note"] == "1"
      current_an = @character.authors_note_settings&.to_h || {}
      result[:authors_note_settings] = current_an.merge(an_params)
    end

    result
  end

  def json_request?
    request.content_type&.include?("application/json")
  end

  def handle_json_update
    payload = parse_json_payload
    return render_parse_error unless payload

    updates = {}

    if payload.key?("data")
      data_patch = payload["data"]
      unless data_patch.is_a?(Hash)
        return render json: { ok: false, errors: ["data must be an object"] }, status: :bad_request
      end

      current_data = @character.data&.to_h&.deep_symbolize_keys || {}
      updates[:data] = current_data.deep_merge(data_patch.deep_symbolize_keys)
      updates[:file_sha256] = nil
    end

    if payload.key?("authors_note_settings")
      an_patch = payload["authors_note_settings"]
      unless an_patch.is_a?(Hash)
        return render json: { ok: false, errors: ["authors_note_settings must be an object"] }, status: :bad_request
      end

      current_an = @character.authors_note_settings&.to_h || {}
      updates[:authors_note_settings] = current_an.deep_merge(an_patch)
    end

    if updates.empty?
      return render json: { ok: false, errors: ["No valid fields to update"] }, status: :bad_request
    end

    if @character.update(updates)
      render json: {
        ok: true,
        saved_at: Time.current.iso8601,
        character: {
          id: @character.id,
          name: @character.name,
          nickname: @character.nickname,
          tags: @character.tags,
          data: @character.data&.to_h,
          authors_note_settings: @character.authors_note_settings,
        },
      }
    else
      render json: { ok: false, errors: @character.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def handle_form_update
    ActiveRecord::Base.transaction do
      if @character.update(character_form_params)
        redirect_to characters_path, notice: t("characters.update.success")
      else
        flash.now[:alert] = @character.errors.full_messages.to_sentence
        @lorebooks = Lorebook.accessible_to(Current.user).ordered.limit(20)
        render :edit, status: :unprocessable_entity
      end
    end
  end

  def parse_json_payload
    JSON.parse(request.body.read)
  rescue JSON::ParserError
    nil
  end

  def render_parse_error
    render json: { ok: false, errors: ["Invalid JSON payload"] }, status: :bad_request
  end

  def import_error_message(result)
    case result.error_code
    when :no_file
      t("characters.create.no_file")
    when :unsupported_format
      t("characters.create.unsupported_format")
    else
      t(
        "characters.create.failed",
        default: "Failed to start import: %{error}",
        error: result.error.presence || "Unknown error"
      )
    end
  end

  # Coerce extensions params to appropriate types for ST compatibility.
  # - talkativeness: string -> float (or nil if blank)
  # - world: string (or nil if blank)
  # - extra_worlds: array/json string -> array of strings
  def coerce_extensions_params(extensions)
    result = {}

    if extensions.key?(:talkativeness)
      val = extensions[:talkativeness].to_s.strip
      result[:talkativeness] = val.present? ? val.to_f : nil
    end

    if extensions.key?(:world)
      val = extensions[:world].to_s.strip
      result[:world] = val.presence
    end

    if extensions.key?(:extra_worlds)
      raw = extensions[:extra_worlds]
      list =
        case raw
        when Array
          raw
        when String
          s = raw.to_s.strip
          begin
            parsed = JSON.parse(s)
            parsed.is_a?(Array) ? parsed : []
          rescue JSON::ParserError
            []
          end
        else
          []
        end

      result[:extra_worlds] = list.map { |w| w.to_s.strip }.reject(&:empty?).uniq
    end

    result
  end

  def render_turbo_stream_error(message)
    render turbo_stream: turbo_stream.action(:show_toast, nil) {
      render_to_string(partial: "shared/toast", locals: { message: message, type: :error })
    }
  end
end
