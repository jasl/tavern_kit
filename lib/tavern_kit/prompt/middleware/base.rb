# frozen_string_literal: true

require_relative "../expander_vars"

module TavernKit
  module Prompt
    module Middleware
      # Base class for all prompt pipeline middlewares.
      #
      # Middlewares follow the Rack-style pattern: each middleware wraps the
      # next one in the chain, receives a context, can modify it before and
      # after passing to the next middleware.
      #
      # @example Simple middleware
      #   class LoggingMiddleware < TavernKit::Prompt::Middleware::Base
      #     private
      #
      #     def before(ctx)
      #       puts "Before: #{ctx.user_message}"
      #     end
      #
      #     def after(ctx)
      #       puts "After: #{ctx.blocks.size} blocks"
      #     end
      #   end
      #
      # @example Middleware that transforms context
      #   class SanitizerMiddleware < TavernKit::Prompt::Middleware::Base
      #     private
      #
      #     def before(ctx)
      #       ctx.user_message = ctx.user_message.to_s.strip
      #     end
      #   end
      #
      class Base
        # @return [#execute] the next middleware or terminal handler
        attr_reader :app

        # @return [Hash] middleware options
        attr_reader :options

        # Initialize middleware with next app and options.
        #
        # @param app [#execute] next middleware in chain
        # @param options [Hash] middleware-specific options
        def initialize(app, **options)
          @app = app
          @options = options
        end

        # Process the context through this middleware.
        #
        # Calls {#before}, then passes to the next middleware,
        # then calls {#after}.
        #
        # Public entrypoint is `#execute` (pipeline contract).
        #
        # @param ctx [Context] the prompt context
        # @return [Context] the processed context
        def execute(ctx)
          before(ctx)
          @app.execute(ctx)
          after(ctx)
          ctx
        end

        # Class method to get the middleware name for registration.
        #
        # @return [Symbol]
        def self.middleware_name
          name.split("::").last.gsub(/Middleware$/, "").gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
        end

        private

        # Hook called before passing to next middleware.
        #
        # Override in subclasses to transform the context before
        # it reaches subsequent middlewares.
        #
        # @param ctx [Context]
        # @return [void]
        def before(ctx)
          # Override in subclass
        end

        # Hook called after next middleware returns.
        #
        # Override in subclasses to transform the context after
        # subsequent middlewares have processed it.
        #
        # @param ctx [Context]
        # @return [void]
        def after(ctx)
          # Override in subclass
        end

        # Helper to access an option with default.
        #
        # @param key [Symbol]
        # @param default [Object]
        # @return [Object]
        def option(key, default = nil)
          @options.fetch(key, default)
        end

        # Build comprehensive macro expansion vars from context.
        #
        # This populates all ST-compatible macro variables so macros like
        # {{char}}, {{user}}, {{description}}, {{persona}}, {{charPrompt}}, etc.
        # can be expanded through the env macro pass.
        #
        # Character field values are pre-expanded with {{char}} and {{user}} so
        # nested macros work correctly (e.g., charPrompt containing "{{char}}").
        #
        # @param ctx [Context] prompt context
        # @param overrides [Hash] additional vars to merge
        # @return [Hash] vars hash for macro expander
        def build_expander_vars(ctx, overrides: {})
          ::TavernKit::Prompt::ExpanderVars.build(ctx, overrides: overrides)
        end

        # Get default macro expander
        def default_expander
          ::TavernKit::Macro::SillyTavernV2::Engine.new
        end
      end
    end
  end
end
