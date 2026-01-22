# frozen_string_literal: true

module TavernKit
  # Global registry for custom macros.
  #
  # This is inspired by SillyTavern's `MacrosParser.registerMacro` and `populateEnv`
  # (vendored under `tmp/SillyTavern/public/scripts/macros.js`), but adapted to
  # TavernKit's Ruby macro expansion pipeline.
  #
  # Registered macros are added into the macro env during prompt building, and can
  # be used anywhere TavernKit expands macros.
  #
  # Values may be:
  # - String (or any object with a useful `to_s`)
  # - Proc/callable (lazy): evaluated only if the macro is encountered
  #
  # Callable macro values receive a {MacroContext} and a
  # {TavernKit::Macro::Invocation} for parameterized macros.
  # Callables should accept both arguments (or be arity-tolerant Procs).
  class MacroRegistry
    Macro = Data.define(:key, :value, :description)

    include Enumerable

    def initialize
      @macros = {}
    end

    # Ensure `dup`/`clone` produce an independent registry (no shared backing hash).
    def initialize_copy(original)
      super
      @macros = original.instance_variable_get(:@macros).dup
    end

    # Return a new registry containing only the specified macro keys.
    #
    # Missing keys are ignored (matches Hash#slice behavior).
    #
    # @param keys [Array<String, Symbol>]
    # @return [MacroRegistry]
    def slice(*keys)
      keys = keys.flatten

      copy = self.class.new
      keys.each do |key|
        k = coerce_key!(key)
        macro = @macros[k]
        copy.instance_variable_get(:@macros)[k] = macro if macro
      end

      copy
    end
    alias only slice

    # Return a new registry excluding the specified macro keys.
    #
    # Missing keys are ignored.
    #
    # @param keys [Array<String, Symbol>]
    # @return [MacroRegistry]
    def except(*keys)
      keys = keys.flatten

      copy = dup
      keys.each do |key|
        copy.instance_variable_get(:@macros).delete(coerce_key!(key))
      end

      copy
    end

    # Register (or replace) a custom macro.
    #
    # @param key [String] macro name without surrounding braces (e.g., "myvar")
    # @param value [Object, nil] static macro value (optional if block is provided)
    # @param description [String] optional description for introspection/docs
    # @yieldparam ctx [MacroContext]
    # @yieldparam invocation [TavernKit::Macro::Invocation, nil]
    # @return [self]
    def register(key, value = nil, description: "", &block)
      k = coerce_key!(key)

      v = block || value
      raise ArgumentError, "Macro value is required (provide a value or a block)" if v.nil?

      @macros[k] = Macro.new(
        key: k,
        value: v,
        description: description.to_s
      )

      self
    end

    # Unregister a macro by key.
    #
    # @param key [String]
    # @return [Macro, nil] removed macro (if present)
    def unregister(key)
      @macros.delete(coerce_key!(key))
    end

    # Get a macro value by key.
    #
    # @param key [String]
    # @return [Object, nil]
    def get(key)
      @macros[coerce_key!(key)]&.value
    end
    alias [] get

    # Check if a macro is registered.
    #
    # @param key [String]
    # @return [Boolean]
    def has?(key)
      @macros.key?(coerce_key!(key))
    end
    alias key? has?

    # Remove all registered macros.
    #
    # Primarily intended for test hygiene.
    #
    # @return [self]
    def clear
      @macros.clear
      self
    end

    # @return [Integer]
    def size
      @macros.size
    end

    # Iterate over registered macros in registration order.
    #
    # @yieldparam macro [Macro]
    def each
      return enum_for(:each) unless block_given?

      @macros.each_value do |macro|
        yield macro
      end
    end

    # Populate a macro env hash with registered macros for the given context.
    #
    # Values are wrapped as zero-arg Procs when needed, so they remain lazily
    # evaluated by {TavernKit::Macro::SillyTavernV1::Engine}.
    #
    # @param env [Hash{Symbol=>Object}] mutable env hash (modified in-place)
    # @param ctx [MacroContext] macro evaluation context
    # @return [Hash] the same env hash for convenience
    def populate_env(env, ctx)
      return env unless env.is_a?(Hash)

      each do |macro|
        env[macro.key] = wrap_macro_value(macro.value, ctx)
      end

      env
    end

    private

    # Coerce a key to a normalized symbol.
    #
    # @param key [String, Symbol] the key to coerce
    # @return [Symbol] normalized lowercase symbol
    def coerce_key!(key)
      raw = key.to_s.strip
      raise ArgumentError, "Macro key must not be empty" if raw.empty?

      if raw.start_with?("{{") || raw.end_with?("}}")
        raise ArgumentError, "Macro key must not include the surrounding braces"
      end

      downcased = raw.downcase

      # Reserved keys used internally by the macro engine / builder.
      if %w[variables outlets].include?(downcased)
        raise ArgumentError, "Macro key is reserved: #{raw.inspect}"
      end

      downcased.to_sym
    end

    def wrap_macro_value(value, ctx)
      callable = macro_callable(value)
      return value unless callable

      # Always pass ctx + invocation; Proc blocks will ignore unused args.
      ->(invocation = nil) { callable.call(ctx, invocation) }
    end

    def macro_callable(value)
      return value if value.is_a?(Proc)
      return value if value.respond_to?(:call)

      nil
    end
  end
end
