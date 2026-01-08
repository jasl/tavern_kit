# frozen_string_literal: true

module TavernKit
  module Macro
    # A small, registry-driven macro preprocessing pipeline.
    #
    # This is an optional hook for host apps to run regex-level rewrites on the
    # raw input string before macro substitution.
    #
    # Note: core ST directives like `{{trim}}` and `{{// ... }}` are implemented in
    # {Macro::SillyTavernV1::Engine} in ST ordering (because ordering affects behavior).
    class Pipeline
      # A single preprocessing rule applied to the raw text before macro substitution.
      #
      # The rule is intentionally minimal: a regex + a replacement.
      Rule = Data.define(:pattern, :replacement, :description) do
        def apply(text)
          text.to_s.gsub(pattern, replacement)
        end
      end

      def initialize(registry = nil)
        @registry = registry.nil? ? [] : registry
        unless @registry.respond_to?(:each)
          raise ArgumentError, "registry must respond to #each"
        end
      end

      def apply(text)
        str = text.to_s
        return str if str.empty?

        @registry.each do |macro|
          rule = macro.value
          next unless rule.respond_to?(:apply)

          str = rule.apply(str)
        end

        str
      end
    end
  end
end
