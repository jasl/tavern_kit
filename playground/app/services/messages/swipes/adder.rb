# frozen_string_literal: true

module Messages
  module Swipes
    # Adds a new swipe version to a message and sets it as active.
    class Adder
      MAX_RETRIES = 5

      def self.call(message:, content:, metadata: {}, conversation_run_id: nil)
        new(message: message, content: content, metadata: metadata, conversation_run_id: conversation_run_id).call
      end

      def initialize(message:, content:, metadata:, conversation_run_id:)
        @message = message
        @content = content
        @metadata = metadata
        @conversation_run_id = conversation_run_id
      end

      # @return [MessageSwipe]
      def call
        InitialSwipeEnsurer.call(message: message) if message.message_swipes.empty?

        retries = 0
        begin
          next_position = (message.message_swipes.maximum(:position) || -1) + 1

          swipe = message.message_swipes.create!(
            position: next_position,
            content: content,
            metadata: metadata,
            conversation_run_id: conversation_run_id
          )

          message.update!(
            active_message_swipe: swipe,
            content: content,
            conversation_run_id: conversation_run_id
          )

          swipe
        rescue ActiveRecord::RecordNotUnique
          retries += 1
          raise if retries >= MAX_RETRIES

          message.message_swipes.reload
          retry
        rescue ActiveRecord::RecordInvalid => e
          # Rails uniqueness validation may fire before DB unique index
          raise unless e.message.include?("Position")

          retries += 1
          raise if retries >= MAX_RETRIES

          message.message_swipes.reload
          retry
        end
      end

      private

      attr_reader :message, :content, :metadata, :conversation_run_id
    end
  end
end
