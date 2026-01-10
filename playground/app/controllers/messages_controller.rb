# frozen_string_literal: true

# Controller for managing messages within a conversation.
#
# Handles CRUD operations for messages with plain text content.
# Messages are sent through space memberships, allowing both users and
# AI characters to participate.
#
class MessagesController < Conversations::ApplicationController
  include Authorization

  before_action :ensure_space_writable, only: %i[create edit inline_edit update destroy]
  before_action :set_message, only: %i[show edit inline_edit update destroy]
  before_action :ensure_message_owner, only: %i[edit inline_edit update destroy]
  before_action :ensure_tail_message_for_modification, only: %i[edit inline_edit update destroy]
  before_action :ensure_not_fork_point, only: %i[edit inline_edit update destroy]

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
  #
  # Delegates to Messages::Creator service for business logic.
  # Controller handles: resource lookup, authorization, rendering.
  def create
    @membership = @space_membership

    result = Messages::Creator.new(
      conversation: @conversation,
      membership: @membership,
      content: message_params[:content],
      on_created: ->(msg, conv) {
        # Broadcast to ALL conversation subscribers via ActionCable.
        # This ensures multi-user conversations work (other users see the message).
        #
        # The sender also receives the message via HTTP response (create.turbo_stream.erb)
        # for reliable delivery during WebSocket reconnection. Duplicate prevention
        # is handled client-side in conversation_channel_controller.js.
        msg.broadcast_create
        Message::Broadcasts.broadcast_group_queue_update(conv)
      }
    ).call

    respond_to_create_result(result)
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
  #
  # Delegates to Messages::Destroyer service for business logic.
  # Controller handles: resource lookup, authorization, rendering.
  def destroy
    result = Messages::Destroyer.new(
      message: @message,
      conversation: @conversation,
      on_destroyed: ->(msg, conv) {
        msg.broadcast_remove
        Message::Broadcasts.broadcast_group_queue_update(conv)
      }
    ).call

    respond_to_destroy_result(result)
  end

  private

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

  # Handle the result from Messages::Creator service.
  # Maps error codes to appropriate HTTP responses.
  def respond_to_create_result(result)
    if result.success?
      @message = result.message
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to conversation_url(@conversation, anchor: helpers.dom_id(@message)) }
      end
    else
      case result.error_code
      when :copilot_blocked
        respond_to do |format|
          format.turbo_stream { head :forbidden }
          format.html { redirect_to conversation_url(@conversation), alert: t("messages.copilot_full_read_only", default: result.error) }
        end
      when :generation_locked
        respond_to do |format|
          format.turbo_stream { head :locked }
          format.html { redirect_to conversation_url(@conversation), alert: t("messages.generating_locked", default: result.error) }
        end
      else # :validation_failed
        @message = result.message
        respond_to do |format|
          format.turbo_stream { render turbo_stream: turbo_stream.replace("message_form", partial: "messages/form", locals: { conversation: @conversation, space: @space, message: @message }) }
          format.html { redirect_to conversation_url(@conversation), alert: result.error }
        end
      end
    end
  end

  # Protect non-tail messages from modification to preserve timeline consistency.
  # Same rationale as regenerate's non-tail protection - use Branch to modify history.
  #
  # @see TailMutationGuard
  def ensure_tail_message_for_modification
    guard = TailMutationGuard.new(@conversation)
    return if guard.tail?(@message)

    error_message = t("messages.non_tail_edit_forbidden",
                      default: "Cannot edit/delete non-last message. Use Branch to modify history.")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: render_to_string(
          partial: "shared/toast_turbo_stream",
          locals: { message: error_message, type: "warning", duration: 5000 }
        ), status: :unprocessable_entity
      end
      format.html do
        redirect_to conversation_url(@conversation), alert: error_message
      end
    end
  end

  # Protect fork point messages from modification.
  # Messages that are referenced by child conversations (via forked_from_message_id)
  # cannot be edited or deleted to preserve timeline integrity.
  def ensure_not_fork_point
    return unless @message.fork_point?

    error_message = t("messages.fork_point_protected",
                      default: "This message is a fork point for other conversations and cannot be modified.")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: render_to_string(
          partial: "shared/toast_turbo_stream",
          locals: { message: error_message, type: "error", duration: 5000 }
        ), status: :unprocessable_entity
      end
      format.html do
        redirect_to conversation_url(@conversation), alert: error_message
      end
    end
  end

  # Handle the result from Messages::Destroyer service.
  # Maps error codes to appropriate HTTP responses.
  def respond_to_destroy_result(result)
    if result.success?
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to conversation_url(@conversation) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: render_to_string(
            partial: "shared/toast_turbo_stream",
            locals: { message: result.error, type: "error", duration: 5000 }
          ), status: :unprocessable_entity
        end
        format.html do
          redirect_to conversation_url(@conversation), alert: result.error
        end
      end
    end
  end
end
