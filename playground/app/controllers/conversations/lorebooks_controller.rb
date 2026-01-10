# frozen_string_literal: true

# Controller for managing lorebook attachments to conversations.
#
# Implements SillyTavern's "Chat Lore" feature, allowing each conversation
# to have its own linked lorebook(s) independent of space-level lorebooks.
#
# Chat lorebooks are sorted first in prompt building (before global/character lore),
# matching SillyTavern's chat lore behavior.
#
class Conversations::LorebooksController < Conversations::ApplicationController
  include ActionView::RecordIdentifier
  include Authorization

  before_action :ensure_space_writable, only: %i[create destroy toggle reorder]
  before_action :set_conversation_lorebook, only: %i[destroy toggle]

  def index
    load_index_data
  end

  def create
    @conversation_lorebook = @conversation.conversation_lorebooks.build(conversation_lorebook_params)

    if @conversation_lorebook.save
      respond_to do |format|
        format.html { redirect_to conversation_lorebooks_path(@conversation), notice: t("conversation_lorebooks.attached") }
        format.turbo_stream { load_index_data }
      end
    else
      redirect_to conversation_lorebooks_path(@conversation), alert: @conversation_lorebook.errors.full_messages.join(", ")
    end
  end

  def destroy
    @conversation_lorebook.destroy!

    respond_to do |format|
      format.html { redirect_to conversation_lorebooks_path(@conversation), notice: t("conversation_lorebooks.detached") }
      format.turbo_stream { load_index_data }
    end
  end

  def toggle
    @conversation_lorebook.update!(enabled: !@conversation_lorebook.enabled)

    respond_to do |format|
      format.html { redirect_to conversation_lorebooks_path(@conversation) }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          dom_id(@conversation_lorebook),
          partial: "conversation_lorebook",
          locals: { conversation_lorebook: @conversation_lorebook, conversation: @conversation }
        )
      end
    end
  end

  def reorder
    position_updates = params[:positions]
    return head :bad_request unless position_updates.is_a?(Array)

    ConversationLorebook.transaction do
      position_updates.each_with_index do |id, index|
        @conversation.conversation_lorebooks.where(id: id).update_all(priority: index)
      end
    end

    head :ok
  end

  private

  def set_conversation_lorebook
    @conversation_lorebook = @conversation.conversation_lorebooks.find(params[:id])
  end

  def conversation_lorebook_params
    params.require(:conversation_lorebook).permit(:lorebook_id, :enabled)
  end

  def load_index_data
    @conversation_lorebooks = @conversation.conversation_lorebooks.includes(:lorebook).by_priority
    @available_lorebooks = Lorebook.accessible_to(Current.user).where.not(id: @conversation.lorebook_ids).ordered
  end
end
