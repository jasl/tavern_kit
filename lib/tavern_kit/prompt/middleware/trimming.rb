# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Prompt
    module Middleware
      # Middleware that trims the prompt plan to fit token budget.
      #
      # This middleware:
      # - Evicts examples (by examples_behavior)
      # - Evicts lore (by priority)
      # - Truncates history (oldest first)
      # - Preserves: system prompts, latest user message
      #
      class Trimming < Base
        private

        def before(ctx)
          # Trimming happens after plan assembly, in the after hook
        end

        def after(ctx)
          # Prune ephemeral injections after build (regardless of trimming)
          prune_ephemeral_injections(ctx)

          return unless ctx.plan

          preset = ctx.effective_preset
          max_tokens = preset&.max_input_tokens
          return unless max_tokens

          token_estimator = ctx.token_estimator || ::TavernKit::TokenEstimator.default
          trimmer = Trimmer.new(
            token_estimator: token_estimator,
            message_overhead: preset.message_token_overhead
          )

          report = trimmer.trim!(
            ctx.plan,
            max_tokens: max_tokens,
            examples_behavior: preset.examples_behavior
          )

          ctx.plan.instance_variable_set(:@trim_report, report)
          ctx.trim_report = report
        end

        def prune_ephemeral_injections(ctx)
          return unless ctx.injection_registry && !ctx.injection_registry.empty?

          ctx.injection_registry.ephemeral_ids.each do |id|
            ctx.injection_registry.remove(id: id)
          end
        end
      end
    end
  end
end
