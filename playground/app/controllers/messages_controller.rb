# frozen_string_literal: true

# Controller for managing messages within a conversation.
#
# Handles CRUD operations for messages with plain text content.
# Messages are sent through space memberships, allowing both users and
# AI characters to participate.
#
class MessagesController < ApplicationController
  include Authorization

  before_action :set_conversation
  before_action :ensure_space_writable, only: %i[create edit inline_edit update destroy]
  before_action :set_message, only: %i[show edit inline_edit update destroy]
  before_action :ensure_message_owner, only: %i[edit inline_edit update destroy]

  layout false, only: :index

  # GET /conversations/:conversation_id/messages
  # Returns paginated messages for the conversation.
  def index
    @messages = find_paged_messages

    respond_to do |format|
      format.html do
        if @messages.any?
          render partial: "messages/message", collection: @messages, as: :message, locals: { conversation: @conversation, space: @space }
        else
          head :no_content
        end
      end
      format.turbo_stream do
        render turbo_stream: turbo_stream.prepend(
          helpers.dom_id(@conversation, :messages_list),
          partial: "messages/messages_batch",
          locals: { messages: @messages, conversation: @conversation, space: @space }
        )
      end
    end
  end

  # POST /conversations/:conversation_id/messages
  def create
    @membership = @space.space_memberships.active.find_by(user_id: Current.user.id, kind: "human")
    return head :forbidden unless @membership

    if @membership.copilot_full?
      respond_to do |format|
        format.turbo_stream { head :forbidden }
        format.html { redirect_to conversation_url(@conversation), alert: t("messages.copilot_full_read_only", default: "Copilot is in full mode. Manual replies are disabled.") }
      end
      return
    end

    if @space.during_generation_user_input_policy == "reject" &&
         ConversationRun.running.exists?(conversation_id: @conversation.id)
      respond_to do |format|
        format.turbo_stream { head :locked }
        format.html { redirect_to conversation_url(@conversation), alert: t("messages.generating_locked", default: "AI is generating a response. Please wait…") }
      end
      return
    end

    @message = @conversation.messages.new(message_params)
    @message.space_membership = @membership
    @message.role = "user"

    if @message.save
      @message.broadcast_create

      Conversation::RunPlanner.plan_from_user_message!(conversation: @conversation, user_message: @message)

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to conversation_url(@conversation, anchor: helpers.dom_id(@message)) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("message_form", partial: "messages/form", locals: { conversation: @conversation, space: @space, message: @message }) }
        format.html { redirect_to conversation_url(@conversation), alert: @message.errors.full_messages.to_sentence }
      end
    end
  end

  # GET /conversations/:conversation_id/messages/:id
  def show
    respond_to do |format|
      format.html do
        content_frame_id = helpers.dom_id(@message, :content)
        if turbo_frame_request_id == content_frame_id
          render partial: "messages/message_content", locals: { message: @message }
        else
          render :show
        end
      end
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          @message,
          partial: "messages/message",
          locals: { message: @message, conversation: @conversation, space: @space }
        )
      end
    end
  end

  # GET /conversations/:conversation_id/messages/:id/edit
  def edit
  end

  # GET /conversations/:conversation_id/messages/:id/inline_edit
  def inline_edit
    render partial: "messages/inline_edit", locals: { message: @message, conversation: @conversation, space: @space }
  end

  # PATCH/PUT /conversations/:conversation_id/messages/:id
  def update
    if @message.update(message_params)
      @message.broadcast_update

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(@message, :content),
            partial: "messages/message_content",
            locals: { message: @message }
          )
        end
        format.html { redirect_to conversation_message_url(@conversation, @message) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(@message, :content),
            partial: "messages/inline_edit",
            locals: { message: @message, conversation: @conversation, space: @space }
          )
        end
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /conversations/:conversation_id/messages/:id
  def destroy
    @message.destroy!
    @message.broadcast_remove

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to conversation_url(@conversation) }
    end
  end

  private

  def set_conversation
    @conversation = Conversation.find(params[:conversation_id])
    @space = @conversation.space
  end

  def set_message
    @message = @conversation.messages.find(params[:id])
  end

  # Find paginated messages for the conversation.
  def find_paged_messages
    messages = @conversation.messages.with_space_membership
    per_page = 20

    if params[:before].present?
      cursor = messages.find_by(id: params[:before])
      return messages.none unless cursor

      messages.page_before_cursor(cursor, per_page)
    elsif params[:after].present?
      cursor = messages.find_by(id: params[:after])
      return messages.none unless cursor

      messages.page_after_cursor(cursor, per_page)
    else
      messages.recent_chronological(per_page)
    end
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
