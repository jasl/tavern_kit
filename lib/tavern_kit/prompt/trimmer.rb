# frozen_string_literal: true

require_relative "../token_estimator"

module TavernKit
  module Prompt
    # Trims a Prompt::Plan to fit within a max token budget.
    #
    # This is a pragmatic approximation of SillyTavern's context management:
    # - Example blocks can be "gradually pushed out" first
    # - World Info (Lore) blocks can be evicted by priority (low order/recursive first)
    # - Chat history can be truncated (oldest first)
    #
    # The Trimmer uses the Extended Block Structure attributes:
    # - `token_budget_group` to determine eviction category
    # - `priority` to determine eviction order within a category
    # - `enabled` to skip already-disabled blocks
    #
    class Trimmer
      attr_reader :token_estimator, :message_overhead

      def initialize(token_estimator: TokenEstimator.default, message_overhead: 4)
        @token_estimator = token_estimator
        @message_overhead = message_overhead.to_i
      end

      def estimate_plan_tokens(plan)
        estimate_blocks_tokens(plan.enabled_blocks).sum
      end

      # Mutates the plan in-place by disabling blocks that exceed the budget.
      # Returns a report Hash.
      def trim!(plan, max_tokens:, examples_behavior: :gradually_push_out)
        max_tokens = max_tokens.to_i
        return { trimmed: false, reason: "no_max" } if max_tokens <= 0

        token_state = compute_token_state(plan)
        total = token_state[:total]
        return { trimmed: false, total_tokens: total, max_tokens: max_tokens } if total <= max_tokens

        report = {
          trimmed: true,
          max_tokens: max_tokens,
          total_tokens_before: total,
          removed_example_blocks: [],
          removed_lore_uids: [],
          removed_history_messages: 0,
        }

        # 1) Examples eviction
        case examples_behavior.to_sym
        when :disabled
          removed = evict_by_budget_group(plan, :examples, max_tokens: nil, remove_all: true, token_state: token_state)
          report[:removed_example_blocks].concat(removed)
        when :gradually_push_out, :trim
          removed = evict_by_budget_group(plan, :examples, max_tokens: max_tokens, token_state: token_state)
          report[:removed_example_blocks].concat(removed)
        end
        # :always_keep means we don't touch examples

        total = token_state[:total]

        # 2) Lore eviction (World Info blocks)
        if total > max_tokens
          removed = evict_by_budget_group(plan, :lore, max_tokens: max_tokens, token_state: token_state)
          report[:removed_lore_uids].concat(removed)
        end

        total = token_state[:total]

        # 3) History truncation (oldest first, keep latest user message)
        if total > max_tokens
          removed_count = evict_history(plan, max_tokens: max_tokens, token_state: token_state)
          report[:removed_history_messages] = removed_count
        end

        report[:total_tokens_after] = token_state[:total]
        report[:fits] = (token_state[:total] <= max_tokens)

        report
      end

      private

      def estimate_blocks_tokens(blocks)
        blocks.map do |b|
          next 0 if b.nil? || b.disabled?
          estimate_block_tokens(b)
        end
      end

      # Evict blocks by budget group, sorted by priority (higher priority = evicted first)
      # Returns list of identifiers (example_block index or uid) for the evicted blocks
      def evict_by_budget_group(plan, budget_group, max_tokens:, token_state:, remove_all: false)
        evicted = []
        budget_group_sym = budget_group.to_sym

        # Get blocks in this budget group, sorted by eviction priority:
        # - Higher numeric priority is evicted first
        # - Lower numeric priority is kept longer
        candidates = plan.blocks
          .select { |b| b.enabled? && b.token_budget_group == budget_group_sym }
          .sort_by { |b| [-b.priority, b.order] }

        # Group by example_block if dealing with examples (evict whole example dialogues at once)
        if budget_group_sym == :examples
          # Evict example dialogues (groups) in priority order, not numeric index order.
          # Each block in a dialogue should share `metadata[:example_block]`; if missing, fall back to block id.
          example_groups = candidates.group_by { |b| b.metadata[:example_block] || b.id }

          sorted_groups = example_groups.map do |group_key, blocks|
            {
              key: group_key,
              blocks: blocks,
              priority: blocks.map(&:priority).max,
              order: blocks.map(&:order).min,
            }
          end.sort_by { |g| [-g[:priority], g[:order], g[:key].to_s] }

          sorted_groups.each do |group|
            break if !remove_all && max_tokens && token_state[:total] <= max_tokens

            disabled_any = false
            group[:blocks].each do |block|
              disabled_any = true if disable_block!(plan, block, token_state: token_state)
            end
            evicted << group[:key] if disabled_any
          end
        else
          # For lore and other groups, evict block by block
          candidates.each do |block|
            break if !remove_all && max_tokens && token_state[:total] <= max_tokens

            next unless disable_block!(plan, block, token_state: token_state)

            evicted << (block.metadata[:uid] || block.id)
          end
        end

        evicted
      end

      # Evict history blocks (oldest first), but never evict the current user message
      def evict_history(plan, max_tokens:, token_state:)
        removed = 0

        # Get history blocks sorted by order (oldest first)
        history_blocks = plan.blocks
          .select { |b| b.enabled? && b.token_budget_group == :history }
          .sort_by(&:order)

        history_blocks.each do |block|
          break if token_state[:total] <= max_tokens

          next unless disable_block!(plan, block, token_state: token_state)

          removed += 1
        end

        removed
      end

      # Disable a block in-place by replacing it with a disabled copy
      def disable_block!(plan, block, token_state:)
        idx = token_state[:index_by_id][block.id]
        return false if idx.nil?

        current = plan.blocks[idx]
        return false if current.nil? || current.disabled?

        token_state[:total] -= token_state[:tokens_by_id].fetch(current.id, 0)
        plan.blocks[idx] = current.disable
        true
      end

      def compute_token_state(plan)
        tokens_by_id = {}
        index_by_id = {}
        total = 0

        plan.blocks.each_with_index do |b, idx|
          next if b.nil?

          index_by_id[b.id] = idx
          tokens_by_id[b.id] = estimate_block_tokens(b)
          total += tokens_by_id[b.id] if b.enabled?
        end

        { total: total, tokens_by_id: tokens_by_id, index_by_id: index_by_id }
      end

      def estimate_block_tokens(block)
        t = token_estimator.estimate(block.content).to_i
        t += message_overhead if message_overhead > 0
        t
      end
    end
  end
end
