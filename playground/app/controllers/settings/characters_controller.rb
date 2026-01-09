# frozen_string_literal: true

class Settings::CharactersController < Settings::ApplicationController
  before_action :set_character, only: %i[show edit update destroy duplicate lock unlock publish unpublish]

  # GET /settings/characters
  # List all characters (ready + pending) with optional filtering.
  def index
    # Handle polling request for pending character updates
    if params[:ids].present? && request.headers["Accept"]&.include?("turbo-stream")
      return refresh_pending_characters
    end

    # Ready characters
    characters = Character.where(status: %w[pending ready])
                          .order(created_at: :desc)
                          .includes(:user, portrait_attachment: :blob)

    # Ownership filter
    characters = apply_ownership_filter(characters)

    # Name search
    characters = characters.where("LOWER(name) LIKE ?", "%#{params[:q].downcase}%") if params[:q].present?

    # Optional tag filtering
    characters = characters.with_tag(params[:tag]) if params[:tag].present?

    # Optional spec version filtering
    characters = characters.by_spec_version(params[:version].to_i) if params[:version].present?

    set_page_and_extract_portion_from characters, per_page: 20

    # Collect unique tags for filter dropdown
    @available_tags = Character.where(status: %w[pending ready])
                               .where.not(tags: [])
                               .pluck(:tags)
                               .flatten
                               .uniq
                               .sort
  end

  # GET /settings/characters/:id
  # Show character details (read-only view for locked characters).
  def show
    @lorebooks = Lorebook.ordered
    @character_lorebooks = @character.character_lorebooks.includes(:lorebook).index_by(&:lorebook_id)
  end

  # GET /settings/characters/:id/edit
  def edit
    # Redirect to show view if locked (read-only)
    if @character.locked?
      redirect_to settings_character_path(@character)
      return
    end

    @lorebooks = Lorebook.ordered
    @character_lorebooks = @character.character_lorebooks.includes(:lorebook).index_by(&:lorebook_id)
  end

  # POST /settings/characters
  # Accept file upload and enqueue import job.
  def create
    result = CharacterImport::UploadEnqueuer.new(
      user: Current.user,
      file: params[:file]
    ).call

    unless result.success?
      message =
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

      respond_to do |format|
        format.html { redirect_to settings_characters_path, alert: message }
        format.turbo_stream { render_turbo_stream_error(message) }
      end
      return
    end

    character = result.character

    respond_to do |format|
      format.html { redirect_to settings_characters_path, notice: t("characters.create.queued") }
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.remove("characters_empty_state"),
          turbo_stream.prepend("characters_list", partial: "character", locals: { character: character }),
          turbo_stream.action(:close_modal, "import_modal"),
          turbo_stream.action(:show_toast, nil) do
            render_to_string(partial: "shared/toast", locals: { message: t("characters.create.queued"), type: :info })
          end,
        ]
      end
    end
  end

  # PATCH/PUT /settings/characters/:id
  def update
    if @character.locked?
      if json_request?
        render json: { ok: false, errors: ["Character is locked"] }, status: :forbidden
      else
        redirect_to settings_character_path(@character), alert: t("characters.locked", default: "Character is locked.")
      end
      return
    end

    if json_request?
      handle_json_update
    else
      handle_form_update
    end
  end

  # DELETE /settings/characters/:id
  def destroy
    if @character.locked?
      redirect_to settings_characters_path, alert: t("characters.locked", default: "Character is locked.")
      return
    end

    @character.mark_deleting!
    CharacterDeleteJob.perform_later(@character.id)
    redirect_to settings_characters_path, notice: t("characters.destroy.queued")
  end

  # POST /settings/characters/:id/duplicate
  def duplicate
    copy = @character.create_copy(user: Current.user, visibility: "public")
    if copy.persisted?
      redirect_to settings_characters_path,
                  notice: t("characters.duplicated", default: "Character duplicated successfully.")
    else
      redirect_to settings_characters_path,
                  alert: t("characters.duplicate_failed",
                           default: "Failed to duplicate character: %{errors}",
                           errors: copy.errors.full_messages.join(", "))
    end
  end

  # POST /settings/characters/:id/lock
  def lock
    @character.lock!
    redirect_to settings_characters_path, notice: t("characters.locked_success", default: "Character locked.")
  end

  # POST /settings/characters/:id/unlock
  def unlock
    @character.unlock!
    redirect_to settings_characters_path, notice: t("characters.unlocked", default: "Character unlocked.")
  end

  # POST /settings/characters/:id/publish
  def publish
    @character.publish!
    redirect_to settings_characters_path, notice: t("characters.published", default: "Character published.")
  end

  # POST /settings/characters/:id/unpublish
  def unpublish
    @character.unpublish!
    redirect_to settings_characters_path, notice: t("characters.unpublished", default: "Character unpublished.")
  end

  private

  def set_character
    @character = Character.find(params[:id])
  end

  def character_params
    params.require(:character).permit(:name, :nickname)
  end

  # Permitted params for data (character card fields)
  def data_params
    params.require(:character).permit(
      data: [
        :description, :personality, :scenario, :first_mes, :mes_example,
        :system_prompt, :post_history_instructions, :creator_notes,
        :creator, :character_version,
        { tags: [], alternate_greetings: [], group_only_greetings: [] },
      ]
    )[:data] || {}
  end

  # Permitted params for Author's Note settings
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

  # Build update params from form submission
  def character_form_params
    attrs = character_params.to_h

    # Get current data as hash (Schema -> Hash)
    current_data = @character.data&.to_h&.deep_symbolize_keys || {}

    # Merge data params if present
    if params[:character]&.key?(:data)
      new_data = data_params.to_h.deep_symbolize_keys
      # Filter out empty strings from arrays
      new_data[:tags] = new_data[:tags]&.reject(&:blank?) || []
      new_data[:alternate_greetings] = new_data[:alternate_greetings]&.reject(&:blank?) || []
      new_data[:group_only_greetings] = new_data[:group_only_greetings]&.reject(&:blank?) || []
      current_data = current_data.merge(new_data)
    end

    # Sync name/nickname to data
    current_data[:name] = attrs[:name] if attrs.key?(:name)
    current_data[:nickname] = attrs[:nickname].presence if attrs.key?(:nickname)

    result = {
      data: current_data,
      file_sha256: nil, # allow re-importing the original file after edits
    }

    # Include authors_note_settings if present
    if params[:character]&.key?(:authors_note_settings)
      an_params = authors_note_params[:authors_note_settings]&.to_h || {}
      # Convert depth to integer
      an_params["authors_note_depth"] = an_params["authors_note_depth"].to_i if an_params["authors_note_depth"].present?
      # Convert checkbox to boolean
      an_params["use_character_authors_note"] = an_params["use_character_authors_note"] == "1"
      # Convert schema object to hash before merging
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

    # Handle data field updates (character card fields)
    if payload.key?("data")
      data_patch = payload["data"]
      unless data_patch.is_a?(Hash)
        return render json: { ok: false, errors: ["data must be an object"] }, status: :bad_request
      end
      # Merge with existing data (Schema -> Hash -> merge -> back to Hash for serialize)
      current_data = @character.data&.to_h&.deep_symbolize_keys || {}
      updates[:data] = current_data.deep_merge(data_patch.deep_symbolize_keys)
      updates[:file_sha256] = nil
    end

    # Handle authors_note_settings updates
    if payload.key?("authors_note_settings")
      an_patch = payload["authors_note_settings"]
      unless an_patch.is_a?(Hash)
        return render json: { ok: false, errors: ["authors_note_settings must be an object"] }, status: :bad_request
      end
      # Convert schema object to hash before merging
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
        sync_character_lorebooks
        redirect_to edit_settings_character_path(@character), notice: t("characters.update.success")
      else
        flash.now[:alert] = @character.errors.full_messages.to_sentence
        @lorebooks = Lorebook.ordered
        @character_lorebooks = @character.character_lorebooks.includes(:lorebook).index_by(&:lorebook_id)
        render :edit, status: :unprocessable_entity
      end
    end
  end

  # Sync character_lorebooks association based on form params.
  # Handles primary_lorebook_id and additional_lorebook_ids.
  def sync_character_lorebooks
    # Handle primary lorebook
    primary_id = params.dig(:character, :primary_lorebook_id)
    sync_primary_lorebook(primary_id)

    # Handle additional lorebooks
    additional_ids = params.dig(:character, :additional_lorebook_ids)
    sync_additional_lorebooks(additional_ids) if params[:character]&.key?(:additional_lorebook_ids)
  end

  def sync_primary_lorebook(lorebook_id)
    current_primary = @character.character_lorebooks.primary.first

    if lorebook_id.blank?
      # Remove primary if cleared
      current_primary&.destroy
    elsif current_primary&.lorebook_id.to_s != lorebook_id.to_s
      # Replace primary if changed
      current_primary&.destroy
      @character.character_lorebooks.create!(
        lorebook_id: lorebook_id,
        source: "primary",
        enabled: true
      )
    end
  end

  def sync_additional_lorebooks(lorebook_ids)
    lorebook_ids = Array(lorebook_ids).map(&:to_i).reject(&:zero?)

    current_ids = @character.character_lorebooks.additional.pluck(:lorebook_id)

    # Remove lorebooks that are no longer in the list
    ids_to_remove = current_ids - lorebook_ids
    @character.character_lorebooks.additional.where(lorebook_id: ids_to_remove).destroy_all

    # Add new lorebooks
    ids_to_add = lorebook_ids - current_ids
    ids_to_add.each_with_index do |id, index|
      @character.character_lorebooks.create!(
        lorebook_id: id,
        source: "additional",
        priority: index,
        enabled: true
      )
    end

    # Update priorities for existing lorebooks to match the order
    lorebook_ids.each_with_index do |id, index|
      @character.character_lorebooks.additional.where(lorebook_id: id).update_all(priority: index)
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

  def render_turbo_stream_error(message)
    render turbo_stream: turbo_stream.action(:show_toast, nil) {
      render_to_string(partial: "shared/toast", locals: { message: message, type: :error })
    }
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

  # Returns Turbo Stream updates for characters that are no longer pending.
  # Called via polling from pending_characters_controller.js
  def refresh_pending_characters
    ids = params[:ids].to_s.split(",").map(&:to_i).reject(&:zero?)
    return head :no_content if ids.empty?

    # Find characters that have changed from pending status
    characters = Character.where(id: ids).where.not(status: "pending")

    if characters.any?
      render turbo_stream: characters.map { |character|
        turbo_stream.replace(
          ActionView::RecordIdentifier.dom_id(character),
          partial: "settings/characters/character",
          locals: { character: character }
        )
      }
    else
      head :no_content
    end
  end
end
