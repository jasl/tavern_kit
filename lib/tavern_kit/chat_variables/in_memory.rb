# frozen_string_literal: true

require "json"

module TavernKit
  module ChatVariables
    # Default in-memory implementation of ChatVariables.
    #
    # Stores variables in a Ruby Hash. Suitable for most use cases
    # where variables don't need to persist across processes.
    #
    # @example Persistence with dump/load
    #   vars = TavernKit::ChatVariables::InMemory.new
    #   vars["foo"] = "bar"
    #   vars["count"] = "42"
    #
    #   # Save to JSON string
    #   json = vars.dump
    #
    #   # Load from JSON string
    #   restored = TavernKit::ChatVariables::InMemory.load(json)
    #
    #   # Save to file
    #   vars.dump_to_file("variables.json")
    #
    #   # Load from file
    #   restored = TavernKit::ChatVariables::InMemory.load_from_file("variables.json")
    #
    class InMemory < Base
      # Create a new in-memory variables store.
      #
      # @param store [Hash, nil] optional backing hash (if provided, it will be mutated in-place)
      def initialize(store = nil)
        @store = store.is_a?(Hash) ? store : {}
      end

      # Get a variable value.
      #
      # @param key [String, Symbol]
      # @return [String, nil]
      def get(key)
        k = coerce_key!(key)
        return @store[k] if @store.key?(k)

        sym = k.to_sym
        return @store[sym] if @store.key?(sym)

        nil
      end
      alias [] get

      # Set a variable value.
      #
      # @param key [String, Symbol]
      # @param value [Object]
      # @return [Object] the original value
      def set(key, value)
        k = coerce_key!(key)
        v = stringify_value(value)

        @store[k] = v

        sym = k.to_sym
        @store[sym] = v if @store.key?(sym)

        value
      end
      alias []= set

      # Delete a variable.
      #
      # @param key [String, Symbol]
      # @return [Object, nil] removed value (best-effort)
      def delete(key)
        k = coerce_key!(key)

        removed = nil
        removed = @store.delete(k) if @store.key?(k)

        sym = k.to_sym
        removed_sym = @store.delete(sym) if @store.key?(sym)

        removed.nil? ? removed_sym : removed
      end

      # Iterate over all variables.
      #
      # @yield [String, String]
      # @return [Enumerator] if no block given
      def each(&block)
        return enum_for(:each) unless block_given?

        # Prefer string keys; hide symbol duplicates if both exist.
        seen = {}
        @store.each do |k, v|
          next unless k.is_a?(String) || k.is_a?(Symbol)

          key_str = k.to_s
          next if seen[key_str]

          seen[key_str] = true
          yield key_str, v.to_s
        end
      end

      # Return the number of variables.
      #
      # @return [Integer]
      def size
        each.count
      end
      alias length size

      # Clear all variables.
      #
      # @return [self]
      def clear
        @store.clear
        self
      end

      # ========================================
      # Serialization / Persistence
      # ========================================

      # Serialize the variables to a JSON string.
      #
      # @param pretty [Boolean] whether to pretty-print the JSON (default: false)
      # @return [String] JSON string
      def dump(pretty: false)
        data = to_h
        pretty ? JSON.pretty_generate(data) : JSON.generate(data)
      end

      # Save the variables to a JSON file.
      #
      # @param path [String] file path
      # @param pretty [Boolean] whether to pretty-print the JSON (default: true)
      # @return [self] for chaining
      def dump_to_file(path, pretty: true)
        File.write(path, dump(pretty: pretty))
        self
      end

      class << self
        # Load variables from a JSON string.
        #
        # @param json_string [String] JSON string
        # @return [InMemory] new variables instance
        def load(json_string)
          data = JSON.parse(json_string, symbolize_names: false)
          new(data)
        end

        # Load variables from a JSON file.
        #
        # @param path [String] file path
        # @return [InMemory] new variables instance
        def load_from_file(path)
          load(File.read(path))
        end
      end
    end
  end
end
