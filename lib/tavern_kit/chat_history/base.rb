# frozen_string_literal: true

module TavernKit
  module ChatHistory
    # Abstract base class for chat history storage.
    #
    # This class defines the interface contract that all ChatHistory implementations
    # must follow. Subclass this to create custom storage backends (e.g., database,
    # Redis, file-based).
    #
    # @example Implementing a custom storage
    #   class RedisChatHistory < TavernKit::ChatHistory::Base
    #     def initialize(redis_key, redis: Redis.current)
    #       @redis = redis
    #       @key = redis_key
    #     end
    #
    #     def append(message)
    #       @redis.rpush(@key, message.to_h.to_json)
    #       self
    #     end
    #
    #     def each
    #       @redis.lrange(@key, 0, -1).each do |json|
    #         yield TavernKit::Prompt::Message.new(**JSON.parse(json, symbolize_names: true))
    #       end
    #     end
    #
    #     def size
    #       @redis.llen(@key)
    #     end
    #
    #     def clear
    #       @redis.del(@key)
    #       self
    #     end
    #   end
    #
    class Base
      include Enumerable

      # ========================================
      # Abstract methods (MUST implement)
      # ========================================

      # Append a message to the history.
      #
      # @param message [Prompt::Message] message to append
      # @return [self] for chaining
      # @raise [NotImplementedError] if not implemented by subclass
      def append(message)
        raise NotImplementedError, "#{self.class} must implement #append"
      end

      # Alias for append.
      alias << append

      # Iterate over all messages.
      #
      # @yield [Prompt::Message] each message in order
      # @raise [NotImplementedError] if not implemented by subclass
      def each(&block)
        raise NotImplementedError, "#{self.class} must implement #each"
      end

      # Return the number of messages.
      #
      # @return [Integer] message count
      # @raise [NotImplementedError] if not implemented by subclass
      def size
        raise NotImplementedError, "#{self.class} must implement #size"
      end
      alias length size

      # Remove all messages.
      #
      # @return [self] for chaining
      # @raise [NotImplementedError] if not implemented by subclass
      def clear
        raise NotImplementedError, "#{self.class} must implement #clear"
      end

      # ========================================
      # Default implementations (MAY override)
      # ========================================

      # Check if history is empty.
      #
      # @return [Boolean]
      def empty?
        size.zero?
      end

      # Get the last message(s).
      #
      # @param n [Integer, nil] number of messages to return (nil = single message)
      # @return [Prompt::Message, Array<Prompt::Message>, nil]
      def last(n = nil)
        arr = to_a
        n ? arr.last(n) : arr.last
      end

      # Get the first message(s).
      #
      # @param n [Integer, nil] number of messages to return (nil = single message)
      # @return [Prompt::Message, Array<Prompt::Message>, nil]
      def first(n = nil)
        arr = to_a
        n ? arr.first(n) : arr.first
      end

      # Count messages matching a condition.
      #
      # @yield [Prompt::Message] block to evaluate
      # @return [Integer]
      def count(&block)
        block ? super(&block) : size
      end

      # ========================================
      # Convenience methods for prompt building
      # ========================================

      # Count user messages in the history.
      # Used for Author's Note frequency calculation.
      #
      # @return [Integer]
      def user_message_count
        count { |m| m.role == :user }
      end

      # Count assistant messages in the history.
      #
      # @return [Integer]
      def assistant_message_count
        count { |m| m.role == :assistant }
      end

      # Count system messages in the history.
      #
      # @return [Integer]
      def system_message_count
        count { |m| m.role == :system }
      end

      # Alias for user_message_count.
      # Represents the number of "turns" in the conversation.
      #
      # @return [Integer]
      def turn_count
        user_message_count
      end

      # ========================================
      # Duplication support (for forking chats)
      # ========================================

      # Create an independent copy of this history.
      # Subclasses should override if they need custom duplication logic.
      #
      # @return [Base] a new instance with copied messages
      def dup
        self.class.new(to_a)
      end

      # ========================================
      # Future extension points (placeholders)
      # ========================================

      # Compress the history (e.g., summarize old messages).
      # Subclasses may implement this with LLM integration.
      #
      # @param options [Hash] compression options
      # @return [self]
      # @raise [NotImplementedError] if not implemented
      def compress(**options)
        raise NotImplementedError, "#{self.class} does not support #compress"
      end

      # Summarize the history into a single text.
      # Subclasses may implement this with LLM integration.
      #
      # @param options [Hash] summarization options
      # @return [String] summary text
      # @raise [NotImplementedError] if not implemented
      def summarize(**options)
        raise NotImplementedError, "#{self.class} does not support #summarize"
      end

      # ========================================
      # Type coercion is handled at higher-level entry points (e.g., TavernKit.build,
      # TavernKit.to_messages, and ChatHistory.wrap).
    end
  end
end
