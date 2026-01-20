# frozen_string_literal: true

module Conversations
  module Messages
    # Controller for navigating message swipes (multiple AI response versions).
    #
    # Swipes allow users to cycle through different versions of an AI response
    # without changing the message's position in the conversation timeline.
    #
    # This controller is conversation-scoped to ensure users can only swipe messages
    # in conversations they are members of.
    #
    # @example Navigate to the previous swipe
    #   POST /conversations/:conversation_id/messages/:message_id/swipe?dir=left
    #
    # @example Navigate to the next swipe
    #   POST /conversations/:conversation_id/messages/:message_id/swipe?dir=right
    #
    class SwipesController < Conversations::ApplicationController
      include Authorization

      before_action :ensure_space_writable
      before_action :set_message

      # POST /conversations/:conversation_id/messages/:message_id/swipe
      #
      # Navigate to the previous (left) or next (right) swipe version.
      # Broadcasts the update to all conversation subscribers via Turbo Streams.
      #
      # Only the last message in a conversation can be swiped to preserve timeline
      # consistency (per SillyTavern Timelines behavior).
      #
      # @param dir [String] Direction to navigate: "left" or "right"
      # @return [void] Returns Turbo Stream response for the initiating client; broadcasts to other subscribers
      def create
        direction = params[:dir]&.to_sym

        unless %i[left right].include?(direction)
          return render_swipe_error(message: t("messages.swipe_invalid_direction", default: "Invalid swipe direction."))
        end

        # Only assistant messages can be swiped
        unless @message.assistant?
          return render_swipe_error(message: t("messages.swipe_assistant_only", default: "Only assistant messages can be swiped."))
        end

        # Only the last message can be swiped (to preserve timeline consistency)
        # @see TailMutationGuard
        guard = TailMutationGuard.new(@conversation)
        unless guard.tail?(@message)
          message = t(
            "messages.swipe_requires_branch",
            default: "Cannot swipe non-last message. Use 'Branch from here' first."
          )
          return render_swipe_error(message: message, flash_message: message)
        end

        # Ensure initial swipe exists before navigating
        @message.ensure_initial_swipe! if @message.message_swipes.empty?

        swipe = @message.select_swipe!(direction: direction)

        # Broadcast to all conversation subscribers (including current tab).
        @message.broadcast_update if swipe

        respond_to do |format|
          format.turbo_stream do
            if swipe
              render :create
            else
              head :ok
            end
          end
          format.html { head :no_content }
          format.any { head :no_content }
        end
      end

      private

      # Set message from params, scoped to the current conversation.
      #
      # @raise [ActiveRecord::RecordNotFound] if message not found in conversation
      def set_message
        @message = @conversation.messages.ui_visible.find(params[:message_id])
      end

      def render_swipe_error(message:, flash_message: nil)
        respond_to do |format|
          format.turbo_stream do
            render_toast_turbo_stream(message: message, type: "error", duration: 5000, status: :unprocessable_entity)
          end
          format.html do
            flash[:alert] = flash_message if flash_message
            head :unprocessable_entity
          end
          format.any { head :unprocessable_entity }
        end
      end
    end
  end
end
