# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Prompt
    module Middleware
      # Middleware that injects content into chat history.
      #
      # This middleware handles:
      # - In-chat prompt entries (depth/order)
      # - World Info at-depth entries
      # - InjectionRegistry chat injections
      # - Sorting by: depth → order → role
      # - Merging same depth+order+role blocks
      #
      class Injection < Base
        # IDs that are forced to relative position
        FORCE_RELATIVE_IDS = %w[chat_history chat_examples].freeze

        private

        def before(ctx)
          partitioned = ctx[:partitioned_entries]
          return unless partitioned

          chat_history_active = partitioned.relative.any? { |pe| pe.id == "chat_history" }
          return unless chat_history_active

          # Build in-chat injections
          injection_blocks = build_in_chat_injections(ctx, partitioned.in_chat)

          # Inject into chat history blocks
          chat_blocks = ctx.pinned_groups["chat_history"]
          return unless chat_blocks&.any?

          chat_blocks = inject_in_chat_blocks(chat_blocks, injection_blocks)

          # Handle :continue generation type
          if ctx.generation_type == :continue
            chat_blocks, continue_blocks = extract_continue_blocks(chat_blocks)
            ctx.continue_blocks = continue_blocks

            # Apply continue-specific processing
            chat_blocks = apply_continue_behavior(chat_blocks, ctx)
          end

          # Apply post-injection transformations
          chat_blocks = apply_replace_empty_message(chat_blocks, ctx)
          chat_blocks = prepend_new_chat_prompt(chat_blocks, ctx)
          chat_blocks = append_group_nudge_prompt(chat_blocks, ctx)

          ctx.pinned_groups["chat_history"] = chat_blocks
        end

        def build_in_chat_injections(ctx, in_chat_entries)
          injections = []
          expander = ctx.expander || default_expander

          # Process in-chat prompt entries
          Array(in_chat_entries).each_with_index do |pe, seq|
            next unless pe.enabled?
            next if FORCE_RELATIVE_IDS.include?(pe.id)

            if pe.pinned?
              blocks = ctx.pinned_groups[pe.id.to_s]

              if blocks.nil?
                # Skip known pinned groups that are simply empty
                next if Compilation::KNOWN_PINNED_IDS.include?(pe.id.to_s)

                if pe.content.to_s.strip.empty?
                  ctx.warn(unknown_pinned_prompt_warning(pe))
                  next
                end

                content = expand_macro(expander, ctx, pe.content, allow_outlets: true)
                injections << build_in_chat_block(pe, content, seq, pinned_fallback: true)
                next
              end

              next if blocks.empty?

              flattened = flatten_pinned_group_for_in_chat(blocks, pe, seq)
              injections.concat(flattened)
            else
              next if pe.content.to_s.strip.empty?

              content = expand_macro(expander, ctx, pe.content, allow_outlets: true)
              injections << build_in_chat_block(pe, content, seq)
            end
          end

          # Add World Info at-depth entries
          injections.concat(build_world_info_at_depth_injections(ctx, expander))

          # Add character depth prompt
          depth_block = build_character_depth_prompt_injection(ctx, expander)
          injections << depth_block if depth_block

          # Add InjectionRegistry chat injections
          injections.concat(build_injection_registry_chat_injections(ctx, expander))

          injections
        end

        def build_in_chat_block(pe, content, seq, pinned_fallback: false)
          metadata = {
            prompt_entry_id: pe.id,
            name: pe.name,
            seq: seq,
            injection_order: pe.order,
            injected: true,
          }
          metadata[:pinned_fallback] = true if pinned_fallback

          Block.new(
            role: pe.role,
            content: content,
            slot: :in_chat_prompt,
            insertion_point: :in_chat,
            depth: pe.depth,
            order: pe.order,
            priority: pe.order,
            token_budget_group: :custom,
            metadata: metadata
          )
        end

        def build_world_info_at_depth_injections(ctx, expander)
          lore_result = ctx.lore_result
          return [] unless lore_result

          entries = lore_result.selected_by_position[:at_depth] || []
          entries.map.with_index do |e, idx|
            content = expand_macro(expander, ctx, e.content, allow_outlets: false)
            Block.new(
              role: e.role,
              content: content,
              slot: :world_info_at_depth,
              insertion_point: :in_chat,
              depth: e.depth,
              order: 100,
              priority: lore_block_priority(e),
              token_budget_group: :lore,
              tags: [:lore, :world_info, (e.constant? ? :constant : nil)].compact,
              metadata: {
                uid: e.uid,
                constant: e.constant?,
                insertion_order: e.insertion_order,
                source: e.source,
                book_name: e.book_name,
                extension: true,
                injection_order: 100,
                seq: 1_000_000 + idx,
                injected: true,
              }
            )
          end
        end

        def build_character_depth_prompt_injection(ctx, expander)
          raw = character_depth_prompt_text(ctx)
          return nil if raw.to_s.strip.empty?

          content = expand_macro(expander, ctx, raw, allow_outlets: false)
          return nil if content.to_s.strip.empty?

          depth = character_depth_prompt_depth(ctx)
          role = character_depth_prompt_role(ctx)

          Block.new(
            role: role,
            content: content,
            slot: :character_depth_prompt,
            insertion_point: :in_chat,
            depth: depth,
            order: 100,
            priority: 100,
            token_budget_group: :system,
            tags: [:character_depth_prompt],
            metadata: {
              extension: true,
              injected: true,
              injection_order: 100,
              insertion_order: 1_000_000,
              seq: 2_000_000,
            }
          )
        end

        def character_depth_prompt_text(ctx)
          extensions = ctx.character&.data&.extensions
          return "" unless extensions.is_a?(Hash)

          depth_prompt = extensions["depth_prompt"]
          return "" unless depth_prompt.is_a?(Hash)

          depth_prompt["prompt"].to_s
        end

        def character_depth_prompt_depth(ctx)
          extensions = ctx.character&.data&.extensions
          return 4 unless extensions.is_a?(Hash)

          depth_prompt = extensions["depth_prompt"]
          return 4 unless depth_prompt.is_a?(Hash)

          depth = depth_prompt["depth"]
          depth.nil? ? 4 : depth.to_i
        end

        def character_depth_prompt_role(ctx)
          extensions = ctx.character&.data&.extensions
          return :system unless extensions.is_a?(Hash)

          depth_prompt = extensions["depth_prompt"]
          return :system unless depth_prompt.is_a?(Hash)

          role = depth_prompt["role"]
          role.nil? ? :system : role.to_s.to_sym
        end

        def build_injection_registry_chat_injections(ctx, expander)
          return [] unless ctx.injection_registry && !ctx.injection_registry.empty?

          filter_ctx = build_injection_filter_context(ctx)
          result = []
          seq_base = 3_000_000

          ctx.injection_registry.each_with_index do |inj, idx|
            next unless inj.position == :chat
            next unless injection_filter_passes?(inj, filter_ctx, ctx)

            content = expand_macro(expander, ctx, inj.content, allow_outlets: true)
            next if content.empty?

            result << Block.new(
              role: inj.role,
              content: content,
              slot: :script_injection,
              insertion_point: :in_chat,
              depth: inj.depth,
              order: 100,
              priority: 100,
              token_budget_group: :custom,
              tags: [:injection_registry],
              metadata: {
                injection_id: inj.id,
                scan: inj.scan?,
                ephemeral: inj.ephemeral?,
                extension: true,
                injected: true,
                injection_order: 100,
                insertion_order: 2_000_000,
                seq: seq_base + idx,
              }
            )
          end

          result
        end

        def inject_in_chat_blocks(chat_blocks, injections)
          injections = Array(injections).compact
          return chat_blocks if injections.empty?

          base_len = chat_blocks.length

          # Group injections by insertion index
          insert_map = Hash.new { |h, k| h[k] = [] }
          injections.each do |b|
            depth = b.depth.to_i
            idx = base_len - depth
            idx = 0 if idx < 0
            idx = base_len if idx > base_len
            insert_map[idx] << b
          end

          # Insert at each position
          offset = 0
          insert_map.keys.sort.each do |idx|
            blocks_to_insert = build_in_chat_insertions(insert_map[idx])
            blocks_to_insert.each do |b|
              chat_blocks.insert(idx + offset, b)
              offset += 1
            end
          end

          chat_blocks
        end

        def build_in_chat_insertions(blocks)
          blocks = Array(blocks).compact
          return [] if blocks.empty?

          by_order = blocks.group_by(&:order)
          orders = by_order.keys.sort

          result = []
          role_order = %i[assistant user system].freeze

          orders.each do |order|
            grouped = by_order.fetch(order, [])
            by_role = grouped.group_by(&:role)

            role_order.each do |role|
              role_blocks = Array(by_role[role]).compact
              next if role_blocks.empty?

              prompt_blocks = role_blocks.reject { |b| b.metadata[:extension] }
              extension_blocks = role_blocks.select { |b| b.metadata[:extension] }

              if prompt_blocks.any?
                result << merge_in_chat_prompt_blocks(prompt_blocks)
              end

              if extension_blocks.any?
                result.concat(sort_in_chat_extension_blocks(extension_blocks))
              end
            end
          end

          result
        end

        def merge_in_chat_prompt_blocks(blocks)
          blocks = Array(blocks).compact
          sorted = blocks.sort_by do |b|
            [b.metadata[:seq].to_i, b.metadata[:prompt_entry_id].to_s, b.id.to_s]
          end

          merged_content = sorted.map(&:content).join("\n").strip
          first = sorted.first

          merged_ids = sorted.map { |b| b.metadata[:prompt_entry_id] }.compact.uniq
          merged_metadata = first.metadata.dup
          if sorted.length > 1
            merged_metadata[:merged_count] = sorted.length
            merged_metadata[:merged_ids] = merged_ids if merged_ids.any?
          end

          Block.new(
            role: first.role,
            content: merged_content,
            slot: first.slot,
            insertion_point: first.insertion_point,
            depth: first.depth,
            order: first.order,
            priority: first.priority,
            token_budget_group: first.token_budget_group,
            tags: first.tags,
            metadata: merged_metadata
          )
        end

        def sort_in_chat_extension_blocks(blocks)
          Array(blocks).compact.sort_by do |b|
            [
              b.metadata[:insertion_order].to_i,
              b.metadata[:seq].to_i,
              b.metadata[:uid].to_s,
              b.id.to_s,
            ]
          end
        end

        def flatten_pinned_group_for_in_chat(blocks, pe, seq)
          return [] if blocks.empty?

          # Special case for Author's Note
          return flatten_authors_note_group_for_in_chat(blocks, pe, seq) if pe.id.to_s == "authors_note"

          by_role = blocks.group_by { |b| b.role.to_s }
          result = []
          ordered_roles = %w[assistant user system].freeze
          extra_roles = (by_role.keys - ordered_roles).sort

          (ordered_roles + extra_roles).each do |role|
            role_blocks = by_role[role]
            next if role_blocks.nil? || role_blocks.empty?

            sorted_role_blocks = role_blocks.sort_by.with_index { |b, idx| [b.priority, b.order, idx] }
            merged_content = sorted_role_blocks.map(&:content).join("\n")

            first = sorted_role_blocks.first
            merged_metadata = sorted_role_blocks.reduce({}) { |acc, b| acc.merge(b.metadata) }
            merged_metadata[:prompt_entry_id] = pe.id
            merged_metadata[:name] = pe.name
            merged_metadata[:flattened_from] = sorted_role_blocks.length
            merged_metadata[:seq] = seq
            merged_metadata[:injection_order] = pe.order
            merged_metadata[:injected] = true

            result << Block.new(
              role: role.to_sym,
              content: merged_content,
              slot: first.slot,
              insertion_point: :in_chat,
              depth: pe.depth,
              order: pe.order,
              priority: pe.order,
              token_budget_group: first.token_budget_group,
              tags: first.tags,
              metadata: merged_metadata
            )
          end

          result
        end

        def flatten_authors_note_group_for_in_chat(blocks, pe, seq)
          by_role = blocks.group_by { |b| b.role.to_s }
          result = []
          ordered_roles = %w[assistant user system].freeze
          extra_roles = (by_role.keys - ordered_roles).sort

          (ordered_roles + extra_roles).each do |role|
            role_blocks = by_role[role]
            next if role_blocks.nil? || role_blocks.empty?

            merged_content = role_blocks.map(&:content).join("\n").strip
            base = role_blocks.find { |b| b.slot == :authors_note } || role_blocks.first

            merged_metadata = role_blocks.reduce({}) { |acc, b| acc.merge(b.metadata) }
            merged_metadata[:prompt_entry_id] = pe.id
            merged_metadata[:name] = pe.name
            merged_metadata[:flattened_from] = role_blocks.length
            merged_metadata[:seq] = seq
            merged_metadata[:injection_order] = pe.order
            merged_metadata[:injected] = true
            merged_metadata[:authors_note_components] = role_blocks.map(&:slot).compact

            tags = role_blocks.flat_map(&:tags).uniq
            tags << :authors_note unless tags.include?(:authors_note)

            result << Block.new(
              role: base.role,
              content: merged_content,
              slot: :authors_note,
              insertion_point: :in_chat,
              depth: pe.depth,
              order: pe.order,
              priority: pe.order,
              token_budget_group: base.token_budget_group,
              tags: tags,
              metadata: merged_metadata
            )
          end

          result
        end

        def extract_continue_blocks(blocks)
          return [blocks, nil] if blocks.empty?

          # Find the last assistant block
          last_assistant_idx = blocks.rindex { |b| b.role == :assistant }
          return [blocks, nil] if last_assistant_idx.nil?

          # Extract continue blocks (everything after last assistant block)
          continue_blocks = blocks[(last_assistant_idx + 1)..]
          chat_blocks = blocks[0..last_assistant_idx]

          [chat_blocks, continue_blocks]
        end

        def apply_continue_behavior(blocks, ctx)
          return blocks if blocks.empty?

          preset = ctx.effective_preset
          return blocks unless preset

          expander = ctx.expander || default_expander

          if preset.continue_prefill
            # Prefill mode: append continue_postfix to last assistant message, skip nudge
            apply_continue_prefill(blocks, preset)
          else
            # Nudge mode: append continue nudge after the chat history
            append_continue_nudge(blocks, preset, expander, ctx)
          end
        end

        def apply_continue_prefill(blocks, preset)
          postfix = preset.continue_postfix.to_s
          return blocks if postfix.empty?

          # Find last assistant block and append postfix
          last_assistant_idx = blocks.rindex { |b| b.role == :assistant }
          return blocks if last_assistant_idx.nil?

          last_block = blocks[last_assistant_idx]
          modified_block = last_block.with(content: last_block.content.to_s + postfix)

          blocks[0...last_assistant_idx] + [modified_block] + blocks[(last_assistant_idx + 1)..]
        end

        def append_continue_nudge(blocks, preset, expander, ctx)
          template = preset.continue_nudge_prompt.to_s
          return blocks if template.strip.empty?

          # Expand macros in the nudge template (including {{lastChatMessage}})
          content = expand_macro(expander, ctx, template, allow_outlets: false)
          return blocks if content.strip.empty?

          nudge_block = Block.new(
            role: :system,
            content: content,
            slot: :continue_nudge,
            priority: 51,
            token_budget_group: :system,
            tags: [:continue_nudge]
          )

          blocks + [nudge_block]
        end

        def apply_replace_empty_message(blocks, ctx)
          preset = ctx.effective_preset
          replacement = preset.replace_empty_message.to_s
          return blocks if replacement.empty?

          blocks.map do |b|
            if b.slot == :user_message && b.role == :user && b.content.to_s.strip.empty?
              b.with(content: replacement, slot: :empty_user_message_replacement)
            else
              b
            end
          end
        end

        def prepend_new_chat_prompt(blocks, ctx)
          return blocks unless blocks.any?

          preset = ctx.effective_preset
          group_template = ctx.group ? preset.new_group_chat_prompt.to_s : ""
          template = group_template.strip.empty? ? preset.new_chat_prompt.to_s : group_template
          return blocks if template.strip.empty?

          expander = ctx.expander || default_expander
          content = expand_macro(expander, ctx, template, allow_outlets: false)
          return blocks if content.strip.empty?

          new_chat_block = Block.new(
            role: :system,
            content: content,
            slot: :new_chat_prompt,
            priority: 49,
            token_budget_group: :system,
            tags: [:new_chat]
          )

          # Insert at start of chat history (per ST behavior)
          [new_chat_block] + blocks
        end

        def append_group_nudge_prompt(blocks, ctx)
          return blocks unless ctx.group

          # Per ST behavior: group nudge is skipped for impersonate generation
          return blocks if ctx.generation_type == :impersonate

          preset = ctx.effective_preset
          return blocks unless preset

          template = preset.group_nudge_prompt.to_s
          return blocks if template.strip.empty?

          expander = ctx.expander || default_expander
          content = expand_macro(expander, ctx, template, allow_outlets: false)
          return blocks if content.strip.empty?

          nudge_block = Block.new(
            role: :system,
            content: content,
            slot: :group_nudge,
            priority: 51,
            token_budget_group: :system,
            tags: [:group_nudge]
          )

          blocks + [nudge_block]
        end

        def unknown_pinned_prompt_warning(pe)
          name = pe.name.to_s.strip
          name_part = name.empty? ? "" : " name=#{name.inspect}"
          "Unknown pinned prompt #{pe.id.inspect}#{name_part} has no content and no pinned group; ignoring."
        end

        def lore_block_priority(entry)
          base = 100
          base - [entry.insertion_order.to_i, 0].max.clamp(0, 99)
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
