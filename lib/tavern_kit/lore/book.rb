# frozen_string_literal: true

require_relative "entry"

module TavernKit
  module Lore
    # A Lore Book (World Info) is a collection of lore entries that can be
    # activated based on keyword matching during prompt generation.
    #
    # Books can be loaded from:
    # - SillyTavern World Info JSON exports
    # - Character Card V2/V3 embedded character_book
    # - Standalone lorebook JSON files
    #
    # @example Load from file
    #   book = TavernKit::Lore::Book.load_file("world.json", source: :global)
    #
    # @example Create programmatically
    #   book = TavernKit::Lore::Book.new(
    #     name: "My World",
    #     entries: [entry1, entry2],
    #     scan_depth: 5,
    #     token_budget: 1000
    #   )
    class Book
      # @return [String, nil] book name
      attr_reader :name

      # @return [String, nil] book description
      attr_reader :description

      # @return [Integer, nil] scan depth for keyword matching
      attr_reader :scan_depth

      # @return [Integer, nil] token budget for this book
      attr_reader :token_budget

      # @return [Boolean] whether recursive scanning is enabled
      attr_reader :recursive_scanning

      # @return [Array<Entry>] lore entries in this book
      attr_reader :entries

      # @return [Hash] extension data
      attr_reader :extensions

      # @return [Symbol, nil] source identifier (:global, :character, etc.)
      attr_reader :source

      # @return [Hash, nil] raw parsed data
      attr_reader :raw

      # Create a new Lore Book.
      #
      # @param name [String, nil] book name
      # @param description [String, nil] book description
      # @param scan_depth [Integer, nil] scan depth for keyword matching
      # @param token_budget [Integer, nil] token budget for this book
      # @param recursive_scanning [Boolean] whether to enable recursive scanning
      # @param entries [Array<Entry>] lore entries
      # @param extensions [Hash] extension data
      # @param source [Symbol, nil] source identifier
      # @param raw [Hash, nil] raw parsed data
      def initialize(
        name: nil,
        description: nil,
        scan_depth: nil,
        token_budget: nil,
        recursive_scanning: false,
        entries: [],
        extensions: {},
        source: nil,
        raw: nil
      )
        @name = name
        @description = description
        @scan_depth = scan_depth
        @token_budget = token_budget
        @recursive_scanning = recursive_scanning
        @entries = entries
        @extensions = extensions
        @source = source
        @raw = raw
      end

      # Load a Lore Book from a JSON file.
      #
      # @param path [String] path to the JSON file
      # @param source [Symbol, nil] source identifier
      # @return [Book]
      def self.load_file(path, source: nil)
        from_hash(JSON.parse(File.read(path)), source: source)
      end

      # Create a Book from a hash.
      #
      # Accepts either:
      # - a standalone World Info / Lorebook JSON object
      # - a Character Card V2 JSON object containing data.character_book
      #
      # @param hash [Hash] parsed JSON data
      # @param source [Symbol, nil] source identifier
      # @return [Book]
      def self.from_hash(hash, source: nil)
        hash = Utils.deep_stringify_keys(hash)

        # Character Card V2 wrapper.
        if hash["spec"].to_s == "chara_card_v2" && hash["data"].is_a?(Hash)
          cb = hash.dig("data", "character_book")
          return cb.nil? ? new(entries: [], raw: hash, source: source) : from_hash(cb, source: source)
        end

        name = hash["name"]
        description = hash["description"]

        # ST lorebook exports (World Info) use camelCase for these book-level fields.
        st_book = hash.key?("scanDepth") || hash.key?("tokenBudget") || hash.key?("recursiveScanning")

        scan_depth = if st_book
          hash.key?("scanDepth") ? hash["scanDepth"] : nil
        else
          hash.key?("scan_depth") ? hash["scan_depth"] : nil
        end

        token_budget = if st_book
          hash.key?("tokenBudget") ? hash["tokenBudget"] : nil
        else
          hash.key?("token_budget") ? hash["token_budget"] : nil
        end

        recursive_scanning = if st_book
          hash.key?("recursiveScanning") ? hash["recursiveScanning"] : false
        else
          hash.key?("recursive_scanning") ? hash["recursive_scanning"] : false
        end

        extensions = hash["extensions"] || {}

        entries_raw = hash["entries"] || []
        entries = index_entries(entries_raw).map do |uid, e|
          Entry.from_hash(e, uid: uid, source: source, book_name: name)
        end

        new(
          name: name,
          description: description,
          scan_depth: scan_depth.nil? ? nil : scan_depth.to_i,
          token_budget: token_budget.nil? ? nil : token_budget.to_i,
          recursive_scanning: Coerce.bool(recursive_scanning, default: false),
          entries: entries,
          extensions: extensions.is_a?(Hash) ? extensions : {},
          source: source&.to_sym,
          raw: hash,
        )
      end

      def self.index_entries(entries_raw)
        case entries_raw
        when Array
          entries_raw.each_with_index.map do |e, idx|
            uid = if e.is_a?(Hash)
              if e.key?("uid")
                e["uid"]
              elsif e.key?("id")
                e["id"]
              end
            end
            uid ||= idx + 1
            [uid, e]
          end
        when Hash
          # ST World Info exports use an object keyed by uid.
          # Preserve numeric-ish ordering when possible.
          entries_raw
            .to_a
            .sort_by { |(k, _)| k.to_s.match?(/^\d+$/) ? k.to_s.to_i : k.to_s }
            .map do |(k, v)|
              # Prefer uid from entry data over hash key
              uid = if v.is_a?(Hash)
                if v.key?("uid")
                  v["uid"]
                elsif v.key?("id")
                  v["id"]
                end
              end
              uid ||= k
              [uid, v]
            end
        else
          raise ArgumentError, "Lore Book entries must be an array or an object"
        end
      end
      private_class_method :index_entries

      def to_h
        {
          name: name,
          description: description,
          scan_depth: scan_depth,
          token_budget: token_budget,
          recursive_scanning: recursive_scanning,
          entries: entries.map(&:to_h),
          extensions: extensions,
          source: source,
        }
      end
    end
  end
end
