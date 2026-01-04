# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Prompt
    module Middleware
      # Middleware that performs macro expansion on all blocks.
      #
      # Note: In the current implementation, macro expansion is performed
      # inline during block construction in PinnedGroups, Injection, and
      # Compilation middlewares. This middleware serves as a hook point
      # for:
      # - Additional post-processing macro passes
      # - Custom macro environments
      # - Macro auditing/logging
      #
      # This design allows the new Macro::Environment system to be plugged
      # in when it's implemented.
      #
      # @example Using a custom macro environment
      #   pipeline.configure(:macro_expansion, environment: custom_env)
      #
      class MacroExpansion < Base
        private

        def before(ctx)
          # Macro expansion is currently performed inline during block construction.
          # This middleware is a placeholder for future macro environment integration.
          #
          # When the new Macro::Environment is implemented, this middleware will:
          # 1. Get the configured macro environment (or default)
          # 2. Re-expand all blocks through the environment's phases
          # 3. Support custom phase ordering and handlers

          nil unless option(:environment)

          # Future: apply custom macro environment
          # environment = option(:environment)
          # ctx.blocks = ctx.blocks.map do |block|
          #   content = environment.expand(block.content, ctx)
          #   block.with(content: content)
          # end
        end

        def after(ctx)
          # Post-expansion hooks can be added here
          return unless option(:post_expand_hook)

          hook = option(:post_expand_hook)
          hook.call(ctx) if hook.respond_to?(:call)
        end
      end
    end
  end
end
