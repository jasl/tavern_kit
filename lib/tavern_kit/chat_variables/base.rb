# frozen_string_literal: true

module TavernKit
  module ChatVariables
    # Abstract base class for chat variable storage.
    #
    # This class defines the interface contract that all ChatVariables implementations
    # must follow. Subclass this to create custom storage backends (e.g., Redis,
    # database, file-based).
    #
    # Conventions:
    # - Keys are treated as strings (whitespace-trimmed); blank keys are invalid.
    # - Missing keys should return nil from {#get}.
    # - Values are stored as strings for macro substitution compatibility.
    class Base
      include Enumerable

      # ========================================
      # Abstract methods (MUST implement)
      # ========================================

      # Get a variable value.
      #
      # @param key [String, Symbol]
      # @return [String, nil]
      def get(key)
        raise NotImplementedError, "#{self.class} must implement #get"
      end
      alias [] get

      # Set a variable value.
      #
      # @param key [String, Symbol]
      # @param value [Object] value to store (will be stringified)
      # @return [Object] the original value (for chaining semantics)
      def set(key, value)
        raise NotImplementedError, "#{self.class} must implement #set"
      end
      alias []= set

      # Delete a variable.
      #
      # @param key [String, Symbol]
      # @return [Object, nil] backend-defined (often the removed value or count)
      def delete(key)
        raise NotImplementedError, "#{self.class} must implement #delete"
      end

      # Iterate over all stored key/value pairs.
      #
      # @yield [String, String] key/value
      # @return [Enumerator] if no block given
      def each(&block)
        raise NotImplementedError, "#{self.class} must implement #each"
      end

      # Return number of variables.
      #
      # @return [Integer]
      def size
        raise NotImplementedError, "#{self.class} must implement #size"
      end
      alias length size

      # Clear all variables.
      #
      # @return [self]
      def clear
        raise NotImplementedError, "#{self.class} must implement #clear"
      end

      # ========================================
      # Default implementations (MAY override)
      # ========================================

      # Check if a variable key exists.
      #
      # @param key [String, Symbol]
      # @return [Boolean]
      def key?(key)
        !get(key).nil?
      end

      # Convert variables to a plain hash.
      #
      # @return [Hash{String=>String}]
      def to_h
        each_with_object({}) do |(k, v), acc|
          acc[k.to_s] = v.to_s
        end
      end

      # Duplication support (useful for forking variable scopes).
      #
      # @return [Base]
      def dup
        self.class.new(to_h)
      end

      protected

      # Coerce a key to a normalized string.
      #
      # @param key [String, Symbol] the key to coerce
      # @return [String] normalized trimmed string
      def coerce_key!(key)
        k = key.to_s.strip
        raise ArgumentError, "variable key cannot be empty" if k.empty?

        k
      end

      # Stringify a value for storage.
      #
      # @param value [Object, nil] value to stringify
      # @return [String]
      def stringify_value(value)
        value.nil? ? "" : value.to_s
      end
    end
  end
end
