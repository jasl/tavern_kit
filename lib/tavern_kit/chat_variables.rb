# frozen_string_literal: true

require_relative "chat_variables/base"
require_relative "chat_variables/in_memory"

module TavernKit
  # ChatVariables provides type-safe storage for SillyTavern-style *chat-local* variable macros.
  #
  # The module includes:
  # - `Base`: Abstract base class defining the interface contract
  # - `InMemory`: Default Hash-backed implementation
  #
  # Developers can implement custom storage backends by subclassing `Base`
  # (e.g., Redis, database, file-based storage).
  #
  # @example Basic usage
  #   vars = TavernKit::ChatVariables.new
  #   vars["x"] = "foo"
  #   vars["x"] # => "foo"
  #
  # @example With TavernKit.build (persist across builds)
  #   store = TavernKit::ChatVariables.new
  #   plan = TavernKit.build do
  #     character my_character
  #     user my_user
  #     preset my_preset
  #     macro_vars local_store: store
  #     message "Hello!"
  #   end
  #
  # @example Custom storage
  #   class RedisChatVariables < TavernKit::ChatVariables::Base
  #     def initialize(redis_key, redis: Redis.current)
  #       @redis = redis
  #       @key = redis_key
  #     end
  #
  #     def get(key)
  #       @redis.hget(@key, coerce_key!(key))
  #     end
  #
  #     def set(key, value)
  #       @redis.hset(@key, coerce_key!(key), stringify_value(value))
  #       value
  #     end
  #
  #     def delete(key)
  #       @redis.hdel(@key, coerce_key!(key))
  #     end
  #
  #     def each
  #       return enum_for(:each) unless block_given?
  #
  #       @redis.hgetall(@key).each do |k, v|
  #         yield k, v
  #       end
  #     end
  #
  #     def size
  #       @redis.hlen(@key)
  #     end
  #
  #     def clear
  #       @redis.del(@key)
  #       self
  #     end
  #   end
  #
  module ChatVariables
    class << self
      # Create a new ChatVariables store with the default InMemory implementation.
      #
      # @param store [Hash, nil] optional backing hash (primarily for interoperability)
      # @return [InMemory]
      def new(store = nil)
        InMemory.new(store)
      end

      # Wrap an input into a ChatVariables store if needed.
      #
      # @param input [ChatVariables::Base, Hash, nil]
      # @return [ChatVariables::Base]
      # @raise [ArgumentError] if input type is not supported
      def wrap(input)
        case input
        when Base
          input
        when Hash
          InMemory.new(input)
        when nil
          InMemory.new
        else
          raise ArgumentError, "variables must be ChatVariables::Base or Hash, got: #{input.class}"
        end
      end

      # Create an InMemory store from a Hash.
      # Alias for {wrap}, provided for clarity.
      #
      # @param hash [Hash]
      # @return [InMemory]
      def from_hash(hash)
        InMemory.new(hash)
      end
    end
  end
end
