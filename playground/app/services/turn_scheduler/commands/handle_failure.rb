# frozen_string_literal: true

module TurnScheduler
  module Commands
    # Handles a failed generation attempt.
    #
    # When AI generation fails, this command updates the scheduling state
    # and broadcasts appropriate error messages.
    #
    class HandleFailure
      def self.call(conversation:, run:, error:)
        new(conversation, run, error).call
      end

      def initialize(conversation, run, error)
        @conversation = conversation
        @run = run
        @error = error
        @space = conversation.space
      end

      # @return [Boolean] true if handled successfully
      def call
        @conversation.update!(scheduling_state: "failed")

        broadcast_error
        Broadcasts.queue_updated(@conversation)

        true
      end

      private

      def broadcast_error
        error_message = extract_error_message

        ConversationChannel.broadcast_to(
          @conversation,
          type: "generation_failed",
          run_id: @run.id,
          error: error_message
        )

        # Also broadcast as alert for UI display
        Turbo::StreamsChannel.broadcast_prepend_to(
          @conversation, :messages,
          target: "alerts",
          partial: "shared/alert",
          locals: {
            type: "error",
            message: "Generation failed: #{error_message}",
          }
        )
      end

      def extract_error_message
        case @error
        when Hash
          @error["message"] || @error["error"] || "Unknown error"
        when StandardError
          @error.message
        else
          @error.to_s
        end
      end
    end
  end
end
