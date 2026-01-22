# frozen_string_literal: true

module TavernKit
  module Macro
    # Represents a single phase in the macro expansion pipeline.
    #
    # A phase encapsulates a specific stage of macro processing with
    # its own set of handlers and patterns. Phases are executed in
    # sequence by the Environment.
    #
    # @example Creating a custom phase
    #   phase = Phase.new(:custom_phase)
    #   phase.add(:my_macro) { |inv| "Hello, #{inv.env[:user]}" }
    #   phase.expand("Say {{my_macro}}", context)
    #
    class Phase
      # @return [Symbol] phase name
      attr_reader :name

      # @return [Hash{Symbol => Proc}] registered handlers
      attr_reader :handlers

      # @return [Array<Hash>] pattern-based handlers
      attr_reader :patterns

      def initialize(name)
        @name = name.to_sym
        @handlers = {}
        @patterns = []
      end

      # Create a copy for safe modification.
      def initialize_copy(original)
        super
        @handlers = original.handlers.dup
        @patterns = original.patterns.map(&:dup)
      end

      # Add a handler for a specific macro name.
      #
      # @param name [Symbol, String] macro name (case-insensitive)
      # @param handler [Proc, nil] handler proc
      # @yield [Invocation] optional block handler
      # @return [self]
      def add(name, handler = nil, &block)
        key = name.to_s.downcase.to_sym
        @handlers[key] = handler || block
        self
      end

      # Remove a handler by name.
      #
      # @param name [Symbol, String] macro name
      # @return [self]
      def remove(name)
        key = name.to_s.downcase.to_sym
        @handlers.delete(key)
        self
      end

      # Add a pattern-based handler.
      #
      # Pattern handlers match regex patterns and are useful for
      # macros with dynamic syntax (e.g., {{roll:2d6+1}}).
      #
      # @param pattern [Regexp] pattern to match
      # @param handler [Proc, nil] handler proc
      # @yield [Invocation, MatchData] optional block handler
      # @return [self]
      def add_pattern(pattern, handler = nil, &block)
        @patterns << { pattern: pattern, handler: handler || block }
        self
      end

      # Remove a pattern handler.
      #
      # @param pattern [Regexp] pattern to remove
      # @return [self]
      def remove_pattern(pattern)
        @patterns.reject! { |p| p[:pattern] == pattern }
        self
      end

      # Check if a handler exists for a macro name.
      #
      # @param name [Symbol, String] macro name
      # @return [Boolean]
      def has?(name)
        key = name.to_s.downcase.to_sym
        @handlers.key?(key)
      end

      # Get a handler by name.
      #
      # @param name [Symbol, String] macro name
      # @return [Proc, nil]
      def get(name)
        key = name.to_s.downcase.to_sym
        @handlers[key]
      end

      # Expand macros in text using this phase's handlers.
      #
      # @param text [String] input text
      # @param context [Hash] expansion context
      # @return [String] expanded text
      def expand(text, context = {})
        result = text.to_s
        return result if result.empty?

        # First, apply pattern-based handlers
        @patterns.each do |pattern_def|
          result = apply_pattern(result, pattern_def, context)
        end

        # Then, apply named handlers
        @handlers.each_key do |name|
          result = apply_handler(result, name, context)
        end

        result
      end

      # Configure the phase using a block.
      #
      # @yield [Phase] self
      # @return [self]
      def configure(&block)
        instance_eval(&block) if block
        self
      end

      private

      def apply_pattern(text, pattern_def, context)
        pattern = pattern_def[:pattern]
        handler = pattern_def[:handler]

        text.gsub(pattern) do |match|
          begin
            invocation = build_invocation(match, context)
            arity = handler.respond_to?(:arity) ? handler.arity : handler.method(:call).arity
            result = arity == 1 ? handler.call(invocation) : handler.call(invocation, Regexp.last_match)
            sanitize_result(result, match)
          rescue StandardError
            match
          end
        end
      end

      def apply_handler(text, name, context)
        pattern = /\{\{#{Regexp.escape(name.to_s)}\}\}/i

        text.gsub(pattern) do |match|
          begin
            invocation = build_invocation(match, context)
            handler = @handlers[name]
            result = evaluate_handler(handler, invocation)
            sanitize_result(result, match)
          rescue StandardError
            match
          end
        end
      end

      def build_invocation(match, context)
        raw = unwrap(match)
        key = raw.to_s.strip.downcase

        # Parse name and args from the raw content
        parts = key.split(/[ :]+/, 2)
        name = parts[0].to_sym
        args_str = parts[1]

        args = if args_str
          args_str.split("::")
        else
          []
        end

        Invocation.new(
          raw: raw,
          key: key,
          name: name,
          args: args,
          offset: 0,
          raw_content_hash: nil,
          pick_seed: context[:pick_seed],
          allow_outlets: context[:allow_outlets] != false,
          env: context[:env] || {},
          rng: context[:rng],
          now: context[:now] || Time.now
        )
      end

      def evaluate_handler(handler, invocation)
        return nil unless handler

        if handler.is_a?(Proc)
          handler.arity == 0 ? handler.call : handler.call(invocation)
        elsif handler.respond_to?(:call)
          handler.call(invocation)
        else
          handler
        end
      end

      def sanitize_result(result, original)
        case result
        when nil
          original
        when String
          result
        else
          result.to_s
        end
      end

      def unwrap(match)
        s = match.to_s
        return s unless s.start_with?("{{") && s.end_with?("}}")

        s[2..-3]
      end
    end
  end
end
