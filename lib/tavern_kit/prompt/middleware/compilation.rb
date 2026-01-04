# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Prompt
    module Middleware
      # Middleware that compiles prompt entries into a final block array.
      #
      # This middleware:
      # - Walks relative entries in order
      # - Expands pinned groups inline
      # - Appends forced_last (PHI)
      # - Appends continue blocks (if :continue)
      # - Applies InjectionRegistry before/after blocks
      #
      class Compilation < Base
        # IDs that are forced to relative position
        FORCE_RELATIVE_IDS = %w[chat_history chat_examples].freeze

        # IDs that are always placed last
        FORCE_LAST_IDS = %w[post_history_instructions].freeze

        # Known pinned group IDs (empty groups are silently skipped, not warned)
        KNOWN_PINNED_IDS = %w[
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
          world_info_before_char_defs
          world_info_after_char_defs
          world_info_top_of_an
          world_info_bottom_of_an
          world_info_before_example_messages
          world_info_after_example_messages
          top_of_an
          bottom_of_an
        ].freeze

        private

        def before(ctx)
          partitioned = ctx[:partitioned_entries]
          return unless partitioned

          # Compile relative entries
          blocks = compile_prompt_entries(ctx, partitioned.relative)

          # Append forced_last entries (PHI)
          partitioned.forced_last.each do |pe|
            append_forced_last_entry(blocks, pe, ctx)
          end

          # Append continue blocks
          if ctx.continue_blocks&.any?
            blocks.concat(ctx.continue_blocks)
          end

          # Apply InjectionRegistry before/after blocks
          apply_injection_registry_relative_blocks!(blocks, ctx)

          ctx.blocks = blocks
        end

        def compile_prompt_entries(ctx, prompt_entries)
          blocks = []
          expander = ctx.expander || default_expander

          Array(prompt_entries).each do |pe|
            next unless pe.enabled?
            next if FORCE_LAST_IDS.include?(pe.id)
            next if pe.in_chat? && !FORCE_RELATIVE_IDS.include?(pe.id)

            if pe.pinned?
              group = ctx.pinned_groups[pe.id.to_s]

              if group.nil?
                # Try the pinned_group_resolver if available
                group = resolve_pinned_group(ctx, pe)

                if group.nil?
                  # Skip known pinned groups that are simply empty
                  next if KNOWN_PINNED_IDS.include?(pe.id.to_s)

                  if pe.content.to_s.strip.empty?
                    ctx.warn(unknown_pinned_prompt_warning(pe))
                    next
                  end

                  content = expand_macro(expander, ctx, pe.content, allow_outlets: true)
                  blocks << build_custom_block(pe, content, pinned_fallback: true)
                  next
                end
              end

              next if group.empty?

              group = apply_role_override(group, pe.role) unless FORCE_RELATIVE_IDS.include?(pe.id)
              blocks.concat(group)
            else
              next if pe.content.to_s.strip.empty?

              content = expand_macro(expander, ctx, pe.content, allow_outlets: true)
              blocks << build_custom_block(pe, content)
            end
          end

          blocks
        end

        def append_forced_last_entry(blocks, pe, ctx)
          return unless pe.enabled?

          expander = ctx.expander || default_expander

          if pe.pinned?
            group = ctx.pinned_groups[pe.id.to_s]

            if group.nil?
              # Try the pinned_group_resolver if available
              group = resolve_pinned_group(ctx, pe)

              if group.nil?
                # Skip known pinned groups that are simply empty
                return if KNOWN_PINNED_IDS.include?(pe.id.to_s)

                if pe.content.to_s.strip.empty?
                  ctx.warn(unknown_pinned_prompt_warning(pe))
                  return
                end

                content = expand_macro(expander, ctx, pe.content, allow_outlets: true)
                blocks << build_forced_last_block(pe, content, pinned_fallback: true)
                return
              end
            end

            return if group.empty?

            group = apply_role_override(group, pe.role) unless FORCE_RELATIVE_IDS.include?(pe.id)
            blocks.concat(group)
          else
            return if pe.content.to_s.strip.empty?

            content = expand_macro(expander, ctx, pe.content, allow_outlets: true)
            blocks << build_forced_last_block(pe, content)
          end
        end

        def build_custom_block(pe, content, pinned_fallback: false)
          metadata = {
            prompt_entry_id: pe.id,
            name: pe.name,
            pinned: false,
          }
          metadata[:pinned_fallback] = true if pinned_fallback

          Block.new(
            role: pe.role,
            content: content,
            slot: :custom_prompt,
            insertion_point: :relative,
            depth: pe.depth,
            order: pe.order,
            priority: pe.order,
            token_budget_group: :custom,
            metadata: metadata
          )
        end

        def build_forced_last_block(pe, content, pinned_fallback: false)
          metadata = {
            prompt_entry_id: pe.id,
            name: pe.name,
            pinned: false,
          }
          metadata[:pinned_fallback] = true if pinned_fallback

          Block.new(
            role: pe.role,
            content: content,
            slot: :custom_prompt,
            insertion_point: :relative,
            depth: pe.depth,
            order: pe.order,
            priority: 1000, # PHI is always last but never evicted
            token_budget_group: :system,
            metadata: metadata
          )
        end

        def apply_role_override(blocks, role)
          role_sym = role.to_s.strip.to_sym
          return blocks if role_sym == :""

          blocks.map { |b| b.with(role: role_sym) }
        end

        def apply_injection_registry_relative_blocks!(blocks, ctx)
          return blocks unless ctx.injection_registry && !ctx.injection_registry.empty?
          return blocks if blocks.nil? || blocks.empty?

          expander = ctx.expander || default_expander
          filter_ctx = build_injection_filter_context(ctx)

          before_blocks = []
          after_blocks = []

          ctx.injection_registry.each do |inj|
            next unless inj.position == :before || inj.position == :after
            next unless injection_filter_passes?(inj, filter_ctx, ctx)

            content = expand_macro(expander, ctx, inj.content, allow_outlets: true)
            next if content.empty?

            block = Block.new(
              role: inj.role,
              content: content,
              slot: :script_injection,
              insertion_point: :relative,
              order: 100,
              priority: 100,
              token_budget_group: :custom,
              tags: [:injection_registry],
              metadata: {
                injection_id: inj.id,
                position: inj.position,
                scan: inj.scan?,
                ephemeral: inj.ephemeral?,
                injected: true,
              }
            )

            (inj.position == :before ? before_blocks : after_blocks) << block
          end

          return blocks if before_blocks.empty? && after_blocks.empty?

          # Determine main prompt region end index
          chat_idx = blocks.index do |b|
            b.slot == :new_chat_prompt ||
              b.slot == :history ||
              b.slot == :user_message ||
              b.slot == :empty_user_message_replacement
          end
          chat_idx ||= blocks.length

          # Insert BEFORE_PROMPT at the start
          blocks.unshift(*before_blocks) if before_blocks.any?

          # Insert IN_PROMPT before chat history
          insert_at = chat_idx + before_blocks.length
          after_blocks.each_with_index do |b, idx|
            blocks.insert(insert_at + idx, b)
          end

          blocks
        end

        def unknown_pinned_prompt_warning(pe)
          name = pe.name.to_s.strip
          name_part = name.empty? ? "" : " name=#{name.inspect}"
          "Unknown pinned prompt #{pe.id.inspect}#{name_part} has no content and no pinned group; ignoring."
        end

        # Try to resolve a pinned group using the preset's resolver.
        #
        # @param ctx [Context]
        # @param pe [PromptEntry]
        # @return [Array<Block>, nil]
        def resolve_pinned_group(ctx, pe)
          resolver = ctx.effective_preset&.pinned_group_resolver
          return nil unless resolver.respond_to?(:call)

          result = resolver.call(
            id: pe.id.to_s,
            entry: pe,
            context: ctx
          )

          return nil unless result.is_a?(Array) && result.any?

          result
        rescue StandardError => e
          ctx.warn("Pinned group resolver error for #{pe.id.inspect}: #{e.class}: #{e.message}")
          nil
        end

        def expand_macro(expander, ctx, text, allow_outlets:)
          vars = build_expander_vars(ctx)
          vars[:outlets] = allow_outlets ? ctx.outlets : nil
          expander.expand(text.to_s, vars, allow_outlets: allow_outlets)
        end

        def build_injection_filter_context(ctx)
          {
            character: ctx.character,
            user: ctx.user,
            preset: ctx.effective_preset,
            history_messages: ctx.effective_history,
            user_message: ctx.user_message.to_s,
            generation_type: ctx.generation_type,
            group: ctx.group,
            macro_vars: ctx.macro_vars,
            outlets: ctx.outlets || {},
            lore_result: ctx.lore_result,
            chat_scan_messages: ctx.chat_scan_messages,
            default_chat_depth: ctx.default_chat_depth,
            turn_count: ctx.turn_count,
          }
        end

        def injection_filter_passes?(inj, filter_ctx, ctx)
          filter = inj&.filter
          return true unless filter.respond_to?(:call)

          ok = filter.arity == 0 ? filter.call : filter.call(filter_ctx)
          !!ok
        rescue StandardError => e
          ctx.warn("Injection filter error for #{inj&.id.inspect}: #{e.class}: #{e.message}")
          false
        end
      end
    end
  end
end
