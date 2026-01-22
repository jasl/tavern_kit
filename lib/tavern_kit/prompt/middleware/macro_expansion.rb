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
          # Macro expansion is performed inline during block construction (PinnedGroups, Injection, Compilation).
          # This middleware exists as a stable hook point for future macro pipeline integrations.
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
