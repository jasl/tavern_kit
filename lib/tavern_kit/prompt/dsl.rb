# frozen_string_literal: true

module TavernKit
  module Prompt
    # DSL for building prompts in a Ruby-idiomatic style.
    #
    # The DSL provides two styles of usage:
    #
    # 1. Block-based DSL:
    #    plan = TavernKit::Prompt.build do
    #      character my_char
    #      user my_user
    #      preset my_preset
    #      history chat_history
    #      message "Hello!"
    #    end
    #
    # 2. Fluent API:
    #    plan = TavernKit::Prompt::DSL.new
    #      .character(my_char)
    #      .user(my_user)
    #      .message("Hello!")
    #      .build
    #
    class DSL
      # @return [Context] the prompt context being built
      attr_reader :context

      # @return [Pipeline] the pipeline to use
      attr_reader :pipeline

      def initialize(pipeline: nil, &block)
        @context = Context.new
        @pipeline = pipeline || Pipeline.default
        @built = false

        instance_eval(&block) if block
      end

      # Set the character.
      #
      # @param value [Character] the character card
      # @return [self]
      def character(value)
        @context.character = value
        self
      end

      # Set the user/persona.
      #
      # @param value [Participant] the user participant
      # @return [self]
      def user(value)
        @context.user = value
        self
      end

      # Set the preset configuration.
      #
      # @param value [Preset] the preset
      # @return [self]
      def preset(value)
        @context.preset = value
        self
      end

      # Set the chat history.
      #
      # @param value [ChatHistory::Base] the chat history
      # @return [self]
      def history(value)
        @context.history = value
        self
      end

      # Set the user message for this prompt.
      #
      # @param text [String] the user message
      # @return [self]
      def message(text)
        @context.user_message = text.to_s
        self
      end

      # Add a lore book.
      #
      # @param book [Lore::Book] a lore book
      # @return [self]
      def lore_book(book)
        @context.lore_books << book
        self
      end

      # Add multiple lore books.
      #
      # @param books [Array<Lore::Book>] lore books
      # @return [self]
      def lore_books(books)
        @context.lore_books.concat(Array(books))
        self
      end

      # Set the generation type.
      #
      # @param type [Symbol] one of :normal, :continue, :impersonate, :swipe, :regenerate, :quiet
      # @return [self]
      def generation_type(type)
        @context.generation_type = type
        self
      end

      # Set the group context.
      #
      # @param value [GroupContext] group context
      # @return [self]
      def group(value)
        @context.group = value
        self
      end

      # Set greeting index for first message selection.
      #
      # @param index [Integer, nil] greeting index (0 = first_mes, 1+ = alternate)
      # @return [self]
      def greeting(index)
        @context.greeting_index = index
        self
      end

      # Set Author's Note overrides.
      #
      # @param position [Symbol, nil] :in_chat, :before_prompt, :in_prompt
      # @param depth [Integer, nil] injection depth
      # @param role [Symbol, nil] message role
      # @return [self]
      def authors_note(position: nil, depth: nil, role: nil)
        overrides = {}
        overrides[:position] = position if position
        overrides[:depth] = depth if depth
        overrides[:role] = role if role
        @context.authors_note_overrides = overrides.empty? ? nil : overrides
        self
      end

      # Set macro variables.
      #
      # @param vars [Hash] macro variables
      # @return [self]
      def macro_vars(vars)
        @context.macro_vars = vars&.transform_keys { |k| k.to_s.downcase.to_sym }
        self
      end

      # Set or add to macro variables.
      #
      # @param key [Symbol, String] variable name
      # @param value [Object] variable value
      # @return [self]
      def set_var(key, value)
        @context.macro_vars ||= {}
        @context.macro_vars[key.to_s.downcase.to_sym] = value
        self
      end

      # Set the macro registry.
      #
      # @param registry [MacroRegistry] custom macro registry
      # @return [self]
      def macro_registry(registry)
        @context.macro_registry = registry
        self
      end

      # Set the injection registry.
      #
      # @param registry [InjectionRegistry] injection registry
      # @return [self]
      def injection_registry(registry)
        @context.injection_registry = registry
        self
      end

      # Set the hook registry.
      #
      # @param registry [HookRegistry] hook registry
      # @return [self]
      def hook_registry(registry)
        @context.hook_registry = registry
        self
      end

      # Register a before_build hook.
      #
      # @yield [HookContext] hook callback
      # @return [self]
      def before_build(&block)
        @context.hook_registry ||= HookRegistry.new
        @context.hook_registry.before_build(&block)
        self
      end

      # Register an after_build hook.
      #
      # @yield [HookContext] hook callback
      # @return [self]
      def after_build(&block)
        @context.hook_registry ||= HookRegistry.new
        @context.hook_registry.after_build(&block)
        self
      end

      # Force activate World Info entries.
      #
      # @param activations [Array<Hash>] forced activations
      # @return [self]
      def force_world_info(activations)
        @context.forced_world_info_activations = Array(activations)
        self
      end

      # Set the token estimator.
      #
      # @param estimator [TokenEstimator::Base] token estimator
      # @return [self]
      def token_estimator(estimator)
        @context.token_estimator = estimator
        self
      end

      # Set the lore engine.
      #
      # @param engine [Lore::Engine] lore engine
      # @return [self]
      def lore_engine(engine)
        @context.lore_engine = engine
        self
      end

      # Set the macro expander.
      #
      # @param expander [#expand] macro expander
      # @return [self]
      def expander(expander)
        @context.expander = expander
        self
      end

      # Select which macro expander to use.
      #
      # @param engine [Symbol, String] :silly_tavern_v1 or :silly_tavern_v2
      # @return [self]
      def macro_engine(engine)
        mode = engine.to_sym

        @context.expander = case mode
        when :silly_tavern_v1
                              Macro::SillyTavernV1::Engine.new
        when :silly_tavern_v2
                              Macro::SillyTavernV2::Engine.new
        else
                              raise ArgumentError,
                                    "macro_engine must be :silly_tavern_v1 or :silly_tavern_v2 (got #{engine.inspect})"
        end

        self
      end

      # Set the warning handler.
      #
      # @param handler [Symbol, #call, nil] :default, nil, or callable
      # @return [self]
      def warning_handler(handler)
        @context.warning_handler = handler
        self
      end

      # Enable or disable strict mode.
      #
      # @param enabled [Boolean]
      # @return [self]
      def strict(enabled = true)
        @context.strict = enabled
        self
      end

      # Configure a specific middleware.
      #
      # @param name [Symbol] middleware name
      # @param options [Hash] middleware options
      # @return [self]
      def configure_middleware(name, **options)
        @pipeline = @pipeline.dup
        @pipeline.configure(name, **options)
        self
      end

      # Replace a middleware.
      #
      # @param name [Symbol] middleware name to replace
      # @param middleware [Class] new middleware class
      # @param options [Hash] middleware options
      # @return [self]
      def replace_middleware(name, middleware, **options)
        @pipeline = @pipeline.dup
        @pipeline.replace(name, middleware, **options)
        self
      end

      # Insert a middleware before another.
      #
      # @param before_name [Symbol] middleware to insert before
      # @param middleware [Class] middleware class to insert
      # @param name [Symbol, nil] name for the new middleware
      # @param options [Hash] middleware options
      # @return [self]
      def insert_middleware_before(before_name, middleware, name: nil, **options)
        @pipeline = @pipeline.dup
        @pipeline.insert_before(before_name, middleware, name: name, **options)
        self
      end

      # Insert a middleware after another.
      #
      # @param after_name [Symbol] middleware to insert after
      # @param middleware [Class] middleware class to insert
      # @param name [Symbol, nil] name for the new middleware
      # @param options [Hash] middleware options
      # @return [self]
      def insert_middleware_after(after_name, middleware, name: nil, **options)
        @pipeline = @pipeline.dup
        @pipeline.insert_after(after_name, middleware, name: name, **options)
        self
      end

      # Remove a middleware.
      #
      # @param name [Symbol] middleware name to remove
      # @return [self]
      def remove_middleware(name)
        @pipeline = @pipeline.dup
        @pipeline.remove(name)
        self
      end

      # Build the prompt plan.
      #
      # @return [Plan] the built prompt plan
      def build
        raise "DSL has already been built" if @built

        @built = true

        # Ensure defaults are set
        @context.injection_registry ||= InjectionRegistry.new
        @context.hook_registry ||= HookRegistry.new
        @context.token_estimator ||= TokenEstimator.default
        @context.expander ||= Macro::SillyTavernV2::Engine.new
        @context.macro_vars ||= {}

        @pipeline.call(@context)
        @context.plan
      end

      # Build and convert to messages.
      #
      # @param dialect [Symbol] output dialect (:openai, :anthropic, etc.)
      # @return [Array<Hash>] messages array
      def to_messages(dialect: :openai)
        plan = build
        plan.to_messages(dialect: dialect)
      end

      # Class methods for convenient access
      class << self
        # Build a prompt using the DSL.
        #
        # @param pipeline [Pipeline, nil] custom pipeline
        # @yield DSL block
        # @return [Plan] the built prompt plan
        def build(pipeline: nil, &block)
          dsl = new(pipeline: pipeline, &block)
          dsl.build
        end

        # Build a prompt and convert to messages.
        #
        # @param dialect [Symbol] output dialect
        # @param pipeline [Pipeline, nil] custom pipeline
        # @yield DSL block
        # @return [Array<Hash>] messages array
        def to_messages(dialect: :openai, pipeline: nil, &block)
          dsl = new(pipeline: pipeline, &block)
          dsl.to_messages(dialect: dialect)
        end
      end
    end

    # Module-level convenience methods
    class << self
      # Build a prompt using the DSL.
      #
      # @param pipeline [Pipeline, nil] custom pipeline
      # @yield DSL block
      # @return [Plan] the built prompt plan
      #
      # @example
      #   plan = TavernKit::Prompt.build do
      #     character my_char
      #     user my_user
      #     message "Hello!"
      #   end
      #
      def build(pipeline: nil, &block)
        DSL.build(pipeline: pipeline, &block)
      end

      # Build a prompt and convert to messages.
      #
      # @param dialect [Symbol] output dialect
      # @param pipeline [Pipeline, nil] custom pipeline
      # @yield DSL block
      # @return [Array<Hash>] messages array
      def to_messages(dialect: :openai, pipeline: nil, &block)
        DSL.to_messages(dialect: dialect, pipeline: pipeline, &block)
      end
    end
  end
end
