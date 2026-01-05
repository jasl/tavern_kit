# frozen_string_literal: true

# Controller for conversation timelines.
class ConversationsController < ApplicationController
  include Authorization
  include TrackedSpaceVisit

  layout "chat", only: :show

  before_action :set_space, only: %i[create]
  before_action :set_conversation, only: %i[show update regenerate branch generate stop]
  before_action :ensure_space_writable, only: %i[update regenerate generate branch stop]
  before_action :remember_last_space_visited, only: :show

  # POST /spaces/:space_id/conversations
  # Creates a root conversation in a space.
  def create
    conversation = @space.conversations.create!(
      title: conversation_params[:title].presence || "Conversation",
      kind: "root"
    )

    conversation.create_first_messages!

    redirect_to conversation_url(conversation)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to playground_url(@space), alert: e.record.errors.full_messages.to_sentence
  end

  # GET /conversations/:id
  def show
    @messages = @conversation.messages.recent_chronological(50).with_space_membership
    @message = @conversation.messages.new
    @current_membership = @space.space_memberships.active.find_by(user_id: Current.user.id, kind: "human")
    @has_more = @messages.any? && @conversation.messages.where("seq < ?", @messages.first.seq).exists?

    # Preload tree data for branch navigation
    @tree_conversations = @conversation.tree_conversations
      .includes(:forked_from_message, :parent_conversation)
      .chronological
  end

  # PATCH /conversations/:id
  # Updates conversation attributes (title, authors_note, etc.)
  def update
    @conversation.update!(conversation_params)

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to conversation_url(@conversation) }
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.turbo_stream { head :unprocessable_entity }
      format.html { redirect_to conversation_url(@conversation), alert: e.record.errors.full_messages.to_sentence }
    end
  end

  # POST /conversations/:id/regenerate
  # Triggers regeneration of an assistant message.
  #
  # Behavior:
  # - Without message_id: regenerates the tail message only if it's an assistant message
  # - With message_id: regenerates the specified assistant message
  #
  # Any regeneration of a non-tail message will auto-branch to preserve timeline consistency
  # (per SillyTavern Timelines behavior).
  def regenerate
    # Get the absolute tail message (max seq)
    tail_message = @conversation.messages.order(seq: :desc).first

    target_message = if params[:message_id].present?
      @conversation.messages.find(params[:message_id])
    else
      # No message_id: only allow regenerate if tail is assistant
      tail_message if tail_message&.assistant?
    end

    # Case 1: No message to regenerate (tail is not assistant when no message_id provided)
    unless target_message
      return respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html do
          redirect_to conversation_url(@conversation),
                      alert: t("messages.last_message_not_assistant", default: "Last message is not assistant.")
        end
      end
    end

    # Case 2: Target is not an assistant message (when message_id is explicitly provided)
    unless target_message.assistant?
      return respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html do
          redirect_to conversation_url(@conversation),
                      alert: t("messages.cannot_regenerate_non_assistant", default: "Cannot regenerate non-assistant message.")
        end
      end
    end

    # Case 3: Target is not the tail message -> auto-branch to preserve timeline consistency
    if target_message.id != tail_message&.id
      return handle_non_tail_regenerate(target_message)
    end

    # Case 4: Target == tail AND is assistant
    # Check if we should use last_turn mode (delete all AI messages in the turn, re-queue generation)
    if @space.group? && @space.group_regenerate_mode_last_turn?
      return handle_last_turn_regenerate
    end

    # Default: in-place swipe (single message regeneration)
    Conversation::RunPlanner.plan_regenerate!(conversation: @conversation, target_message: target_message)

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to conversation_url(@conversation, anchor: helpers.dom_id(target_message)) }
    end
  end

  # POST /conversations/:id/branch
  # Creates a branch (fork) from a specific message.
  #
  # Parameters (via request body):
  #   message_id: ID of the message to fork from (required)
  #   title: Title for the new branch (optional, defaults to "Branch")
  #   visibility: "shared" or "private" (optional, defaults to "shared")
  def branch
    message = @conversation.messages.find_by(id: branch_params[:message_id])
    return head :not_found unless message

    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: message,
      kind: "branch",
      title: branch_params[:title],
      visibility: branch_params[:visibility]
    ).call

    if result.success?
      redirect_to conversation_url(result.conversation)
    else
      redirect_to conversation_url(@conversation), alert: result.error
    end
  end

  # POST /conversations/:id/generate
  # Triggers an AI response without requiring a user message.
  #
  # Parameters:
  #   speaker_id: (optional) SpaceMembership ID to force a specific speaker
  #
  # Behavior:
  # - With speaker_id: Uses plan_force_talk! (works even for muted members)
  # - Without speaker_id + manual mode: Randomly selects an active AI character
  # - Without speaker_id + non-manual: Uses SpeakerSelector.select_for_user_turn
  def generate
    speaker = if params[:speaker_id].present?
      # Force talk mode: allow any active AI character (including muted)
      @space.space_memberships.active.ai_characters.find_by(id: params[:speaker_id])
    elsif @space.manual?
      # Manual mode: random selection from active participating AI characters
      @space.space_memberships.participating.ai_characters.sample
    else
      # Non-manual mode: use normal speaker selection
      SpeakerSelector.new(@conversation).select_for_user_turn
    end

    unless speaker
      return respond_to do |format|
        format.turbo_stream { head :unprocessable_entity }
        format.html { redirect_to conversation_url(@conversation), alert: t("messages.no_speaker_available", default: "No AI character available to respond.") }
      end
    end

    Conversation::RunPlanner.plan_force_talk!(
      conversation: @conversation,
      speaker_space_membership_id: speaker.id
    )

    respond_to do |format|
      format.turbo_stream { head :no_content }
      format.html { redirect_to conversation_url(@conversation) }
    end
  end

  # POST /conversations/:id/stop
  # Requests cancellation of any running generation for this conversation.
  #
  # Behavior:
  # - Sets cancel_requested_at on running run (idempotent via request_cancel!)
  # - Immediately broadcasts stream_complete + typing_stop to clear UI
  # - Returns 204 regardless of whether a run existed
  def stop
    running_run = @conversation.conversation_runs.running.first

    if running_run
      running_run.request_cancel!

      # Immediately broadcast to clear typing indicator (don't wait for executor)
      if running_run.speaker_space_membership_id
        ConversationChannel.broadcast_stream_complete(@conversation, space_membership_id: running_run.speaker_space_membership_id)
        membership = SpaceMembership.find_by(id: running_run.speaker_space_membership_id)
        ConversationChannel.broadcast_typing(@conversation, membership: membership, active: false) if membership
      end
    end

    head :no_content
  end

  private

  def set_space
    @space = Current.user.spaces.find_by(id: params[:playground_id] || params[:space_id])
    return if @space

    redirect_to root_url, alert: t("playgrounds.not_found", default: "Playground not found")
  end

  def set_conversation
    @conversation = Conversation.find(params[:id])
    @space = @conversation.space

    membership = @space.space_memberships.active.find_by(user_id: Current.user.id, kind: "human")
    head :forbidden unless membership
  end

  def conversation_params
    params.fetch(:conversation, {}).permit(:title, :authors_note)
  end

  def branch_params
    params.permit(:message_id, :title, :visibility)
  end

  # Auto-branch when regenerating a non-tail assistant message.
  # Any non-tail regenerate will auto-branch to preserve timeline consistency.
  # Creates a branch from the target message, then regenerates the cloned message in the branch.
  # This preserves the original conversation timeline.
  def handle_non_tail_regenerate(target_message)
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: target_message,
      kind: "branch"
    ).call

    unless result.success?
      return redirect_to conversation_url(@conversation), alert: result.error
    end

    # Find the cloned target message in the new branch and regenerate it
    cloned_message = result.conversation.messages.find_by(origin_message_id: target_message.id)
    Conversation::RunPlanner.plan_regenerate!(conversation: result.conversation, target_message: cloned_message)

    redirect_to conversation_url(result.conversation)
  end

  # Handle last_turn regeneration mode for group chats.
  # Delegates to Conversation::LastTurnRegenerator service for robust handling of:
  # - Atomic message deletion (no partial deletes)
  # - Fork point protection (auto-branches when needed)
  # - Concurrent fork handling (rescues InvalidForeignKey)
  #
  # This mimics SillyTavern's group chat regeneration behavior.
  def handle_last_turn_regenerate
    result = Conversation::LastTurnRegenerator.new(
      conversation: @conversation,
      on_messages_deleted: ->(ids, conv) {
        ids.each { |id| Turbo::StreamsChannel.broadcast_remove_to(conv, :messages, target: "message_#{id}") }
        Message::Broadcasts.broadcast_group_queue_update(conv)
      }
    ).call

    case result.outcome
    when :success
      # Messages deleted successfully, queue generation
      Conversation::RunPlanner.plan_user_turn!(
        conversation: @conversation,
        trigger: "regenerate_turn"
      )

      respond_to do |format|
        format.turbo_stream { head :no_content }
        format.html { redirect_to conversation_url(@conversation) }
      end

    when :fallback_branch
      # Fork point detected (upfront or concurrent), created a branch
      Conversation::RunPlanner.plan_user_turn!(
        conversation: result.conversation,
        trigger: "regenerate_turn"
      )

      redirect_to conversation_url(result.conversation)

    when :nothing_to_regenerate
      # No user messages exist - nothing to regenerate
      # This preserves greeting messages and provides clear feedback.
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: render_to_string(
            partial: "shared/toast_turbo_stream",
            locals: {
              message: t("conversations.nothing_to_regenerate",
                         default: "Nothing to regenerate yet. Send a message first."),
              type: "warning",
              duration: 5000,
            }
          ), status: :unprocessable_entity
        end
        format.html do
          redirect_to conversation_url(@conversation),
                      alert: t("conversations.nothing_to_regenerate",
                               default: "Nothing to regenerate yet. Send a message first.")
        end
      end

    when :error
      # Unexpected error (e.g., branch creation failed)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: render_to_string(
            partial: "shared/toast_turbo_stream",
            locals: { message: result.error, type: "error", duration: 5000 }
          ), status: :unprocessable_entity
        end
        format.html { redirect_to conversation_url(@conversation), alert: result.error }
      end
    end
  end
end
