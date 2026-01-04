# frozen_string_literal: true

require_relative "chat_history/base"
require_relative "chat_history/in_memory"

module TavernKit
  # ChatHistory provides storage for chat messages.
  #
  # Supports the default InMemory implementation or custom backends (database, Redis, etc.).
  #
  # @example Basic usage
  #   history = TavernKit::ChatHistory.new
  #   history << TavernKit::Prompt::Message.new(role: :user, content: "Hello")
  #
  # @example Wrap existing messages
  #   history = TavernKit::ChatHistory.wrap([
  #     { role: :user, content: "Hello" },
  #     { role: :assistant, content: "Hi!" }
  #   ])
  #
  module ChatHistory
    class << self
      # Create a new ChatHistory with the default InMemory implementation.
      def new(messages = [])
        InMemory.new(messages)
      end

      # Alias for new.
      def from_array(messages)
        InMemory.new(messages)
      end

      # Wrap an input into a ChatHistory if needed.
      def wrap(input)
        return InMemory.new unless input
        return input if input.respond_to?(:each) && input.respond_to?(:append) && !input.is_a?(Array)

        InMemory.new(Array(input).map { |m| coerce_message(m) })
      end

      private

      # Convert hash to Message using duck typing.
      def coerce_message(value)
        return value if value.respond_to?(:role) && value.respond_to?(:content)

        h = Utils::HashAccessor.new(value)
        TavernKit::Prompt::Message.new(
          role: Coerce.role(h[:role], default: :user),
          content: (h[:content] || "").to_s,
          name: h[:name]&.to_s,
          swipes: h[:swipes],
          swipe_id: h[:swipe_id, :swipeId]&.to_i,
          send_date: h[:send_date, :sendDate],
        )
      end
    end
  end
end
