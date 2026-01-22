# frozen_string_literal: true

module TavernKit
  module Macro
    # Registry of ordered parsing rules for converting raw `{{...}}` content into an Invocation.
    #
    # This is the "syntax layer" of macro expansion: it decides how different ST-style
    # spellings (e.g., `time_utc+3`, `setvar::x::y`) map to a canonical macro name and
    # parsed args payload.
    #
    # Rules run in registration order (first match wins).
    class InvocationSyntax
      Rule = Data.define(:id, :pattern, :description, :handler) do
        def parse(raw)
          m = pattern.match(raw.to_s)
          return nil unless m

          handler.call(m, raw.to_s)
        end
      end

      def initialize
        @rules = []
      end

      # Register a new parsing rule.
      #
      # @param id [String, Symbol] stable identifier for enabling/disabling
      # @param pattern [Regexp] regex applied to raw content (inside braces)
      # @param description [String] optional documentation
      # @yieldparam match [MatchData]
      # @yieldparam raw [String]
      # @yieldreturn [Array<(String, Object)>] [name, args]
      # @return [self]
      def register(id, pattern, description: "", &block)
        raise ArgumentError, "register requires a block" unless block
        raise ArgumentError, "pattern must be a Regexp" unless pattern.is_a?(Regexp)

        @rules << Rule.new(
          id: id.to_sym,
          pattern: pattern,
          description: description.to_s,
          handler: block,
        )
        self
      end

      # Parse raw content into [name, args].
      #
      # @param raw [String]
      # @param default_name [String] name to use when no rule matches
      # @return [Array<(String, Object)>] [name, args]
      def parse(raw, default_name:)
        @rules.each do |rule|
          parsed = rule.parse(raw)
          next unless parsed

          name, args = parsed
          return [name.to_s, args]
        end

        [default_name.to_s, nil]
      end

      # @return [Array<Symbol>]
      def ids
        @rules.map(&:id)
      end

      # Return a new syntax including only the specified rule ids.
      #
      # Missing ids are ignored.
      def only(*ids)
        wanted = ids.flatten.compact.map(&:to_sym)

        copy = self.class.new
        @rules.each do |r|
          next unless wanted.include?(r.id)

          copy.send(:add_rule, r)
        end
        copy
      end

      # Return a new syntax excluding the specified rule ids.
      #
      # Missing ids are ignored.
      def except(*ids)
        excluded = ids.flatten.compact.map(&:to_sym)

        copy = self.class.new
        @rules.each do |r|
          next if excluded.include?(r.id)

          copy.send(:add_rule, r)
        end
        copy
      end

      # Deep-ish copy (rules are immutable Data objects).
      def dup
        copy = self.class.new
        @rules.each { |r| copy.send(:add_rule, r) }
        copy
      end

      private

      def add_rule(rule)
        @rules << rule
      end
    end
  end
end
