# frozen_string_literal: true

class Settings::CharactersController < Settings::ApplicationController
  before_action :set_character, only: %i[show edit update destroy]

  # GET /settings/characters
  # List all characters (ready + pending) with optional filtering.
  def index
    # Handle polling request for pending character updates
    if params[:ids].present? && request.headers["Accept"]&.include?("turbo-stream")
      return refresh_pending_characters
    end

    # Ready characters
    @characters = Character.where(status: %w[pending ready])
                           .order(created_at: :desc)
                           .includes(portrait_attachment: :blob)

    # Optional tag filtering
    @characters = @characters.with_tag(params[:tag]) if params[:tag].present?

    # Optional spec version filtering
    @characters = @characters.by_spec_version(params[:version].to_i) if params[:version].present?
  end

  # GET /settings/characters/:id
  def show
  end

  # GET /settings/characters/:id/edit
  def edit
  end

  # POST /settings/characters
  # Accept file upload and enqueue import job.
  def create
    unless params[:file].present?
      flash[:alert] = t("characters.create.no_file")
      return redirect_to settings_characters_path
    end

    file = params[:file]

    # Validate file format
    unless CharacterImport::Detector.supported?(file.original_filename)
      flash[:alert] = t("characters.create.unsupported_format")
      return redirect_to settings_characters_path
    end

    # Extract placeholder name from filename (without extension)
    placeholder_name = File.basename(file.original_filename, ".*")

    # Create placeholder character immediately
    character = Character.create!(
      name: placeholder_name,
      status: "pending"
    )

    # Create upload record linked to the placeholder character
    upload = Current.user.character_uploads.create!(
      filename: file.original_filename,
      content_type: file.content_type,
      status: "pending",
      character: character
    )

    # Attach the file
    upload.file.attach(file)

    # Enqueue import job
    CharacterImportJob.perform_later(upload.id)

    # Simple redirect with page refresh - no complex notifications
    redirect_to settings_characters_path, notice: t("characters.create.queued")
  end

  # PATCH/PUT /settings/characters/:id
  def update
    if json_request?
      handle_json_update
    else
      handle_form_update
    end
  end

  # DELETE /settings/characters/:id
  def destroy
    @character.mark_deleting!
    CharacterDeleteJob.perform_later(@character.id)
    redirect_to settings_characters_path, notice: t("characters.destroy.queued")
  end

  private

  def set_character
    @character = Character.find(params[:id])
  end

  def character_params
    params.require(:character).permit(:name, :nickname)
  end

  def card_update_params
    attrs = character_params.to_h
    data = (@character.data || {}).deep_dup

    # Keep exported card data in sync with editable fields.
    data["name"] = attrs["name"] if attrs.key?("name")
    data["nickname"] = attrs["nickname"].presence if attrs.key?("nickname")

    {
      data: data,
      file_sha256: nil, # allow re-importing the original file after edits
    }
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
      updates[:data] = (@character.data || {}).deep_merge(data_patch)
      updates[:file_sha256] = nil
    end

    # Handle authors_note_settings updates
    if payload.key?("authors_note_settings")
      an_patch = payload["authors_note_settings"]
      unless an_patch.is_a?(Hash)
        return render json: { ok: false, errors: ["authors_note_settings must be an object"] }, status: :bad_request
      end
      updates[:authors_note_settings] = (@character.authors_note_settings || {}).deep_merge(an_patch)
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
          data: @character.data,
          authors_note_settings: @character.authors_note_settings,
        },
      }
    else
      render json: { ok: false, errors: @character.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def handle_form_update
    if @character.update(card_update_params)
      redirect_to settings_character_path(@character), notice: t("characters.update.success")
    else
      flash.now[:alert] = @character.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
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
