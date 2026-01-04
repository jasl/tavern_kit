# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Prompt
    module Middleware
      # Middleware that builds pinned group content.
      #
      # Pinned groups are predefined content slots that can be referenced
      # by prompt entries. This middleware builds the content for:
      # - main_prompt, persona_description
      # - character_description, personality, scenario
      # - chat_examples (parsed → message blocks)
      # - chat_history (history → message blocks)
      # - world_info_* positions (8 positions)
      # - authors_note, enhance_definitions, auxiliary_prompt
      #
      class PinnedGroups < Base
        # Known pinned group IDs
        KNOWN_PINNED_GROUPS = %w[
          main_prompt
          persona_description
          character_description
          personality
          character_personality
          scenario
          chat_examples
          chat_history
          authors_note
          enhance_definitions
          auxiliary_prompt
          post_history_instructions
          world_info_before
          world_info_after
          top_of_an
          bottom_of_an
        ].freeze

        private

        def before(ctx)
          ctx.pinned_groups = build_pinned_groups(ctx)
        end

        def build_pinned_groups(ctx)
          groups = {}

          # Core prompts
          groups["main_prompt"] = build_main_prompt_blocks(ctx)
          groups["persona_description"] = build_persona_blocks(ctx)
          groups["character_description"] = build_character_description_blocks(ctx)
          groups["character_personality"] = build_personality_blocks(ctx)
          groups["personality"] = groups["character_personality"] # Alias for compatibility
          groups["scenario"] = build_scenario_blocks(ctx)
          groups["enhance_definitions"] = build_enhance_definitions_blocks(ctx)
          groups["auxiliary_prompt"] = build_auxiliary_prompt_blocks(ctx)
          groups["post_history_instructions"] = build_phi_blocks(ctx)

          # Chat examples
          groups["chat_examples"] = build_chat_examples_blocks(ctx)

          # Chat history
          groups["chat_history"] = build_chat_history_blocks(ctx)

          # Author's Note
          groups["authors_note"] = build_authors_note_blocks(ctx)

          # World Info positions (using full IDs that match default prompt entries)
          groups["world_info_before_char_defs"] = build_world_info_position_blocks(ctx, :before_char_defs)
          groups["world_info_after_char_defs"] = build_world_info_position_blocks(ctx, :after_char_defs)
          groups["world_info_top_of_an"] = build_world_info_position_blocks(ctx, :top_of_an)
          groups["world_info_bottom_of_an"] = build_world_info_position_blocks(ctx, :bottom_of_an)
          groups["world_info_before_example_messages"] = build_world_info_position_blocks(ctx, :before_example_messages)
          groups["world_info_after_example_messages"] = build_world_info_position_blocks(ctx, :after_example_messages)

          # Remove empty groups
          groups.reject! { |_, v| v.nil? || v.empty? }

          groups
        end

        def build_main_prompt_blocks(ctx)
          preset = ctx.effective_preset
          content = resolve_main_prompt_content(ctx, preset)
          return [] if content.to_s.strip.empty?

          [Block.new(
            role: :system,
            content: content,
            slot: :main_prompt,
            priority: 1,
            token_budget_group: :system,
            tags: [:core]
          )]
        end

        def resolve_main_prompt_content(ctx, preset)
          expander = ctx.expander || default_expander
          entry = find_prompt_entry(ctx, "main_prompt")
          forbid_overrides = entry&.forbid_overrides

          if preset.prefer_char_prompt && Utils.presence(ctx.character.data.system_prompt) && !forbid_overrides
            expand_with_original(
              expander, ctx,
              template: ctx.character.data.system_prompt,
              original_template: preset.main_prompt,
              allow_outlets: true
            )
          else
            expand_macro(expander, ctx, preset.main_prompt, allow_outlets: true)
          end
        end

        def build_persona_blocks(ctx)
          persona = Utils.presence(ctx.user&.persona_text)
          return [] if persona.nil?

          expander = ctx.expander || default_expander
          content = expand_macro(expander, ctx, persona, allow_outlets: false)
          return [] if content.to_s.strip.empty?

          [Block.new(
            role: :system,
            content: content,
            slot: :persona,
            priority: 10,
            token_budget_group: :system,
            tags: [:persona]
          )]
        end

        def build_character_description_blocks(ctx)
          desc = Utils.presence(ctx.character.data.description)
          return [] if desc.nil?

          expander = ctx.expander || default_expander
          content = expand_macro(expander, ctx, desc, allow_outlets: false)
          return [] if content.to_s.strip.empty?

          [Block.new(
            role: :system,
            content: content,
            slot: :character_description,
            priority: 5,
            token_budget_group: :system,
            tags: [:character]
          )]
        end

        def build_personality_blocks(ctx)
          raw = ctx.character.data.personality.to_s
          return [] if raw.empty?

          expander = ctx.expander || default_expander
          expanded = expand_macro(expander, ctx, raw, allow_outlets: false)
          return [] if expanded.empty?

          preset = ctx.effective_preset
          content = if preset.personality_format && !preset.personality_format.to_s.empty?
            expand_macro(
              expander, ctx,
              preset.personality_format,
              allow_outlets: false,
              overrides: { personality: expanded }
            )
          else
            expanded
          end

          return [] if content.to_s.strip.empty?

          [Block.new(
            role: :system,
            content: content,
            slot: :character_personality,
            priority: 5,
            token_budget_group: :system,
            tags: [:character]
          )]
        end

        def build_scenario_blocks(ctx)
          raw = ctx.character.data.scenario.to_s
          return [] if raw.empty?

          expander = ctx.expander || default_expander
          expanded = expand_macro(expander, ctx, raw, allow_outlets: false)
          return [] if expanded.empty?

          preset = ctx.effective_preset
          content = if preset.scenario_format && !preset.scenario_format.to_s.empty?
            expand_macro(
              expander, ctx,
              preset.scenario_format,
              allow_outlets: false,
              overrides: { scenario: expanded }
            )
          else
            expanded
          end

          return [] if content.to_s.strip.empty?

          [Block.new(
            role: :system,
            content: content,
            slot: :scenario,
            priority: 5,
            token_budget_group: :system,
            tags: [:scenario]
          )]
        end

        def build_enhance_definitions_blocks(ctx)
          preset = ctx.effective_preset
          template = preset.enhance_definitions.to_s
          return [] if template.strip.empty?

          expander = ctx.expander || default_expander
          content = expand_macro(expander, ctx, template, allow_outlets: false)
          return [] if content.to_s.strip.empty?

          [Block.new(
            role: :system,
            content: content,
            slot: :enhance_definitions,
            priority: 6,
            token_budget_group: :system,
            tags: [:core]
          )]
        end

        def build_auxiliary_prompt_blocks(ctx)
          preset = ctx.effective_preset
          template = preset.auxiliary_prompt.to_s
          return [] if template.strip.empty?

          expander = ctx.expander || default_expander
          content = expand_macro(expander, ctx, template, allow_outlets: false)
          return [] if content.to_s.strip.empty?

          [Block.new(
            role: :system,
            content: content,
            slot: :auxiliary_prompt,
            priority: 6,
            token_budget_group: :system,
            tags: [:core]
          )]
        end

        def build_phi_blocks(ctx)
          preset = ctx.effective_preset
          expander = ctx.expander || default_expander
          entry = find_prompt_entry(ctx, "post_history_instructions")
          forbid_overrides = entry&.forbid_overrides

          template = nil
          original_template = nil
          use_override = false

          if preset.prefer_char_instructions && Utils.presence(ctx.character.data.post_history_instructions) && !forbid_overrides
            template = ctx.character.data.post_history_instructions
            original_template = preset.post_history_instructions
            use_override = true
          else
            template = preset.post_history_instructions
            original_template = ""
          end

          return [] if template.to_s.strip.empty?

          content = if use_override
            expand_with_original(
              expander, ctx,
              template: template,
              original_template: original_template,
              allow_outlets: true
            )
          else
            expand_macro(expander, ctx, template, allow_outlets: true)
          end

          return [] if content.to_s.strip.empty?

          [Block.new(
            role: :system,
            content: content,
            slot: :post_history_instructions,
            priority: 2,
            token_budget_group: :system,
            tags: [:core]
          )]
        end

        def build_chat_examples_blocks(ctx)
          raw = ctx.character.data.mes_example.to_s
          return [] if raw.strip.empty?

          expander = ctx.expander || default_expander
          preset = ctx.effective_preset
          blocks = []

          ExampleParser.parse_blocks(raw).each_with_index do |msgs, idx|
            if Utils.presence(preset.new_example_chat)
              new_example_content = expand_macro(expander, ctx, preset.new_example_chat, allow_outlets: false)
              blocks << Block.new(
                role: :system,
                content: new_example_content,
                slot: :new_example_chat,
                priority: 200 + idx,
                token_budget_group: :examples,
                tags: [:examples],
                metadata: { example_block: idx }
              )
            end

            msgs.each do |m|
              content = expand_macro(expander, ctx, m.content.to_s, allow_outlets: false)
              blocks << Block.new(
                role: m.role.to_sym,
                content: content,
                name: m.name,
                slot: :examples,
                priority: 200 + idx,
                token_budget_group: :examples,
                tags: [:examples],
                metadata: { example_block: idx }
              )
            end
          end

          blocks
        end

        def build_chat_history_blocks(ctx)
          history = ctx.effective_history
          expander = ctx.expander || default_expander

          blocks = history.to_a.map.with_index do |msg, idx|
            content = expand_macro(expander, ctx, msg.content.to_s, allow_outlets: false)
            Block.new(
              role: msg.role.to_sym,
              content: content,
              name: msg.name, # Preserve message name for OpenAI
              slot: :history,
              priority: 50,
              token_budget_group: :history,
              tags: [:history],
              metadata: { history_index: idx }
            )
          end

          # Add current user message as the last message
          user_message_content = ctx.user_message.to_s
          unless user_message_content.strip.empty? && !ctx.effective_preset&.replace_empty_message
            user_content = expand_macro(expander, ctx, user_message_content, allow_outlets: false)
            blocks << Block.new(
              role: :user,
              content: user_content,
              slot: :user_message,
              priority: 50,
              token_budget_group: :history,
              tags: [:history, :current_message],
              metadata: { history_index: history.size, name: ctx.user&.name, current_message: true }
            )
          end

          blocks
        end

        def build_authors_note_blocks(ctx)
          preset = ctx.effective_preset
          template = preset.authors_note.to_s
          return [] if template.strip.empty?

          expander = ctx.expander || default_expander
          content = expand_macro(expander, ctx, template, allow_outlets: false)
          return [] if content.to_s.strip.empty?

          # Merge top_of_an and bottom_of_an World Info into the authors_note block
          # ST behavior: top_of_an content comes before AN, bottom_of_an after
          lore_result = ctx.lore_result

          top_an_parts = []
          bottom_an_parts = []

          if lore_result
            top_entries = lore_result.selected_by_position[:top_of_an] || []
            bottom_entries = lore_result.selected_by_position[:bottom_of_an] || []

            top_entries.each do |entry|
              expanded = expand_macro(expander, ctx, entry.content.to_s, allow_outlets: false)
              top_an_parts << expanded unless expanded.to_s.strip.empty?
            end

            bottom_entries.each do |entry|
              expanded = expand_macro(expander, ctx, entry.content.to_s, allow_outlets: false)
              bottom_an_parts << expanded unless expanded.to_s.strip.empty?
            end
          end

          # Build combined content: TOP_AN + AN_CONTENT + BOTTOM_AN
          parts = []
          parts.concat(top_an_parts)
          parts << content
          parts.concat(bottom_an_parts)

          combined_content = parts.join("\n")

          [Block.new(
            role: preset.authors_note_role || :system,
            content: combined_content,
            slot: :authors_note,
            priority: 3,
            token_budget_group: :system,
            tags: [:authors_note]
          )]
        end

        def build_world_info_position_blocks(ctx, position)
          lore_result = ctx.lore_result
          return [] unless lore_result

          expander = ctx.expander || default_expander
          preset = ctx.effective_preset
          wi_format = preset.wi_format.to_s

          entries = lore_result.selected_by_position[position] || []
          entries.map.with_index do |entry, idx|
            content = expand_macro(expander, ctx, entry.content.to_s, allow_outlets: false)

            # Apply wi_format if present (uses {0} as placeholder)
            unless wi_format.empty?
              content = wi_format.gsub("{0}", content)
            end

            Block.new(
              role: entry.role || :system,
              content: content,
              slot: :"world_info_#{position}",
              priority: lore_block_priority(entry),
              token_budget_group: :lore,
              tags: [:lore, :world_info, (entry.constant? ? :constant : nil)].compact,
              metadata: {
                uid: entry.uid,
                constant: entry.constant?,
                insertion_order: entry.insertion_order,
                source: entry.source,
                book_name: entry.book_name,
                position: position,
                seq: idx,
              }
            )
          end
        end

        def lore_block_priority(entry)
          # Higher insertion_order = lower priority (appears later in eviction)
          base = 100
          base - [entry.insertion_order.to_i, 0].max.clamp(0, 99)
        end

        def find_prompt_entry(ctx, id)
          ctx.prompt_entries&.find { |pe| pe.id.to_s == id.to_s }
        end

        def expand_macro(expander, ctx, text, allow_outlets:, overrides: {})
          vars = build_expander_vars(ctx, overrides: overrides)
          vars[:outlets] = allow_outlets ? ctx.outlets : nil
          expander.expand(text.to_s, vars, allow_outlets: allow_outlets)
        end

        def expand_with_original(expander, ctx, template:, original_template:, allow_outlets:)
          vars = build_expander_vars(ctx)
          original_expanded = expander.expand(original_template.to_s, vars, allow_outlets: false)
          vars[:original] = original_expanded
          vars[:outlets] = allow_outlets ? ctx.outlets : nil
          expander.expand(template.to_s, vars, allow_outlets: allow_outlets)
        end
      end
    end
  end
end
