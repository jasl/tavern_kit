# frozen_string_literal: true

module TavernKit
  module Lore
    INSERTION_STRATEGIES = [
      :sorted_evenly,
      :character_lore_first,
      :global_lore_first,
    ].freeze

    Candidate = Struct.new(
      :entry,
      :matched_primary_keys,
      :matched_secondary_keys,
      :activation_type,
      :token_estimate,
      :selected,
      :dropped_reason,
      keyword_init: true,
    ) do
      def to_h
        {
          uid: entry.uid,
          comment: entry.comment,
          position: entry.position,
          insertion_order: entry.insertion_order,
          constant: entry.constant?,
          enabled: entry.enabled?,
          depth: entry.depth,
          role: entry.role,
          outlet: entry.outlet,
          source: entry.source,
          book_name: entry.book_name,
          matched_primary_keys: Array(matched_primary_keys),
          matched_secondary_keys: Array(matched_secondary_keys),
          activation_type: activation_type,
          token_estimate: token_estimate,
          selected: selected,
          dropped_reason: dropped_reason,
        }
      end
    end

    # Result of lore engine evaluation.
    #
    # Contains candidates (both selected and dropped entries) and provides
    # convenience methods for accessing selected entries by position.
    class Result
      # @return [Array<Lore::Book>] books evaluated
      attr_reader :books

      # @return [String] text that was scanned
      attr_reader :scan_text

      # @return [Integer, nil] token budget
      attr_reader :budget

      # @return [Integer] tokens used by selected entries
      attr_reader :used_tokens

      # @return [Array<Candidate>] all candidates (selected and dropped)
      attr_reader :candidates

      # @return [Symbol] insertion strategy
      attr_reader :insertion_strategy

      # Create a new Result.
      #
      # @param books [Array<Lore::Book>] books evaluated
      # @param scan_text [String] text that was scanned
      # @param budget [Integer, nil] token budget
      # @param used_tokens [Integer] tokens used by selected entries
      # @param candidates [Array<Candidate>] all candidates
      # @param insertion_strategy [Symbol] insertion strategy
      def initialize(books:, scan_text:, budget:, used_tokens:, candidates: [], insertion_strategy: :sorted_evenly)
        @books = Array(books)
        @scan_text = scan_text
        @budget = budget
        @used_tokens = used_tokens
        @candidates = candidates
        @insertion_strategy = insertion_strategy
      end

      def selected
        candidates.select(&:selected)
      end

      def dropped
        candidates.reject(&:selected)
      end

      # Returns true if any entries were dropped due to budget exhaustion.
      # This is useful for displaying alerts in the UI (ST: "Alert on overflow").
      #
      # @return [Boolean]
      def budget_exceeded?
        return false if budget.nil?

        dropped.any? { |c| c.dropped_reason == "budget_exhausted" }
      end

      # Returns the count of entries dropped due to budget exhaustion.
      #
      # @return [Integer]
      def budget_dropped_count
        dropped.count { |c| c.dropped_reason == "budget_exhausted" }
      end

      # Convenience: the activated (matched) Lore::Entry records.
      def activated_entries
        candidates.map(&:entry)
      end

      # Convenience: the dropped (budget-excluded) candidates.
      def dropped_candidates
        dropped
      end

      def selected_entries
        selected.map(&:entry)
      end

      # Get selected entries grouped by position.
      #
      # @param insertion_strategy [Symbol, nil] override insertion strategy
      # @return [Hash{Symbol => Array<Entry>}] entries grouped by position
      def selected_by_position(insertion_strategy: nil)
        strat = insertion_strategy.nil? ? @insertion_strategy : insertion_strategy
        selected_entries.group_by(&:position).transform_values { |entries| ordered(entries, strat) }
      end

      def outlets
        map = {}
        selected_entries
          .select { |e| e.position == :outlet && !e.outlet.to_s.strip.empty? }
          .group_by(&:outlet)
          .each do |name, entries|
            ordered_entries = ordered(entries, @insertion_strategy)
            map[name] = ordered_entries.map(&:content).join("\n")
        end
        map
      end

      def to_h
        {
          budget: budget || "unlimited",
          used_tokens: used_tokens,
          budget_exceeded: budget_exceeded?,
          budget_dropped_count: budget_dropped_count,
          scan_text: scan_text,
          insertion_strategy: insertion_strategy,
          candidates: candidates.map(&:to_h),
          outlets: outlets,
        }
      end

      private

      def ordered(entries, strategy)
        list = Array(entries)
        case strategy
        in :sorted_evenly
          list.sort_by { |e| [fixed_source_rank(e.source), e.insertion_order.to_i, e.book_name.to_s, e.uid.to_s] }
        in :character_lore_first
          list.sort_by do |e|
            [
              fixed_source_rank(e.source),
              source_rank(e, prefer: :character),
              e.insertion_order.to_i,
              e.book_name.to_s,
              e.uid.to_s,
            ]
          end
        in :global_lore_first
          list.sort_by do |e|
            [
              fixed_source_rank(e.source),
              source_rank(e, prefer: :global),
              e.insertion_order.to_i,
              e.book_name.to_s,
              e.uid.to_s,
            ]
          end
        else
          raise ArgumentError, "Unknown insertion strategy: #{strategy.inspect}"
        end
      end

      # ST parity: chat lore always goes first, then persona lore, then the rest.
      #
      # This ordering is independent of the "character vs global" insertion strategy.
      def fixed_source_rank(source)
        s = source&.to_sym
        return 0 if chat_source?(s)
        return 1 if persona_source?(s)

        2
      end

      def source_rank(entry, prefer:)
        s = entry.source&.to_sym
        return 1 if s.nil?

        prefer_sym = prefer&.to_sym

        case prefer_sym
        when :character
          return 0 if character_source?(s)
        when :global
          return 0 if global_source?(s)
        else
          return 0 if s == prefer_sym
        end

        2
      end

      def character_source?(source)
        source == :character || source.to_s.start_with?("character_")
      end

      def global_source?(source)
        source == :global || source.to_s.start_with?("global_")
      end

      def chat_source?(source)
        source == :chat || source.to_s.start_with?("chat_") || source.to_s.start_with?("conversation_")
      end

      def persona_source?(source)
        source == :persona || source.to_s.start_with?("persona_")
      end
    end
  end
end
