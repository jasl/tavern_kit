# frozen_string_literal: true

# Controller for managing lorebook attachments to spaces.
#
# Allows attaching/detaching standalone lorebooks to a space
# for use in prompt generation.
#
class Playgrounds::LorebooksController < Playgrounds::ApplicationController
  include ActionView::RecordIdentifier
  include Authorization

  before_action :ensure_space_admin, only: %i[create destroy toggle reorder]
  before_action :ensure_space_writable, only: %i[create destroy toggle reorder]
  before_action :set_space_lorebook, only: %i[destroy toggle]

  def index
    load_index_data
  end

  def create
    @space_lorebook = @playground.space_lorebooks.build(space_lorebook_params)

    if @space_lorebook.save
      respond_to do |format|
        format.html { redirect_to playground_lorebooks_path(@playground), notice: t("space_lorebooks.attached") }
        format.turbo_stream { load_index_data }
      end
    else
      redirect_to playground_lorebooks_path(@playground), alert: @space_lorebook.errors.full_messages.join(", ")
    end
  end

  def destroy
    @space_lorebook.destroy!

    respond_to do |format|
      format.html { redirect_to playground_lorebooks_path(@playground), notice: t("space_lorebooks.detached") }
      format.turbo_stream { load_index_data }
    end
  end

  def toggle
    @space_lorebook.update!(enabled: !@space_lorebook.enabled)

    respond_to do |format|
      format.html { redirect_to playground_lorebooks_path(@playground) }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          dom_id(@space_lorebook),
          partial: "space_lorebook",
          locals: { space_lorebook: @space_lorebook, space: @playground }
        )
      end
    end
  end

  def reorder
    position_updates = params[:positions]
    return head :bad_request unless position_updates.is_a?(Array)

    SpaceLorebook.transaction do
      position_updates.each_with_index do |id, index|
        @playground.space_lorebooks.where(id: id).update_all(priority: index)
      end
    end

    head :ok
  end

  private

  def set_space_lorebook
    @space_lorebook = @playground.space_lorebooks.find(params[:id])
  end

  def space_lorebook_params
    params.require(:space_lorebook).permit(:lorebook_id, :source, :enabled)
  end

  def load_index_data
    @space_lorebooks = @playground.space_lorebooks.includes(:lorebook).by_priority
    @available_lorebooks = Lorebook.accessible_to(Current.user).where.not(id: @playground.lorebook_ids).ordered
  end
end
