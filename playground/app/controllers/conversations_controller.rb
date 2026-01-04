# frozen_string_literal: true

# Controller for conversation timelines.
class ConversationsController < ApplicationController
  include Authorization
  include TrackedSpaceVisit

  layout "chat", only: :show

  before_action :set_space, only: %i[create]
  before_action :set_conversation, only: %i[show regenerate branch]
  before_action :ensure_space_writable, only: %i[regenerate]
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
  end

  # POST /conversations/:id/regenerate
  # Triggers regeneration of the last assistant message (or specified message).
  #
  # If the target message is NOT the last assistant message, auto-branches to preserve
  # timeline consistency (per SillyTavern Timelines behavior).
  def regenerate
    target_message = if params[:message_id].present?
      @conversation.messages.find(params[:message_id])
    else
      @conversation.messages.where(role: "assistant").order(seq: :desc).first
    end

    return redirect_to conversation_url(@conversation), alert: t("messages.no_message_to_regenerate", default: "No message to regenerate.") unless target_message

    # Check if regenerating a non-last assistant message (would cause timeline inconsistency)
    last_assistant = @conversation.messages.where(role: "assistant").order(seq: :desc).first
    if target_message.id != last_assistant&.id
      return handle_non_tail_regenerate(target_message)
    end

    Conversation::RunPlanner.plan_regenerate!(conversation: @conversation, target_message: target_message)

    respond_to do |format|
      format.turbo_stream { head :ok }
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
    params.fetch(:conversation, {}).permit(:title)
  end

  def branch_params
    params.permit(:message_id, :title, :visibility)
  end

  # Auto-branch when regenerating a non-last assistant message.
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
end
