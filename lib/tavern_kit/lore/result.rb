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
          list.sort_by { |e| [e.insertion_order.to_i, e.book_name.to_s, e.uid.to_s] }
        in :character_lore_first
          list.sort_by { |e| [source_rank(e, prefer: :character), e.insertion_order.to_i, e.book_name.to_s, e.uid.to_s] }
        in :global_lore_first
          list.sort_by { |e| [source_rank(e, prefer: :global), e.insertion_order.to_i, e.book_name.to_s, e.uid.to_s] }
        else
          raise ArgumentError, "Unknown insertion strategy: #{strategy.inspect}"
        end
      end

      def source_rank(entry, prefer:)
        s = entry.source&.to_sym
        return 0 if s == prefer
        return 1 if s.nil?
        2
      end
    end
  end
end
