# frozen_string_literal: true

module Messages
  module Swipes
    # Adds a new swipe version to a message and sets it as active.
    class Adder
      MAX_RETRIES = 5

      def self.execute(message:, content:, metadata: {}, conversation_run_id: nil)
        new(message: message, content: content, metadata: metadata, conversation_run_id: conversation_run_id).execute
      end

      def initialize(message:, content:, metadata:, conversation_run_id:)
        @message = message
        @content = content
        @metadata = metadata
        @conversation_run_id = conversation_run_id
      end

      def execute
        call
      end

      # @return [MessageSwipe]
      def call
        InitialSwipeEnsurer.execute(message: message) unless message.message_swipes.exists?

        retries = 0
        begin
          swipe = nil

          MessageSwipe.transaction(requires_new: true) do
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
          end

          swipe
        rescue ActiveRecord::RecordNotUnique
          retries += 1
          raise if retries >= MAX_RETRIES

          message.message_swipes.reset
          retry
        rescue ActiveRecord::RecordInvalid => e
          # Rails uniqueness validation may fire before DB unique index
          raise unless position_conflict?(e)

          retries += 1
          raise if retries >= MAX_RETRIES

          message.message_swipes.reset
          retry
        end
      end

      private :call

      private

      attr_reader :message, :content, :metadata, :conversation_run_id

      def position_conflict?(error)
        return false unless error.record

        error.record.errors.details.fetch(:position, []).any? { |detail| detail[:error] == :taken }
      end
    end
  end
end
