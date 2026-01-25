# frozen_string_literal: true

# Controller for managing messages within a conversation.
#
# Handles CRUD operations for messages with plain text content.
# Messages are sent through space memberships, allowing both users and
# AI characters to participate.
#
class MessagesController < Conversations::ApplicationController
  include Authorization

  before_action :ensure_space_writable, only: %i[create edit inline_edit update destroy translate]
  before_action :set_message, only: %i[show edit inline_edit update destroy translate]
  before_action :ensure_message_owner, only: %i[edit inline_edit update destroy]
  before_action :ensure_tail_message_for_modification, only: %i[edit inline_edit update]
  before_action :ensure_not_fork_point, only: %i[edit inline_edit update destroy]
  before_action :ensure_space_admin, only: %i[translate]

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
        if @messages.any?
          action = params[:after].present? ? :append : :prepend

          render turbo_stream: turbo_stream.public_send(
            action,
            helpers.dom_id(@conversation, :messages_list),
            partial: "messages/messages_batch",
            locals: { messages: @messages, conversation: @conversation, space: @space }
          )
        else
          head :no_content
        end
      end
    end
  end

  # POST /conversations/:conversation_id/messages
  #
  # Delegates to Messages::Creator service for business logic.
  # Controller handles: resource lookup, authorization, rendering.
  def create
    @membership = @space_membership

    reset_blocked_turn_modes_if_needed!

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

  # POST /conversations/:conversation_id/messages/:id/translate
  #
  # Enqueues a background translation job for an assistant message.
  # Translation results are written to message/swipe metadata and broadcast
  # back into the conversation via Turbo Streams.
  def translate
    unless @message.assistant?
      message = t("messages.translate_assistant_only", default: "Only assistant messages can be translated.")
      return respond_to do |format|
        format.turbo_stream { render_toast_turbo_stream(message: message, type: "warning", duration: 4000, status: :unprocessable_entity) }
        format.html { redirect_to conversation_url(@conversation), alert: message }
        format.any { head :unprocessable_entity }
      end
    end

    settings = @space.prompt_settings&.i18n
    if settings.nil? || settings.mode != "translate_both"
      message = t("messages.translation_disabled", default: "Translation is disabled. Enable Translate both in Language / Translation settings first.")
      return respond_to do |format|
        format.turbo_stream { render_toast_turbo_stream(message: message, type: "warning", duration: 5000, status: :unprocessable_entity) }
        format.html { redirect_to conversation_url(@conversation), alert: message }
        format.any { head :unprocessable_entity }
      end
    end

    target_lang = settings.target_lang.to_s
    internal_lang = settings.internal_lang.to_s

    if target_lang.blank?
      message = t("messages.translation_missing_lang", default: "Target language is not configured.")
      return respond_to do |format|
        format.turbo_stream { render_toast_turbo_stream(message: message, type: "warning", duration: 4000, status: :unprocessable_entity) }
        format.html { redirect_to conversation_url(@conversation), alert: message }
        format.any { head :unprocessable_entity }
      end
    end

    if target_lang == internal_lang
      message = t("messages.translation_same_lang", default: "Target language matches internal language; nothing to translate.")
      return respond_to do |format|
        format.turbo_stream { render_toast_turbo_stream(message: message, type: "info", duration: 4000, status: :ok) }
        format.html { redirect_to conversation_url(@conversation), notice: message }
        format.any { head :ok }
      end
    end

    swipe_id = @message.active_message_swipe_id
    target_record = swipe_id ? @message.active_message_swipe : @message

    marked_pending = false
    if target_record && Translation::Metadata.mark_pending!(target_record, target_lang: target_lang)
      marked_pending = true
    end

    run =
      if marked_pending
        TranslationRun.create!(
          conversation: @conversation,
          message: @message,
          message_swipe_id: swipe_id,
          kind: "message_translation",
          status: "queued",
          source_lang: internal_lang,
          internal_lang: internal_lang,
          target_lang: target_lang,
          debug: { "enqueued_by" => "messages_controller" }
        ).tap do |created|
          ConversationEvents::Emitter.emit(
            event_name: "translation_run.queued",
            conversation: @conversation,
            space: @space,
            message_id: @message.id,
            reason: created.debug["enqueued_by"],
            payload: {
              translation_run_id: created.id,
              message_swipe_id: swipe_id,
              source_lang: created.source_lang,
              internal_lang: created.internal_lang,
              target_lang: created.target_lang,
            }
          )
        end
      else
        TranslationRun
          .active
          .where(message_id: @message.id, message_swipe_id: swipe_id, target_lang: target_lang)
          .order(created_at: :desc)
          .first
      end

    # Ensure the UI updates (and buttons re-enable) even if the translation was already pending.
    # This also prevents "stuck disabled button" when the request succeeds but Turbo doesn't
    # replace the message DOM (because the pending state was already set).
    if target_record && Translation::Metadata.pending?(target_record, target_lang: target_lang)
      @message.association(:active_message_swipe).reset
      @message.broadcast_update
    end

    if run.nil? && target_record && Translation::Metadata.pending?(target_record, target_lang: target_lang)
      run =
        TranslationRun.create!(
          conversation: @conversation,
          message: @message,
          message_swipe_id: swipe_id,
          kind: "message_translation",
          status: "queued",
          source_lang: internal_lang,
          internal_lang: internal_lang,
          target_lang: target_lang,
          debug: { "enqueued_by" => "messages_controller" }
        ).tap do |created|
          ConversationEvents::Emitter.emit(
            event_name: "translation_run.queued",
            conversation: @conversation,
            space: @space,
            message_id: @message.id,
            reason: created.debug["enqueued_by"],
            payload: {
              translation_run_id: created.id,
              message_swipe_id: swipe_id,
              source_lang: created.source_lang,
              internal_lang: created.internal_lang,
              target_lang: created.target_lang,
            }
          )
        end
    end

    MessageTranslationJob.perform_later(run.id) if run

    respond_to do |format|
      format.turbo_stream do
        render_toast_turbo_stream(message: t("messages.translate_enqueued", default: "Translation queued."), type: "info", duration: 2500, status: :accepted)
      end
      format.html { head :accepted }
      format.any { head :accepted }
    end
  end

  # DELETE /conversations/:conversation_id/messages/:id
  #
  # Delegates to Messages::Hider service for business logic.
  # Controller handles: resource lookup, authorization, rendering.
  def destroy
    result = Messages::Hider.new(
      message: @message,
      conversation: @conversation,
      on_hidden: ->(msg, conv) {
        msg.broadcast_remove
        Messages::Broadcasts.broadcast_group_queue_update(conv)
      }
    ).call

    respond_to_destroy_result(result)
  end

  private

  def set_message
    @message = @conversation.messages.ui_visible.find(params[:id])
  end

  # Find paginated messages for the conversation.
  def find_paged_messages
    base = @conversation.messages.ui_visible
    messages = base.with_space_membership
    per_page = 20

    if params[:before].present?
      cursor = base.find_by(id: params[:before])
      return messages.none unless cursor

      messages.page_before_cursor(cursor, per_page)
    elsif params[:after].present?
      cursor = base.find_by(id: params[:after])
      return messages.none unless cursor

      messages.page_after_cursor(cursor, per_page)
    else
      messages.recent_chronological(per_page)
    end
  end

  def message_params
    params.require(:message).permit(:content)
  end

  # When the scheduler is in a failed (blocked) state, user input is treated as an
  # implicit "Stop" to reset the round and continue the conversation.
  #
  # Keep this logic in the Rails controller (not Stimulus) to avoid relying on
  # client-side timing/races for disabling modes before message submission.
  def reset_blocked_turn_modes_if_needed!
    return unless TurnScheduler.state(@conversation).failed?

    # Stop auto-without-human so the user gets a clear "manual recovery" boundary.
    @conversation.stop_auto_without_human! if @conversation.auto_without_human_enabled?

    # Disable Auto so manual input is accepted (Auto blocks manual messages).
    if @membership.auto_enabled?
      @membership.update!(auto: "none", auto_remaining_steps: nil)
      Messages::Broadcasts.broadcast_auto_disabled(@membership, reason: "turn_blocked_reset")
    end
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
      return
    end

    case result.error_code
    when :auto_blocked
      error_message = t("messages.auto_read_only", default: result.error)
      respond_to do |format|
        format.turbo_stream do
          render_toast_turbo_stream(message: error_message, type: "warning", duration: 5000, status: :forbidden)
        end
        format.html { redirect_to conversation_url(@conversation), alert: error_message }
      end
    when :generation_locked
      error_message = t("messages.generating_locked", default: result.error)
      respond_to do |format|
        format.turbo_stream do
          render_toast_turbo_stream(message: error_message, type: "warning", duration: 5000, status: :locked)
        end
        format.html { redirect_to conversation_url(@conversation), alert: error_message }
      end
    else # :validation_failed
      @message = result.message
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "message_form",
            partial: "messages/form",
            locals: { conversation: @conversation, space: @space, message: @message }
          )
        end
        format.html { redirect_to conversation_url(@conversation), alert: result.error }
      end
    end
  end

  # Protect non-tail messages from modification to preserve timeline consistency.
  # Same rationale as regenerate's non-tail protection - use Branch to modify history.
  #
  # @see TailMutationGuard
  def ensure_tail_message_for_modification
    return if action_name == "destroy"

    guard = TailMutationGuard.new(@conversation)
    return if guard.tail?(@message)

    error_message = t("messages.non_tail_edit_forbidden",
                      default: "Cannot edit/delete non-last message. Use Branch to modify history.")

    respond_to do |format|
      format.turbo_stream do
        render_toast_turbo_stream(message: error_message, type: "warning", duration: 5000, status: :unprocessable_entity)
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
        render_toast_turbo_stream(message: error_message, type: "error", duration: 5000, status: :unprocessable_entity)
      end
      format.html do
        redirect_to conversation_url(@conversation), alert: error_message
      end
    end
  end

  # Handle the result from Messages::Hider service.
  # Maps error codes to appropriate HTTP responses.
  def respond_to_destroy_result(result)
    if result.success?
      toast = destroy_success_toast(result.effects || {})

      respond_to do |format|
        format.turbo_stream do
          streams = [turbo_stream.remove(@message)]

          if toast
            response.set_header("X-TavernKit-Toast", "1")
            streams << toast_turbo_stream(message: toast.fetch(:message), type: toast.fetch(:type), duration: toast.fetch(:duration))
          end

          render turbo_stream: streams, status: :ok
        end
        format.html { redirect_to conversation_url(@conversation) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render_toast_turbo_stream(message: result.error, type: "error", duration: 5000, status: :unprocessable_entity)
        end
        format.html do
          redirect_to conversation_url(@conversation), alert: result.error
        end
      end
    end
  end

  def destroy_success_toast(effects)
    canceled_round = !!effects[:canceled_round]
    canceled_queued_runs = effects[:canceled_queued_runs].to_i
    requested_cancel_running = !!effects[:requested_cancel_running]

    message = t("messages.deleted", default: "Deleted message.")
    type = "info"

    if canceled_round || requested_cancel_running || canceled_queued_runs.positive?
      type = "warning"
      message =
        if canceled_round && requested_cancel_running
          t("messages.deleted_stop_and_reset", default: "Deleted message. This stopped generation and reset the current round.")
        elsif canceled_round
          t("messages.deleted_reset_round", default: "Deleted message. This reset the current round.")
        elsif requested_cancel_running
          t("messages.deleted_stopped_generation", default: "Deleted message. This stopped generation.")
        else
          t("messages.deleted_canceled_queue", default: "Deleted message. Queued replies were canceled.")
        end
    end

    { message: message, type: type, duration: 4000 }
  end
end
