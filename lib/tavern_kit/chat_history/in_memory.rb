# frozen_string_literal: true

require "json"

module TavernKit
  module ChatHistory
    # Default in-memory implementation of ChatHistory.
    #
    # Stores messages in a simple Ruby Array. Suitable for most use cases
    # where history doesn't need to persist across processes.
    #
    # @example Basic usage
    #   history = TavernKit::ChatHistory::InMemory.new
    #   history << TavernKit::Prompt::Message.new(role: :user, content: "Hello")
    #   history << TavernKit::Prompt::Message.new(role: :assistant, content: "Hi!")
    #   history.size  # => 2
    #
    # @example Initialize with existing messages
    #   history = TavernKit::ChatHistory::InMemory.new([
    #     TavernKit::Prompt::Message.new(role: :user, content: "Hello"),
    #     TavernKit::Prompt::Message.new(role: :assistant, content: "Hi!")
    #   ])
    #
    # @example Fork a conversation
    #   branch = history.dup
    #   branch << TavernKit::Prompt::Message.new(role: :user, content: "Different path...")
    #   history.size  # => 2 (unchanged)
    #   branch.size   # => 3
    #
    # @example Persistence with dump/load
    #   history = TavernKit::ChatHistory::InMemory.new
    #   history << TavernKit::Prompt::Message.new(role: :user, content: "Hello")
    #   history << TavernKit::Prompt::Message.new(role: :assistant, content: "Hi!")
    #
    #   # Save to JSON string
    #   json = history.dump
    #
    #   # Load from JSON string
    #   restored = TavernKit::ChatHistory::InMemory.load(json)
    #
    #   # Save to file
    #   history.dump_to_file("chat.json")
    #
    #   # Load from file
    #   restored = TavernKit::ChatHistory::InMemory.load_from_file("chat.json")
    #
    class InMemory < Base
      # Create a new in-memory chat history.
      #
      # @param messages [Array<Prompt::Message>] initial messages (optional)
      def initialize(messages = [])
        @messages = []
        Array(messages).each { |m| append(m) }
      end

      # Append a message to the history.
      #
      # @param message [Prompt::Message] message to append
      # @return [self] for chaining
      def append(message)
        unless message.is_a?(TavernKit::Prompt::Message)
          raise ArgumentError, "message must be a TavernKit::Prompt::Message, got: #{message.class}"
        end

        @messages << message
        self
      end
      alias << append

      # Iterate over all messages.
      #
      # @yield [Prompt::Message] each message in order
      # @return [Enumerator] if no block given
      def each(&block)
        return enum_for(:each) unless block_given?

        @messages.each(&block)
      end

      # Return the number of messages.
      #
      # @return [Integer] message count
      def size
        @messages.size
      end
      alias length size

      # Remove all messages.
      #
      # @return [self] for chaining
      def clear
        @messages.clear
        self
      end

      # Check if history is empty.
      # Optimized to avoid iteration.
      #
      # @return [Boolean]
      def empty?
        @messages.empty?
      end

      # Get the last message(s).
      # Optimized to avoid full iteration.
      #
      # @param n [Integer, nil] number of messages to return (nil = single message)
      # @return [Prompt::Message, Array<Prompt::Message>, nil]
      def last(n = nil)
        n ? @messages.last(n) : @messages.last
      end

      # Get the first message(s).
      # Optimized to avoid full iteration.
      #
      # @param n [Integer, nil] number of messages to return (nil = single message)
      # @return [Prompt::Message, Array<Prompt::Message>, nil]
      def first(n = nil)
        n ? @messages.first(n) : @messages.first
      end

      # Convert to array.
      #
      # @return [Array<Prompt::Message>] copy of internal array
      def to_a
        @messages.dup
      end

      # Get message at index.
      #
      # @param index [Integer] message index
      # @return [Prompt::Message, nil]
      def [](index)
        @messages[index]
      end

      # Deep copy support for forking conversations.
      #
      # @return [InMemory] independent copy
      def initialize_copy(original)
        super
        @messages = original.instance_variable_get(:@messages).dup
      end

      # ========================================
      # Serialization / Persistence
      # ========================================

      # Serialize the history to a JSON string.
      #
      # @param pretty [Boolean] whether to pretty-print the JSON (default: false)
      # @return [String] JSON string
      def dump(pretty: false)
        data = @messages.map(&:to_serializable_hash)
        pretty ? JSON.pretty_generate(data) : JSON.generate(data)
      end

      # Serialize the history to a Hash array (without JSON encoding).
      #
      # @return [Array<Hash>] array of message hashes
      def to_a_hashes
        @messages.map(&:to_serializable_hash)
      end

      # Save the history to a JSON file.
      #
      # @param path [String] file path
      # @param pretty [Boolean] whether to pretty-print the JSON (default: true)
      # @return [self] for chaining
      def dump_to_file(path, pretty: true)
        File.write(path, dump(pretty: pretty))
        self
      end

      class << self
        # Load history from a JSON string.
        #
        # @param json_string [String] JSON string
        # @return [InMemory] new history instance
        def load(json_string)
          data = JSON.parse(json_string, symbolize_names: true)
          from_hashes(data)
        end

        # Load history from a JSON file.
        #
        # @param path [String] file path
        # @return [InMemory] new history instance
        def load_from_file(path)
          load(File.read(path))
        end

        # Create history from an array of hashes.
        #
        # @param hashes [Array<Hash>] array of message hashes
        # @return [InMemory] new history instance
        def from_hashes(hashes)
          messages = hashes.map { |h| deserialize_message(h) }
          new(messages)
        end

        private

        def deserialize_message(hash)
          TavernKit::Prompt::Message.new(
            role: hash[:role].to_sym,
            content: hash[:content] || "",
            name: hash[:name],
            swipes: hash[:swipes],
            swipe_id: hash[:swipe_id],
            send_date: hash[:send_date]
          )
        end
      end
    end
  end
end
