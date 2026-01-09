# frozen_string_literal: true

module Conversations
  # Controller for creating checkpoint snapshots of conversations.
  #
  # Checkpoints clone a conversation up to a specific message without switching
  # away from the current conversation. This allows users to "save a node" in
  # long roleplay sessions without interrupting their flow.
  #
  # Unlike branches, which redirect to the new conversation, checkpoints stay
  # on the current page and show a toast notification with a link.
  #
  # @see Conversations::Forker for the cloning logic
  class CheckpointsController < Conversations::ApplicationController
    include Authorization

    before_action :ensure_space_writable

    # POST /conversations/:conversation_id/checkpoints
    #
    # Creates a checkpoint (snapshot) from a specific message. The user stays
    # on the current conversation and receives a toast with a link to the
    # new checkpoint.
    #
    # Parameters:
    #   message_id: ID of the message to checkpoint from (required)
    #   title: Title for the checkpoint (optional, defaults to "Checkpoint")
    #
    # @return [void] Returns Turbo Stream response with toast notification
    def create
      message = @conversation.messages.find_by(id: checkpoint_params[:message_id])

      unless message
        return respond_to do |format|
          format.turbo_stream { head :not_found }
          format.html { redirect_to conversation_url(@conversation), alert: t("checkpoints.message_not_found", default: "Message not found") }
        end
      end

      result = Conversations::Forker.new(
        parent_conversation: @conversation,
        fork_from_message: message,
        kind: "checkpoint",
        title: checkpoint_title(message),
        visibility: "shared"
      ).call

      if result.success?
        @checkpoint = result.conversation
        @async = result.async?
        respond_to do |format|
          format.turbo_stream
          format.html do
            if result.async?
              redirect_to conversation_url(@conversation), notice: t("checkpoints.creating", default: "Creating checkpoint...")
            else
              redirect_to conversation_url(@conversation), notice: t("checkpoints.created", default: "Checkpoint saved")
            end
          end
        end
      else
        respond_to do |format|
          format.turbo_stream { head :unprocessable_entity }
          format.html { redirect_to conversation_url(@conversation), alert: result.error }
        end
      end
    end

    private

    def checkpoint_params
      params.permit(:message_id, :title)
    end

    # Generate a default title for the checkpoint if none provided.
    #
    # @param message [Message] the message being checkpointed from
    # @return [String] the checkpoint title
    def checkpoint_title(message)
      if checkpoint_params[:title].present?
        checkpoint_params[:title]
      else
        t("checkpoints.default_title",
          default: "Checkpoint at message #%{seq}",
          seq: message.seq)
      end
    end
  end
end
