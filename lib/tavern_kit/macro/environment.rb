# frozen_string_literal: true

require_relative "phase"

module TavernKit
  module Macro
    # A configurable macro expansion environment.
    #
    # The Environment provides a structured way to configure macro
    # expansion through phases and handlers. It supports:
    # - Multiple expansion phases (pre_env, env, post_env)
    # - Custom handlers for individual macros
    # - Inheritance from preset configurations
    # - Phase replacement and customization
    #
    # @example Basic usage
    #   env = Environment.new do
    #     inherit :st_core
    #     add :custom_macro, "Custom value"
    #   end
    #   result = env.expand("Hello, {{custom_macro}}!", context)
    #
    # @example Custom phases
    #   env = Environment.new do
    #     phase :pre_env do |p|
    #       p.add :my_early_macro, "Expanded early"
    #     end
    #     phase :env, default: true
    #     phase :post_env do |p|
    #       p.remove :random  # Remove built-in random
    #       p.add :my_random { |inv| rand.to_s }
    #     end
    #   end
    #
    class Environment
      # Standard phase names in execution order
      STANDARD_PHASES = %i[pre_env env post_env].freeze

      # @return [Hash{Symbol => Phase}] phases by name
      attr_reader :phases

      # @return [Hash{Symbol => Proc}] global handlers
      attr_reader :handlers

      def initialize(&block)
        @phases = {}
        @handlers = {}
        @inherited = []

        # Initialize standard phases
        STANDARD_PHASES.each do |name|
          @phases[name] = Phase.new(name)
        end

        instance_eval(&block) if block
      end

      # Create a copy for safe modification.
      def initialize_copy(original)
        super
        @phases = original.phases.transform_values(&:dup)
        @handlers = original.handlers.dup
        @inherited = original.instance_variable_get(:@inherited).dup
      end

      # Configure a phase.
      #
      # @param name [Symbol] phase name
      # @param klass [Class, nil] custom phase class
      # @param default [Boolean] use default ST configuration
      # @yield [Phase] phase configuration block
      # @return [self]
      def phase(name, klass = nil, default: false, &block)
        name = name.to_sym

        if klass
          @phases[name] = klass.new(name)
        elsif default
          apply_default_phase(name)
        elsif block
          @phases[name] ||= Phase.new(name)
          @phases[name].configure(&block)
        end

        self
      end

      # Replace a phase entirely.
      #
      # @param name [Symbol] phase name
      # @param phase [Phase] replacement phase
      # @return [self]
      def replace_phase(name, phase)
        @phases[name.to_sym] = phase
        self
      end

      # Remove a phase.
      #
      # @param name [Symbol] phase name
      # @return [self]
      def remove_phase(name)
        @phases.delete(name.to_sym)
        self
      end

      # Inherit handlers from a preset.
      #
      # @param preset [Symbol] preset name (:st_core, :st_full, :minimal)
      # @return [self]
      def inherit(preset)
        @inherited << preset

        case preset
        when :st_core
          apply_st_core_preset
        when :st_full, :silly_tavern
          apply_st_full_preset
        when :minimal
          apply_minimal_preset
        end

        self
      end

      # Exclude specific macros.
      #
      # @param names [Array<Symbol>] macro names to exclude
      # @return [self]
      def exclude(*names)
        names.flatten.each do |name|
          key = name.to_s.downcase.to_sym
          @handlers.delete(key)
          @phases.each_value { |p| p.remove(key) }
        end
        self
      end

      # Add a macro handler.
      #
      # @param name [Symbol, String] macro name
      # @param value [Object, nil] static value or handler
      # @yield [Invocation] handler block
      # @return [self]
      def add(name, value = nil, &block)
        key = name.to_s.downcase.to_sym
        @handlers[key] = value || block
        self
      end

      # Remove a macro handler.
      #
      # @param name [Symbol, String] macro name
      # @return [self]
      def remove(name)
        key = name.to_s.downcase.to_sym
        @handlers.delete(key)
        self
      end

      # Check if a macro handler exists.
      #
      # @param name [Symbol, String] macro name
      # @return [Boolean]
      def has?(name)
        key = name.to_s.downcase.to_sym
        @handlers.key?(key) || @phases.any? { |_, p| p.has?(key) }
      end

      # Get a macro handler.
      #
      # @param name [Symbol, String] macro name
      # @return [Proc, Object, nil]
      def get(name)
        key = name.to_s.downcase.to_sym
        return @handlers[key] if @handlers.key?(key)

        @phases.each_value do |phase|
          handler = phase.get(key)
          return handler if handler
        end

        nil
      end

      # Expand macros in text.
      #
      # @param text [String] input text
      # @param context [Hash] expansion context
      # @return [String] expanded text
      def expand(text, context = {})
        result = text.to_s
        return result if result.empty?

        # Build full context
        full_context = context.merge(handlers: @handlers)

        # Run through phases in order
        STANDARD_PHASES.each do |phase_name|
          phase = @phases[phase_name]
          next unless phase

          result = phase.expand(result, full_context)
        end

        # Apply global handlers
        @handlers.each do |name, handler|
          pattern = /\{\{#{Regexp.escape(name.to_s)}\}\}/i
          result = result.gsub(pattern) do |match|
            begin
              evaluate_handler(handler, match, full_context)
            rescue StandardError
              match
            end
          end
        end

        result
      end

      # Class methods for preset creation
      class << self
        # Create a SillyTavern-compatible environment.
        #
        # @return [Environment]
        def st_default
          new do
            inherit :st_full
          end
        end

        # Create a minimal environment.
        #
        # @return [Environment]
        def minimal
          new do
            inherit :minimal
          end
        end

        # Create an empty environment (no handlers).
        #
        # @return [Environment]
        def empty
          new
        end
      end

      private

      def apply_default_phase(name)
        case name
        when :pre_env
          apply_st_pre_env_phase
        when :env
          apply_st_env_phase
        when :post_env
          apply_st_post_env_phase
        end
      end

      def apply_st_core_preset
        # Core ST macros that are commonly used
        apply_st_env_phase
      end

      def apply_st_full_preset
        apply_st_pre_env_phase
        apply_st_env_phase
        apply_st_post_env_phase
      end

      def apply_minimal_preset
        # Only the most basic macros
        phase = @phases[:env]
        phase.add(:char) { |inv| inv.env[:char].to_s }
        phase.add(:user) { |inv| inv.env[:user].to_s }
      end

      def apply_st_pre_env_phase
        phase = @phases[:pre_env]

        # Roll macro
        phase.add_pattern(/\{\{roll[ :][^}]+\}\}/i) do |inv|
          evaluate_roll(inv)
        end

        # Variable macros
        phase.add_pattern(/\{\{setvar::[^}]+\}\}/i) { |inv| handle_setvar(inv) }
        phase.add_pattern(/\{\{getvar::[^}]+\}\}/i) { |inv| handle_getvar(inv) }
        phase.add_pattern(/\{\{addvar::[^}]+\}\}/i) { |inv| handle_addvar(inv) }
        phase.add_pattern(/\{\{incvar::[^}]+\}\}/i) { |inv| handle_incvar(inv) }
        phase.add_pattern(/\{\{decvar::[^}]+\}\}/i) { |inv| handle_decvar(inv) }

        # Utility macros
        phase.add(:newline) { "\n" }
        phase.add(:noop) { "" }
        phase.add(:input) { |inv| inv.env[:input].to_s }
      end

      def apply_st_env_phase
        phase = @phases[:env]

        # Character/user macros
        phase.add(:char) { |inv| inv.env[:char].to_s }
        phase.add(:user) { |inv| inv.env[:user].to_s }
        phase.add(:persona) { |inv| inv.env[:persona].to_s }
        phase.add(:original) { |inv| inv.env[:original].to_s }
        phase.add(:description) { |inv| inv.env[:description].to_s }
        phase.add(:personality) { |inv| inv.env[:personality].to_s }
        phase.add(:scenario) { |inv| inv.env[:scenario].to_s }
        phase.add(:system) { |inv| inv.env[:system].to_s }
        phase.add(:mesexamples) { |inv| inv.env[:mesexamples].to_s }
        phase.add(:mes_example) { |inv| inv.env[:mes_example].to_s }
      end

      def apply_st_post_env_phase
        phase = @phases[:post_env]

        # Time/date macros
        phase.add(:time) { |inv| inv.now.strftime("%H:%M") }
        phase.add(:date) { |inv| inv.now.strftime("%Y-%m-%d") }
        phase.add(:weekday) { |inv| inv.now.strftime("%A") }
        phase.add(:isotime) { |inv| inv.now.strftime("%H:%M:%S") }
        phase.add(:isodate) { |inv| inv.now.strftime("%Y-%m-%d") }

        # Random/pick macros
        phase.add_pattern(/\{\{random\s?::?[^}]+\}\}/i) do |inv|
          evaluate_random(inv)
        end

        phase.add_pattern(/\{\{pick\s?::?[^}]+\}\}/i) do |inv|
          evaluate_pick(inv)
        end

        # Outlet macro
        phase.add_pattern(/\{\{outlet::.+?\}\}/i) do |inv|
          evaluate_outlet(inv)
        end
      end

      def evaluate_handler(handler, match, context)
        invocation = build_simple_invocation(match, context)

        result = if handler.is_a?(Proc)
          handler.arity == 0 ? handler.call : handler.call(invocation)
        elsif handler.respond_to?(:execute)
          handler.execute(invocation)
        else
          handler
        end

        result.nil? ? match : result.to_s
      end

      def build_simple_invocation(match, context)
        raw = match.to_s.gsub(/^\{\{|\}\}$/, "")
        key = raw.strip.downcase

        parts = key.split(/[ :]+/, 2)
        name = parts[0].to_sym
        args = parts[1]&.split("::") || []

        Invocation.new(
          raw: raw,
          key: key,
          name: name,
          args: args,
          offset: 0,
          raw_content_hash: nil,
          pick_seed: context[:pick_seed],
          allow_outlets: context[:allow_outlets] != false,
          env: context[:env] || context,
          rng: context[:rng],
          now: context[:now] || Time.now
        )
      end

      # Placeholder implementations for ST macros
      def evaluate_roll(inv)
        # Basic dice roll implementation
        raw = inv.raw.to_s
        match = raw.match(/roll[ :](.+)/i)
        return raw unless match

        dice_expr = match[1].strip
        # Simple d20 style parsing
        if dice_expr =~ /(\d*)d(\d+)([+-]\d+)?/i
          count = (Regexp.last_match(1).empty? ? 1 : Regexp.last_match(1).to_i)
          sides = Regexp.last_match(2).to_i
          modifier = Regexp.last_match(3).to_i

          rng = inv.rng || Random.new
          total = count.times.sum { rng.rand(1..sides) } + modifier
          total.to_s
        else
          "0"
        end
      end

      def handle_setvar(inv)
        args = inv.args
        return "" unless args.length >= 2

        name = args[0]
        value = args[1]
        store = inv.env[:local_store]
        store&.set(name, value)
        ""
      end

      def handle_getvar(inv)
        args = inv.args
        return "" unless args.any?

        name = args[0]
        index = args[1]&.to_i
        store = inv.env[:local_store]
        return "" unless store

        val = store.get(name)
        if index && val.is_a?(Array)
          val[index].to_s
        else
          val.to_s
        end
      end

      def handle_addvar(inv)
        args = inv.args
        return "" unless args.length >= 2

        name = args[0]
        value = args[1]
        store = inv.env[:local_store]
        return "" unless store

        current = store.get(name)
        if current.is_a?(Numeric)
          store.set(name, current + value.to_f)
        else
          store.set(name, current.to_s + value.to_s)
        end
        ""
      end

      def handle_incvar(inv)
        args = inv.args
        return "" unless args.any?

        name = args[0]
        store = inv.env[:local_store]
        return "" unless store

        current = store.get(name).to_i
        store.set(name, current + 1)
        ""
      end

      def handle_decvar(inv)
        args = inv.args
        return "" unless args.any?

        name = args[0]
        store = inv.env[:local_store]
        return "" unless store

        current = store.get(name).to_i
        store.set(name, current - 1)
        ""
      end

      def evaluate_random(inv)
        args = inv.args
        return "" if args.empty?

        rng = inv.rng || Random.new
        args[rng.rand(args.length)].to_s
      end

      def evaluate_pick(inv)
        args = inv.args
        return "" if args.empty?

        # Use pick_seed for deterministic selection
        seed = inv.pick_seed || inv.raw_content_hash || 0
        index = seed.abs % args.length
        args[index].to_s
      end

      def evaluate_outlet(inv)
        return "" unless inv.allow_outlets

        args = inv.args
        return "" if args.empty?

        outlet_name = args[0]
        outlets = inv.env[:outlets]
        return "" unless outlets.is_a?(Hash)

        outlets[outlet_name].to_s
      end
    end
  end
end
