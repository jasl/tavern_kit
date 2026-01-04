# frozen_string_literal: true

require_relative "base"

module TavernKit
  module Prompt
    module Middleware
      # Middleware that filters and partitions prompt entries.
      #
      # This middleware:
      # - Filters entries by generation_type triggers
      # - Filters entries by conditional activation (chat/turns/character)
      # - Applies Author's Note parity controls
      # - Separates entries into: relative, in_chat, forced_last
      #
      class Entries < Base
        # IDs that are forced to relative position even if configured as in_chat
        FORCE_RELATIVE_IDS = %w[chat_history chat_examples].freeze

        # IDs that are always placed last (PHI = Post History Instructions)
        FORCE_LAST_IDS = %w[post_history_instructions].freeze

        # Result of partitioning prompt entries
        PartitionedEntries = Data.define(:relative, :in_chat, :forced_last)

        private

        def before(ctx)
          preset = ctx.effective_preset
          prompt_entries = preset.effective_prompt_entries

          # Build conditions context for filtering
          conditions_context = {
            chat_scan_messages: ctx.chat_scan_messages,
            default_chat_depth: ctx.default_chat_depth,
            turn_count: ctx.turn_count,
            character: ctx.character,
            user: ctx.user,
          }

          # Filter by triggers and conditions
          prompt_entries = prompt_entries.select do |e|
            e.triggered_by?(ctx.generation_type) && e.active_for?(conditions_context)
          end

          # Apply Author's Note parity controls
          prompt_entries = apply_authors_note_parity_controls(prompt_entries, ctx)

          # Partition entries
          partitioned = partition_prompt_entries(prompt_entries)

          # Store results in context
          ctx.prompt_entries = prompt_entries
          ctx[:partitioned_entries] = partitioned
        end

        def apply_authors_note_parity_controls(prompt_entries, ctx)
          prompt_entries = Array(prompt_entries)
          return prompt_entries if prompt_entries.empty?

          idx = prompt_entries.index { |pe| pe.id.to_s == "authors_note" }
          return prompt_entries if idx.nil?

          preset = ctx.effective_preset

          # Check frequency - if frequency is 0, never include AN
          # If frequency > 0, include AN only when message_count % frequency == 0
          frequency = preset.authors_note_frequency.to_i
          if frequency == 0
            # Remove the AN entry entirely when frequency is 0
            prompt_entries = prompt_entries.dup
            prompt_entries.delete_at(idx)
            return prompt_entries
          end

          # Check if current message count matches the frequency
          message_count = ctx.turn_count.to_i
          if message_count > 0 && (message_count % frequency != 0)
            # Not on a frequency match - remove AN
            prompt_entries = prompt_entries.dup
            prompt_entries.delete_at(idx)
            return prompt_entries
          end

          raw_position, depth, role = effective_authors_note_controls(ctx)
          entry_position = (raw_position == :in_chat ? :in_chat : :relative)

          original = prompt_entries[idx]
          updated = rebuild_prompt_entry(
            original,
            position: entry_position,
            depth: depth,
            role: role
          )

          prompt_entries = prompt_entries.dup
          prompt_entries[idx] = updated

          # Non-chat positions are injected relative to main_prompt
          if raw_position == :before_prompt || raw_position == :in_prompt
            prompt_entries = move_prompt_entry_adjacent_to_main(
              prompt_entries,
              entry_id: "authors_note",
              before: (raw_position == :before_prompt)
            )
          end

          prompt_entries
        end

        def effective_authors_note_controls(ctx)
          preset = ctx.effective_preset
          position = preset.authors_note_position
          depth = preset.authors_note_depth
          role = preset.authors_note_role

          overrides = ctx.authors_note_overrides
          if overrides
            position = overrides[:position] if overrides.key?(:position)
            depth = overrides[:depth] if overrides.key?(:depth)
            role = overrides[:role] if overrides.key?(:role)
          end

          [position, depth, role]
        end

        def rebuild_prompt_entry(prompt_entry, **overrides)
          PromptEntry.new(
            id: prompt_entry.id,
            name: prompt_entry.name,
            enabled: prompt_entry.enabled,
            pinned: prompt_entry.pinned,
            role: overrides.fetch(:role, prompt_entry.role),
            position: overrides.fetch(:position, prompt_entry.position),
            depth: overrides.fetch(:depth, prompt_entry.depth),
            order: overrides.fetch(:order, prompt_entry.order),
            content: prompt_entry.content,
            triggers: prompt_entry.triggers,
            forbid_overrides: prompt_entry.forbid_overrides,
            conditions: prompt_entry.conditions
          )
        end

        def move_prompt_entry_adjacent_to_main(prompt_entries, entry_id:, before:)
          prompt_entries = Array(prompt_entries).dup

          main_idx = prompt_entries.index { |pe| pe.id.to_s == "main_prompt" }
          entry_idx = prompt_entries.index { |pe| pe.id.to_s == entry_id.to_s }
          return prompt_entries if main_idx.nil? || entry_idx.nil?

          entry = prompt_entries.delete_at(entry_idx)
          main_idx -= 1 if entry_idx < main_idx

          insert_at = before ? main_idx : (main_idx + 1)
          prompt_entries.insert(insert_at, entry)
          prompt_entries
        end

        def partition_prompt_entries(prompt_entries)
          relative = []
          in_chat = []
          forced_last = []

          Array(prompt_entries).each do |pe|
            if FORCE_LAST_IDS.include?(pe.id.to_s)
              forced_last << pe
            elsif FORCE_RELATIVE_IDS.include?(pe.id.to_s)
              # Force multi-block markers to relative even if configured in_chat
              relative << pe
            elsif pe.in_chat?
              in_chat << pe
            else
              relative << pe
            end
          end

          PartitionedEntries.new(relative: relative, in_chat: in_chat, forced_last: forced_last)
        end
      end
    end
  end
end
