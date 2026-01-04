# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Prompt
    module Middleware
      # Middleware that assembles the final Prompt::Plan.
      #
      # This middleware:
      # - Creates the Plan object from compiled blocks
      # - Includes outlets from World Info
      # - Includes lore_result reference
      # - Resolves and includes greeting text
      # - Collects warnings
      #
      class PlanAssembly < Base
        private

        def before(ctx)
          resolved_greeting, resolved_greeting_index = resolve_greeting(ctx)

          ctx.resolved_greeting = resolved_greeting
          ctx.resolved_greeting_index = resolved_greeting_index

          ctx.plan = Plan.new(
            blocks: ctx.blocks || [],
            outlets: ctx.outlets || {},
            lore_result: ctx.lore_result,
            greeting: resolved_greeting,
            greeting_index: resolved_greeting_index,
            warnings: ctx.warnings.dup
          )
        end

        def resolve_greeting(ctx)
          return [nil, nil] if ctx.greeting_index.nil? || ctx.character.nil?

          data = ctx.character.data
          greetings = build_greetings_array(data)

          if ctx.greeting_index < 0 || ctx.greeting_index >= greetings.size
            raise ArgumentError,
                  "Greeting index #{ctx.greeting_index} out of range. " \
                  "Available: 0 (first_mes)#{greetings.size > 1 ? ", 1-#{greetings.size - 1} (alternate)" : ""}"
          end

          raw_greeting = greetings[ctx.greeting_index]
          expander = ctx.expander || default_expander
          expanded_greeting = expand_macro(expander, ctx, raw_greeting.to_s, allow_outlets: false)

          [expanded_greeting, ctx.greeting_index]
        end

        def build_greetings_array(data)
          greetings = []
          greetings << data.first_mes.to_s
          greetings.concat(Array(data.alternate_greetings).map(&:to_s))
          greetings
        end

        def expand_macro(expander, ctx, text, allow_outlets:)
          vars = build_expander_vars(ctx)
          expander.expand(text.to_s, vars, allow_outlets: allow_outlets)
        end

        def build_expander_vars(ctx)
          vars = ctx.macro_vars&.dup || {}
          vars[:char] = ctx.character&.name
          vars[:user] = ctx.user&.name
          vars
        end

        def default_expander
          ::TavernKit::Macro::V2::Engine.new
        end
      end
    end
  end
end
