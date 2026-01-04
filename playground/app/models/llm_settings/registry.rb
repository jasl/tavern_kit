# frozen_string_literal: true

module LLMSettings
  # Registry for managing all settings schema classes.
  #
  # This provides a central place to access all schema definitions
  # and generate the bundled JSON Schema output.
  #
  class Registry
    class << self
      def schemas
        @schemas ||= {}
      end

      def register(key, klass)
        schemas[key.to_sym] = klass
      end

      def resolve(key)
        schemas.fetch(key.to_sym)
      end

      def all
        schemas.values
      end

      def keys
        schemas.keys
      end

      def clear!
        @schemas = {}
      end
    end
  end
end
