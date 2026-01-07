# frozen_string_literal: true

module Messages
  module Swipes
    # Selects an existing swipe and syncs message fields.
    class Selector
      def self.select_by_direction!(message:, direction:)
        new(message: message).select_by_direction!(direction: direction)
      end

      def self.select_at!(message:, position:)
        new(message: message).select_at!(position: position)
      end

      def initialize(message:)
        @message = message
      end

      # @return [MessageSwipe, nil]
      def select_by_direction!(direction:)
        return nil unless message.active_message_swipe

        current_position = message.active_message_swipe.position
        target_position =
          case direction.to_sym
          when :left then current_position - 1
          when :right then current_position + 1
          else return nil
          end

        return nil if target_position.negative?

        target_swipe = message.message_swipes.find_by(position: target_position)
        return nil unless target_swipe

        apply_selection!(target_swipe)
      end

      # @return [MessageSwipe, nil]
      def select_at!(position:)
        target_swipe = message.message_swipes.find_by(position: position)
        return nil unless target_swipe

        apply_selection!(target_swipe)
      end

      private

      attr_reader :message

      def apply_selection!(target_swipe)
        message.update!(
          active_message_swipe: target_swipe,
          content: target_swipe.content,
          conversation_run_id: target_swipe.conversation_run_id
        )

        target_swipe
      end
    end
  end
end
