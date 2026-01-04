# frozen_string_literal: true

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
        # @return [#call] the next middleware or terminal handler
        attr_reader :app

        # @return [Hash] middleware options
        attr_reader :options

        # Initialize middleware with next app and options.
        #
        # @param app [#call] next middleware in chain
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
        # Subclasses typically override {#before} and/or {#after}
        # rather than {#call} itself.
        #
        # @param ctx [Context] the prompt context
        # @return [Context] the processed context
        def call(ctx)
          before(ctx)
          @app.call(ctx)
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
          vars = ctx.macro_vars&.dup || {}

          # Core identity macros - these must be set first for pre-expansion
          char_name = ctx.character&.name.to_s
          user_name = ctx.user&.name.to_s
          vars[:char] = char_name
          vars[:user] = user_name

          # Helper to pre-expand {{char}} and {{user}} in character fields
          pre_expand = ->(text) do
            return "" if text.nil? || text.empty?
            text.to_s
              .gsub(/\{\{char\}\}/i, char_name)
              .gsub(/\{\{user\}\}/i, user_name)
          end

          # Character field macros (pre-expanded with char/user)
          if ctx.character
            data = ctx.character.data
            vars[:description] = pre_expand.call(data.description)
            vars[:scenario] = pre_expand.call(data.scenario)
            vars[:personality] = pre_expand.call(data.personality)
            vars[:charprompt] = pre_expand.call(data.system_prompt)
            vars[:charinstruction] = pre_expand.call(data.post_history_instructions)
            vars[:charjailbreak] = pre_expand.call(data.post_history_instructions)
            vars[:mesexamplesraw] = pre_expand.call(data.mes_example)
            vars[:mesexamples] = pre_expand.call(format_mes_examples(data.mes_example.to_s))
            vars[:charversion] = data.character_version.to_s
            vars[:char_version] = data.character_version.to_s
            vars[:creatornotes] = pre_expand.call(data.creator_notes)

            # Depth prompt from extensions
            extensions = Utils.deep_stringify_keys(data.extensions || {})
            depth_prompt = extensions["depth_prompt"]
            vars[:chardepthprompt] = pre_expand.call(depth_prompt.is_a?(Hash) ? depth_prompt["prompt"].to_s : "")
          end

          # User macros (pre-expanded)
          vars[:persona] = pre_expand.call(ctx.user&.persona_text)

          # Group macros
          if ctx.group
            members = ctx.group.members || []
            muted = ctx.group.muted || []
            member_names = members.map { |m| m.respond_to?(:name) ? m.name : m.to_s }
            non_muted_names = member_names.reject { |name| muted.include?(name) }

            # {{group}} - all group members
            vars[:group] = member_names.any? ? member_names.join(", ") : char_name

            # {{groupNotMuted}} - group members not in muted list
            vars[:groupnotmuted] = non_muted_names.any? ? non_muted_names.join(", ") : char_name

            # {{charIfNotGroup}} - char name in single chat, group list in group chat
            vars[:charifnotgroup] = member_names.any? ? member_names.join(", ") : char_name

            # {{notChar}} - everyone except current character (user + other members)
            # Use current_character_or to handle stale/invalid current_character values
            current_char = ctx.group.current_character_or(char_name)
            others = member_names.reject { |name| name == current_char }
            others_with_user = (others + [user_name]).reject { |v| v.to_s.strip.empty? }
            vars[:notchar] = others_with_user.any? ? others_with_user.join(", ") : user_name
          else
            vars[:group] = char_name
            vars[:groupnotmuted] = char_name
            vars[:charifnotgroup] = char_name
            vars[:notchar] = user_name
          end

          # Current input/message
          vars[:input] = ctx.user_message.to_s

          # Last chat message macro (for continue nudge)
          history = ctx.effective_history
          if history && history.respond_to?(:to_a) && history.to_a.any?
            last_msg = history.to_a.last
            vars[:lastchatmessage] = last_msg&.content.to_s
          else
            vars[:lastchatmessage] = ""
          end

          # Preset-derived macros
          preset = ctx.effective_preset
          if preset
            vars[:maxprompt] = preset.context_window_tokens.to_s
          end

          # Generation type
          vars[:lastgenerationtype] = ctx.generation_type.to_s

          # Environment flags (ST defaults to "false" for unknown)
          vars[:ismobile] ||= "false"

          # Populate global macros from TavernKit.macros registry
          populate_global_macros!(vars, ctx)

          # Merge overrides last
          vars.merge(overrides)
        end

        # Populate global macros from TavernKit.macros registry.
        #
        # Creates a MacroContext from the pipeline context and uses it to populate
        # custom macro values into the vars hash.
        #
        # @param vars [Hash] mutable vars hash
        # @param ctx [Context] pipeline context
        # @return [Hash] the modified vars hash
        def populate_global_macros!(vars, ctx)
          return vars if ::TavernKit.macros.size.zero?

          # Build a MacroContext for the registry's populate_env
          macro_ctx = ::TavernKit::MacroContext.new(
            card: ctx.character,
            user: ctx.user,
            history: ctx.effective_history,
            local_store: ctx.variables_store || ::TavernKit::ChatVariables.wrap(nil),
            preset: ctx.effective_preset,
            generation_type: ctx.generation_type,
            group: ctx.group,
            input: ctx.user_message.to_s
          )

          ::TavernKit.macros.populate_env(vars, macro_ctx)
          vars
        end

        private_class_method def self.format_mes_examples(examples_str)
          return "" if examples_str.to_s.strip.empty? || examples_str == "<START>"

          normalized = examples_str.to_s
          normalized = "<START>\n#{normalized.strip}" unless normalized.strip.start_with?("<START>")

          normalized
            .split(/<START>/i)
            .drop(1)
            .map { |block| "<START>\n#{block.strip}\n" }
            .join
        end

        def format_mes_examples(examples_str)
          return "" if examples_str.to_s.strip.empty? || examples_str == "<START>"

          normalized = examples_str.to_s
          normalized = "<START>\n#{normalized.strip}" unless normalized.strip.start_with?("<START>")

          normalized
            .split(/<START>/i)
            .drop(1)
            .map { |block| "<START>\n#{block.strip}\n" }
            .join
        end

        # Get default macro expander
        def default_expander
          ::TavernKit::Macro::V2::Engine.new
        end
      end
    end
  end
end
