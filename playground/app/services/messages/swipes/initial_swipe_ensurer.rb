# frozen_string_literal: true

module Messages
  module Swipes
    # Ensures a message has an initial swipe at position 0.
    class InitialSwipeEnsurer
      def self.execute(message:)
        new(message: message).execute
      end

      def initialize(message:)
        @message = message
      end

      def execute
        call
      end

      # @return [MessageSwipe]
      def call
        return message.message_swipes.find_by(position: 0) if message.message_swipes.exists?

        swipe = nil

        MessageSwipe.transaction(requires_new: true) do
          swipe = message.message_swipes.create!(
            position: 0,
            content: message.content,
            metadata: message.metadata || {},
            conversation_run_id: message.conversation_run_id
          )
          message.update!(active_message_swipe: swipe)
        end

        swipe
      rescue ActiveRecord::RecordNotUnique
        # Another request created position 0 first - return it
        message.message_swipes.find_by(position: 0)
      end

      private :call

      private

      attr_reader :message
    end
  end
end
