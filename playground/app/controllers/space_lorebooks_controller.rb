# frozen_string_literal: true

# Controller for managing lorebook attachments to spaces.
#
# Allows attaching/detaching standalone lorebooks to a space
# for use in prompt generation.
#
class SpaceLorebooksController < ApplicationController
  include ActionView::RecordIdentifier
  include Authorization

  before_action :set_space
  before_action :ensure_space_admin, only: %i[create destroy toggle reorder]
  before_action :ensure_space_writable, only: %i[create destroy toggle reorder]
  before_action :set_space_lorebook, only: %i[destroy toggle]

  def index
    load_index_data
  end

  def create
    @space_lorebook = @space.space_lorebooks.build(space_lorebook_params)

    if @space_lorebook.save
      respond_to do |format|
        format.html { redirect_to playground_space_lorebooks_path(@space), notice: t("space_lorebooks.attached") }
        format.turbo_stream { load_index_data }
      end
    else
      redirect_to playground_space_lorebooks_path(@space), alert: @space_lorebook.errors.full_messages.join(", ")
    end
  end

  def destroy
    @space_lorebook.destroy!

    respond_to do |format|
      format.html { redirect_to playground_space_lorebooks_path(@space), notice: t("space_lorebooks.detached") }
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@space_lorebook)) }
    end
  end

  def toggle
    @space_lorebook.update!(enabled: !@space_lorebook.enabled)

    respond_to do |format|
      format.html { redirect_to playground_space_lorebooks_path(@space) }
      format.turbo_stream { render turbo_stream: turbo_stream.replace(dom_id(@space_lorebook), partial: "space_lorebook", locals: { space_lorebook: @space_lorebook, space: @space }) }
    end
  end

  def reorder
    position_updates = params[:positions]
    return head :bad_request unless position_updates.is_a?(Array)

    SpaceLorebook.transaction do
      position_updates.each_with_index do |id, index|
        @space.space_lorebooks.where(id: id).update_all(priority: index)
      end
    end

    head :ok
  end

  private

  def set_space
    @space = Current.user.spaces.playgrounds.find_by(id: params[:playground_id])
    return if @space

    redirect_to root_url, alert: t("playgrounds.not_found", default: "Playground not found")
  end

  def set_space_lorebook
    @space_lorebook = @space.space_lorebooks.find(params[:id])
  end

  def space_lorebook_params
    params.require(:space_lorebook).permit(:lorebook_id, :source, :enabled)
  end

  def load_index_data
    @space_lorebooks = @space.space_lorebooks.includes(:lorebook).by_priority
    @available_lorebooks = Lorebook.where.not(id: @space.lorebook_ids).ordered
  end
end
