# frozen_string_literal: true

module Messages
  module Swipes
    # Ensures a message has an initial swipe at position 0.
    class InitialSwipeEnsurer
      def self.call(message:)
        new(message: message).call
      end

      def initialize(message:)
        @message = message
      end

      # @return [MessageSwipe]
      def call
        return message.message_swipes.first if message.message_swipes.any?

        swipe = message.message_swipes.create!(
          position: 0,
          content: message.content,
          metadata: message.metadata || {},
          conversation_run_id: message.conversation_run_id
        )
        message.update!(active_message_swipe: swipe)
        swipe
      rescue ActiveRecord::RecordNotUnique
        # Another request created position 0 first - return it
        message.message_swipes.reload.first
      end

      private

      attr_reader :message
    end
  end
end
