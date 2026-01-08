# frozen_string_literal: true

require_relative "../chat_variables"
require_relative "../macro_context"
require_relative "../utils"

module TavernKit
  module Prompt
    # Builds ST-compatible macro variables for a prompt context.
    #
    # This is used by the prompt pipeline for macro expansion, and is also
    # intentionally public so host applications can pre-expand per-character
    # content (e.g., group depth prompts) using the same semantics as TavernKit.
    module ExpanderVars
      class << self
        # @param ctx [Prompt::Context] prompt context
        # @param overrides [Hash] additional vars to merge (wins over computed vars)
        # @return [Hash] expander vars for Macro engines
        def build(ctx, overrides: {})
          vars = ctx.macro_vars&.dup || {}

          # Core identity macros - set first for pre-expansion.
          char_name = ctx.character&.name.to_s
          user_name = ctx.user&.name.to_s
          vars[:char] = char_name
          vars[:user] = user_name

          # Helper to pre-expand {{char}} and {{user}} in character fields.
          pre_expand = ->(text) do
            return "" if text.nil? || text.empty?

            text
              .to_s
              .gsub(/\{\{char\}\}/i, char_name)
              .gsub(/\{\{user\}\}/i, user_name)
          end

          # Character field macros (pre-expanded with char/user).
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

            # Depth prompt from extensions.
            extensions = Utils.deep_stringify_keys(data.extensions || {})
            depth_prompt = extensions["depth_prompt"]
            vars[:chardepthprompt] = pre_expand.call(depth_prompt.is_a?(Hash) ? depth_prompt["prompt"].to_s : "")
          end

          # User macros (pre-expanded).
          vars[:persona] = pre_expand.call(ctx.user&.persona_text)

          # Group macros.
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

          # Current input/message.
          vars[:input] = ctx.user_message.to_s

          # Last chat message macro (for continue nudge).
          history = ctx.effective_history
          last_msg = history&.last
          vars[:lastchatmessage] = last_msg ? last_msg.content.to_s : ""

          # Preset-derived macros.
          preset = ctx.effective_preset
          vars[:maxprompt] = preset.context_window_tokens.to_s if preset.context_window_tokens

          # Generation type.
          vars[:lastgenerationtype] = ctx.generation_type.to_s

          # Environment flags (ST defaults to "false" for unknown).
          vars[:ismobile] ||= "false"

          populate_global_macros!(vars, ctx)

          vars.merge(overrides)
        end

        # Populate global macros from TavernKit.macros registry.
        #
        # @param vars [Hash] mutable vars hash
        # @param ctx [Prompt::Context] prompt context
        # @return [Hash] the modified vars hash
        def populate_global_macros!(vars, ctx)
          return vars if ::TavernKit.macros.size.zero?

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
      end
    end
  end
end
