# frozen_string_literal: true

require "zlib"

module TavernKit
  module Macro
    # Sentinel value used by macro handlers to indicate they could not resolve the macro.
    #
    # The expander treats this as an "unknown macro" and applies the configured unknown
    # policy (:keep or :empty).
    UNRESOLVED = Object.new.freeze

    # A single macro call site within a macro expansion pass.
    #
    # This is provided to parameterized custom macros registered via {TavernKit::MacroRegistry}.
    #
    # Example:
    # - For `{{random::a,b,c}}`, the invocation name is `:random` and args is `"a,b,c"`.
    # - For `{{timeDiff::a::b}}`, the invocation name is `:timediff` and args is `{a:, b:}`.
    #
    # @attr raw [String] raw macro content (inside braces), trimmed
    # @attr key [String] normalized lookup key (downcased `raw`)
    # @attr name [Symbol] macro name (downcased)
    # @attr args [Object, nil] parsed argument payload (String/Hash/nil)
    # @attr offset [Integer] character offset of the macro match in the source string
    # @attr raw_content_hash [Integer] stable hash of the original input string (for deterministic pick)
    # @attr pick_seed [Object, nil] optional external seed (from env) for deterministic pick
    # @attr allow_outlets [Boolean] whether outlet expansion is enabled for this pass
    # @attr env [Hash, nil] the macro environment hash for this expansion pass
    # @attr rng [Random, nil] optional RNG injected into the expander
    # @attr now [Time, nil] timestamp used for this invocation (respects expander clock injection)
    Invocation = Data.define(
      :raw,
      :key,
      :name,
      :args,
      :offset,
      :raw_content_hash,
      :pick_seed,
      :allow_outlets,
      :env,
      :rng,
      :now,
    )

    class Invocation
      # Convenience accessor for World Info outlets map (if present in env).
      def outlets
        return nil unless env.is_a?(Hash)

        env[:outlets]
      end

      # ST list splitting helper used by macros like {{random::...}} / {{pick::...}}.
      #
      # Supports:
      # - `a,b,c` with `\,` escape
      # - `a::b::c` for explicit `::` splitting
      def split_list(source = args)
        str = source.to_s
        return [] if str.strip.empty?

        if str.include?("::")
          str.split("::")
        else
          placeholder = "##COMMA##"
          str
            .gsub("\\,", placeholder)
            .split(",")
            .map { |item| item.strip.gsub(placeholder, ",") }
        end
      end

      # RNG helper matching TavernKit's built-in random behavior:
      # uses injected RNG when present, otherwise a new RNG per call.
      def rng_or_new
        rng || Random.new(Random.new_seed)
      end

      # Deterministic pick index helper matching ST/TavernKit behavior.
      #
      # Uses the invocation offset, the input string hash, and optional pick_seed.
      def pick_index(length)
        length = length.to_i
        return 0 if length <= 0

        # ST behavior uses `seedrandom(finalSeed)`; TavernKit intentionally uses Ruby's
        # built-in Random for a deterministic-but-not-ST-identical result.
        chat_id_hash = pick_seed.nil? ? 0 : pick_seed
        combined_seed_string = "#{chat_id_hash}-#{raw_content_hash}-#{offset}"
        seed = self.class.stable_hash(combined_seed_string)

        Random.new(seed).rand(length)
      end

      # Stable hashing algorithm used for deterministic picks (mirrors ST behavior).
      def self.stable_hash(value)
        # TavernKit intentionally uses Ruby stdlib hashing primitives rather than porting
        # SillyTavern's JS hash function. The goal is a stable, deterministic seed input
        # for `{{pick}}`, not byte-level parity with ST.
        Zlib.crc32(value.to_s.b)
      rescue StandardError
        0
      end
    end
  end
end
