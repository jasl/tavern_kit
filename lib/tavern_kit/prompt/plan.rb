# frozen_string_literal: true

require_relative "block"
require_relative "dialects"

module TavernKit
  module Prompt
    # A prompt plan is a sequence of Prompt::Block objects.
    #
    # Plans make it easier to:
    # - inspect/debug the built prompt (all blocks including disabled)
    # - filter to only enabled blocks for LLM consumption
    # - insert custom content at specific points
    # - map SillyTavern concepts (persona, character defs, World Info, examples, PHI) to structured units
    #
    # @example Basic usage
    #   plan = Plan.new(blocks: blocks)
    #   plan.blocks           # All blocks (including disabled) for debugging
    #   plan.enabled_blocks   # Only enabled blocks
    #   plan.to_messages      # Dialect-specific format (default: :openai)
    #
    # @example Using different dialects
    #   plan.to_messages(dialect: :openai)    # => [{role:, content:}]
    #   plan.to_messages(dialect: :anthropic) # => {messages:, system:}
    #   plan.to_messages(dialect: :text)      # => "System: ...\nassistant:"
    #
    class Plan
      attr_reader :blocks, :outlets, :lore_result, :trim_report, :greeting, :greeting_index, :warnings

      # @param blocks [Array<Block>] array of prompt blocks
      # @param outlets [Hash] World Info outlets
      # @param lore_result [Lore::Result, nil] lore evaluation result
      # @param trim_report [Hash, nil] context trimming report
      # @param greeting [String, nil] resolved greeting text with macros expanded
      # @param greeting_index [Integer, nil] greeting index (0 = first_mes, 1+ = alternate_greetings)
      # @param warnings [Array<String>, nil] non-fatal warnings emitted during build
      def initialize(blocks:, outlets: {}, lore_result: nil, trim_report: nil, greeting: nil, greeting_index: nil, warnings: nil)
        @blocks = Array(blocks)
        @outlets = outlets || {}
        @lore_result = lore_result
        @trim_report = trim_report
        @greeting = greeting
        @greeting_index = greeting_index
        @warnings = Array(warnings).compact.map(&:to_s)
      end

      # Check if a greeting is available.
      # @return [Boolean]
      def greeting?
        !@greeting.nil?
      end

      # Returns only enabled blocks.
      # Use this when you need the actual blocks that will be sent to the LLM.
      #
      # @return [Array<Block>]
      def enabled_blocks
        @blocks.select(&:enabled?)
      end

      # Convert enabled blocks to Message objects.
      # @return [Array<Message>]
      def messages
        merge_in_chat_blocks_for_output(enabled_blocks).map(&:to_message)
      end

      # Convert enabled blocks to the specified dialect format.
      #
      # @param dialect [Symbol] target dialect (:openai, :anthropic, :text)
      # @param squash_system_messages [Boolean] whether to squash consecutive system messages (OpenAI only)
      # @return [Array<Hash>, Hash, String] formatted output for the dialect
      #
      # @example OpenAI format (default)
      #   plan.to_messages
      #   # => [{role: "system", content: "..."}, {role: "user", content: "..."}]
      #
      # @example Anthropic format
      #   plan.to_messages(dialect: :anthropic)
      #   # => {messages: [{role: "user", content: [{type: "text", text: "..."}]}], system: [...]}
      #
      # @example Text completion format
      #   plan.to_messages(dialect: :text)
      #   # => "System: ...\nuser: ...\nassistant:"
      #
      def to_messages(dialect: :openai, squash_system_messages: false, **dialect_opts)
        dialect_sym = dialect.to_sym

        output_blocks = merge_in_chat_blocks_for_output(enabled_blocks)
        if squash_system_messages && dialect_sym == :openai
          output_blocks = squash_system_blocks(output_blocks)
        end

        Dialects.convert(output_blocks.map(&:to_message), dialect: dialect_sym, **dialect_opts)
      end

      # Total number of blocks (including disabled).
      # @return [Integer]
      def size
        @blocks.size
      end

      # Number of enabled blocks.
      # @return [Integer]
      def enabled_size
        enabled_blocks.size
      end

      # Debug dump showing all blocks with their metadata.
      # Includes disabled blocks marked with [DISABLED].
      #
      # @return [String]
      def debug_dump
        @blocks.map do |b|
          status = b.enabled? ? "" : " [DISABLED]"
          slot_info = b.slot ? " (#{b.slot})" : ""
          header = "[#{b.role}]#{slot_info}#{status}"
          meta_info = format_metadata(b)
          "#{header}#{meta_info}\n#{b.content}\n"
        end.join("\n")
      end

      private

      SQUASH_SYSTEM_EXCLUDE_SLOTS = %i[new_chat_prompt new_example_chat].freeze

      # Squash consecutive system messages into one (ST: squash_system_messages).
      #
      # Matches ST behavior at a high level:
      # - only applies to system-role messages
      # - drops empty system messages
      # - excludes certain identifiers (mapped here via block.slot)
      def squash_system_blocks(blocks)
        blocks = Array(blocks)

        squashed = []
        blocks.each do |block|
          next if block.role == :system && block.content.to_s.empty?

          should_squash = block.role == :system &&
            (block.name.nil? || block.name.to_s.empty?) &&
            !SQUASH_SYSTEM_EXCLUDE_SLOTS.include?(block.slot)
          last = squashed.last
          last_should_squash = last &&
            last.role == :system &&
            (last.name.nil? || last.name.to_s.empty?) &&
            !SQUASH_SYSTEM_EXCLUDE_SLOTS.include?(last.slot)

          if should_squash && last_should_squash
            merged_content = "#{last.content}\n#{block.content}"
            squashed[-1] = last.with(content: merged_content)
          else
            squashed << block
          end
        end

        squashed
      end

      def format_metadata(block)
        parts = []
        parts << "id=#{block.id[0, 8]}..." if block.id
        parts << "depth=#{block.depth}" if block.in_chat?
        parts << "order=#{block.order}" if block.order != 100
        parts << "priority=#{block.priority}" if block.priority != 100
        parts << "group=#{block.token_budget_group}" if block.token_budget_group != :default
        parts << "tags=#{block.tags.join(",")}" if block.tags.any?

        parts.empty? ? "" : " {#{parts.join(", ")}}"
      end

      def merge_in_chat_blocks_for_output(blocks)
        merged = []

        blocks.each do |block|
          if block.in_chat? && (prev = merged.last) &&
              prev.in_chat? &&
              prev.role == block.role &&
              prev.depth == block.depth &&
              prev.order == block.order
            merged_content = [prev.content.to_s.strip, block.content.to_s.strip].reject(&:empty?).join("\n")
            merged[-1] = prev.with(content: merged_content)
          else
            merged << block
          end
        end

        merged
      end
    end
  end
end
