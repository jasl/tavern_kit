# frozen_string_literal: true

module Conversations
  module Messages
    # Controller for toggling message visibility in prompt context.
    #
    # Allows users to exclude specific messages from the AI context without
    # deleting them. Excluded messages remain visible in the chat UI but are
    # not sent to the LLM during prompt building.
    #
    # This mirrors SillyTavern's "Included/Excluded in context" toggle.
    #
    # @example Toggle message visibility
    #   PATCH /conversations/:conversation_id/messages/:message_id/visibility
    #
    class VisibilitiesController < Conversations::ApplicationController
      include Authorization

      before_action :ensure_space_writable
      before_action :set_message

      # PATCH /conversations/:conversation_id/messages/:message_id/visibility
      #
      # Toggle whether this message is included in the AI prompt context.
      # Broadcasts the update to all conversation subscribers via Turbo Streams.
      #
      # @return [void] Returns Turbo Stream response; DOM updates via broadcast
      def update
        @message.toggle_prompt_visibility!
        @message.broadcast_update

        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to conversation_path(@conversation) }
        end
      end

      private

      # Set message from params, scoped to the current conversation.
      #
      # @raise [ActiveRecord::RecordNotFound] if message not found in conversation
      def set_message
        @message = @conversation.messages.ui_visible.find(params[:message_id])
      end
    end
  end
end
