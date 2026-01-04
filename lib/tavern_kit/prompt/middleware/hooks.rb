# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Prompt
    module Middleware
      # Middleware that executes before_build and after_build hooks.
      #
      # This middleware wraps the entire pipeline, running before_build hooks
      # at the start and after_build hooks at the end.
      #
      # @example
      #   pipeline = Pipeline.new do
      #     use Middleware::Hooks
      #     # ... other middlewares
      #   end
      #
      class Hooks < Base
        private

        def before(ctx)
          return unless ctx.hook_registry

          hook_ctx = build_hook_context(ctx)
          ctx.hook_registry.run_before_build(hook_ctx)
          apply_hook_context_changes(ctx, hook_ctx)
        end

        def after(ctx)
          return unless ctx.hook_registry
          return unless ctx.plan

          hook_ctx = build_hook_context(ctx)
          hook_ctx.plan = ctx.plan

          ctx.hook_registry.run_after_build(hook_ctx)

          # Validate plan type after hooks
          unless hook_ctx.plan.is_a?(Plan)
            raise ArgumentError, "after_build must set ctx.plan to a Prompt::Plan, got: #{hook_ctx.plan.class}"
          end

          ctx.plan = hook_ctx.plan
        end

        def build_hook_context(ctx)
          HookContext.new(
            character: ctx.character,
            user: ctx.user,
            history: ctx.history,
            user_message: ctx.user_message.to_s,
            preset: ctx.preset,
            generation_type: ctx.generation_type,
            injection_registry: ctx.injection_registry,
            macro_vars: ctx.macro_vars,
            group: ctx.group
          )
        end

        def apply_hook_context_changes(ctx, hook_ctx)
          # Validate and apply character changes
          if !hook_ctx.character.nil? && !hook_ctx.character.is_a?(Character)
            raise ArgumentError,
                  "before_build must set ctx.character to a TavernKit::Character (or nil), got: #{hook_ctx.character.class}"
          end
          ctx.character = hook_ctx.character

          # Validate and apply user changes
          if !hook_ctx.user.nil? && !hook_ctx.user.is_a?(Participant)
            raise ArgumentError,
                  "before_build must set ctx.user to a TavernKit::Participant (or nil), got: #{hook_ctx.user.class}"
          end
          ctx.user = hook_ctx.user

          # Validate and apply history changes
          resolved_history = hook_ctx.history || ChatHistory.new
          unless resolved_history.is_a?(ChatHistory::Base)
            raise ArgumentError,
                  "before_build must set ctx.history to a TavernKit::ChatHistory::Base (or nil), got: #{resolved_history.class}"
          end
          ctx.history = resolved_history

          # Apply user message changes
          ctx.user_message = hook_ctx.user_message.to_s
        end
      end
    end
  end
end
