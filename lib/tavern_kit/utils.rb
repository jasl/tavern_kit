# frozen_string_literal: true

module TavernKit
  module Utils
    module_function

    # Deep-convert keys to symbols.
    def deep_symbolize_keys(value)
      case value
      when Array then value.map { |v| deep_symbolize_keys(v) }
      when Hash
        value.transform_keys { |k| k.respond_to?(:to_sym) ? k.to_sym : k }
              .transform_values { |v| deep_symbolize_keys(v) }
      else value
      end
    end

    # Deep-convert keys to strings.
    def deep_stringify_keys(value)
      case value
      when Array then value.map { |v| deep_stringify_keys(v) }
      when Hash
        value.transform_keys(&:to_s).transform_values { |v| deep_stringify_keys(v) }
      else value
      end
    end

    # Returns nil if value is blank, otherwise returns the value.
    def presence(value)
      str = value.to_s.strip
      str.empty? ? nil : value
    end

    # Format a string with {0}, {1}, ... placeholders.
    def string_format(format, *args)
      format.to_s.gsub(/\{(\d+)\}/) do |match|
        idx = Regexp.last_match(1).to_i
        args[idx]&.to_s || match
      end
    end

    # Flexible hash accessor for parsing mixed-key hashes (string/symbol, camelCase/snake_case).
    # Simplifies from_hash methods by providing a clean interface.
    class HashAccessor
      TRUE_STRINGS = %w[1 true yes y on].freeze

      def self.wrap(hash)
        new(hash)
      end

      def initialize(hash)
        @hash = hash.is_a?(Hash) ? hash : {}
      end

      # Check if underlying data is a valid hash.
      def valid?
        !@hash.empty?
      end

      # Fetch value by trying multiple keys (string and symbol variants).
      def [](*keys)
        keys.each do |key|
          [key.to_s, key.to_sym].each do |k|
            return @hash[k] if @hash.key?(k)
          end
        end
        nil
      end

      # Fetch with a default value.
      def fetch(*keys, default: nil)
        self[*keys] || default
      end

      # Fetch a nested value (e.g., from extensions).
      def dig(*path)
        current = @hash
        path.each do |key|
          return nil unless current.is_a?(Hash)
          current = current[key.to_s] || current[key.to_sym]
        end
        current
      end

      # Fetch boolean value with fallback to extensions path.
      def bool(*keys, ext_key: nil, default: false)
        val = self[*keys]
        val = dig(:extensions, ext_key) if val.nil? && ext_key
        to_bool(val, default)
      end

      # Fetch integer value with fallback to extensions path.
      def int(*keys, ext_key: nil, default: 0)
        val = self[*keys]
        val = dig(:extensions, ext_key) if val.nil? && ext_key
        val.nil? ? default : val.to_i
      end

      # Fetch optional positive integer (returns nil for zero/negative).
      def positive_int(*keys, ext_key: nil)
        val = self[*keys]
        val = dig(:extensions, ext_key) if val.nil? && ext_key
        return nil if val.nil?

        i = val.to_i
        i.positive? ? i : nil
      end

      # Fetch string value.
      def str(*keys, ext_key: nil, default: nil)
        val = self[*keys]
        val = dig(:extensions, ext_key) if val.nil? && ext_key
        val.nil? ? default : val.to_s
      end

      # Fetch string, return nil if blank.
      def presence(*keys, ext_key: nil)
        val = str(*keys, ext_key: ext_key)
        val && !val.strip.empty? ? val : nil
      end

      private

      def to_bool(val, default)
        return default if val.nil?
        return val if val == true || val == false

        TRUE_STRINGS.include?(val.to_s.strip.downcase) || default
      end
    end
  end
end
