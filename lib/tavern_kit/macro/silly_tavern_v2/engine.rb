# frozen_string_literal: true

require "date"
require "json"
require "time"

require_relative "../../chat_variables"
require_relative "../invocation"
require_relative "../invocation_syntax"
require_relative "../pipeline"
require_relative "../packs/silly_tavern"

module TavernKit
  module Macro::SillyTavernV2
    # Parser-based macro expander inspired by SillyTavern's experimental "MacroEngine".
    #
    # Why this exists alongside {Macro::SillyTavernV1::Engine}:
    # - {Macro::SillyTavernV1::Engine} is regex + multi-pass (legacy ST-ish behavior).
    # - {Macro::SillyTavernV2::Engine} expands by parsing balanced `{{ ... }}` blocks, enabling
    #   reliable nesting (e.g. `{{outer::{{inner}}}}`).
    #
    # Design goals:
    # - Keep TavernKit's pluggability story: macro implementations still come from
    #   the env hash and MacroRegistry instances.
    # - Preserve unknown macros (optionally) while still resolving nested macros
    #   inside them.
    # - Deterministic pick/roll: offsets are computed against the *original input*
    #   string (pre-replacement), matching ST MacroEngine semantics.
    #
    # Notes:
    # - This engine does **not** auto-expand macros that appear in a macro handler's
    #   *returned output*. Nested support applies to macros that appear inside the
    #   braces of another macro.
    # - `{{trim}}` is implemented as a directive and removed in a post-processing
    #   step (so it can strip newlines produced by `{{newline}}`).
    class Engine
      UNKNOWN_POLICIES = %i[keep empty].freeze

      def initialize(
        unknown: :keep,
        max_depth: 50,
        clock: nil,
        rng: nil,
        pick_seed: nil,
        builtins_registry: ::TavernKit::Macro::Packs::SillyTavern.utilities_registry,
        pipeline_registry: ::TavernKit::Macro::Packs::SillyTavern.pipeline_registry,
        invocation_syntax: ::TavernKit::Macro::Packs::SillyTavern.invocation_syntax
      )
        unknown = unknown.to_sym
        raise ArgumentError, "unknown must be one of #{UNKNOWN_POLICIES.inspect}" unless UNKNOWN_POLICIES.include?(unknown)

        @unknown = unknown
        @max_depth = Integer(max_depth)
        @clock = clock
        @rng = rng
        @pick_seed = pick_seed
        @builtins_registry = builtins_registry
        @invocation_syntax = invocation_syntax
        @pipeline = ::TavernKit::Macro::Pipeline.new(pipeline_registry)
      end

      # Expand macros in +text+.
      #
      # @param text [String]
      # @param vars [Hash] macro environment (string/symbol keys). Values may be
      #   strings or callables (receiving {Invocation}).
      # @param allow_outlets [Boolean]
      # @return [String]
      def expand(text, vars = {}, allow_outlets: true)
        str = text.to_s
        return str if str.empty?

        env = normalize_keys!(vars || {})
        resolve_variable_store!(env)
        resolve_global_variable_store!(env)

        rng = @rng || Random.new
        now = current_time
        raw_content_hash = ::TavernKit::Macro::Invocation.stable_hash(str)
        pick_seed = lookup(env, :pick_seed) || @pick_seed

        # ST behavior: {{original}} expands only once per evaluation pass.
        env_eval = wrap_original_once(env.dup)

        # Optional regex-level preprocessing (host apps can register their own).
        str = @pipeline.apply(str)

        out = render(
          str,
          env: env_eval,
          allow_outlets:,
          raw_content_hash:,
          pick_seed:,
          rng:,
          now:,
          base_offset: 0,
          depth: 0,
        )

        post_process(out)
      end

      private

      # ----------------------------------------------------------------------
      # Rendering
      # ----------------------------------------------------------------------

      def render(str, env:, allow_outlets:, raw_content_hash:, pick_seed:, rng:, now:, base_offset:, depth:)
        return str.to_s if str.to_s.empty?

        # Guard rail for pathological nesting.
        return str.to_s if depth >= @max_depth

        s = str.to_s
        out = +""
        i = 0
        n = s.bytesize

        while i < n
          b = s.getbyte(i)

          # Escaped macro delimiters: \{{ and \}}.
          if b == 92 # \\
            nb1 = (i + 1 < n) ? s.getbyte(i + 1) : nil
            nb2 = (i + 2 < n) ? s.getbyte(i + 2) : nil

            if nb1 == 123 && nb2 == 123 # \{{
              out << "{{"
              i += 3
              next
            end
            if nb1 == 125 && nb2 == 125 # \}}
              out << "}}"
              i += 3
              next
            end
          end

          # Macro start.
          if b == 123 && (i + 1 < n) && s.getbyte(i + 1) == 123 # {{
            # ST MacroLexer behavior: a single '{' immediately before a macro opener
            # is treated as literal text (e.g. "{{{char}}" == "{"+ "{{char}}").
            if (i + 2 < n) && s.getbyte(i + 2) == 123 # {{{
              out << "{"
              i += 1
              next
            end

            span = extract_macro_span(s, i)
            if span.nil?
              # Unclosed: treat literally.
              out << "{{"
              i += 2
              next
            end

            full_tag, body, end_i = span
            abs_offset = base_offset + i

            out << expand_tag(
              full_tag,
              body,
              env:,
              allow_outlets:,
              raw_content_hash:,
              pick_seed:,
              rng:,
              now:,
              base_offset: abs_offset,
              depth: depth + 1,
            )
            i = end_i
            next
          end

          out << s.byteslice(i, 1)
          i += 1
        end

        out
      end

      # Expand a single macro tag (including nested macros inside its body).
      def expand_tag(full_tag, body, env:, allow_outlets:, raw_content_hash:, pick_seed:, rng:, now:, base_offset:, depth:)
        raw_inner = body.to_s

        # ST comment directive: remove the whole tag.
        return "" if raw_inner.lstrip.start_with?("//")

        # Expand nested macros *inside* this tag's body.
        # The body's first character starts after the opening braces ({{).
        expanded_inner = render(
          raw_inner,
          env:,
          allow_outlets:,
          raw_content_hash:,
          pick_seed:,
          rng:,
          now:,
          base_offset: base_offset + 2,
          depth: depth,
        )

        expanded_raw_inner = expanded_inner.to_s
        inner = expanded_raw_inner.strip

        # ST trim directive is removed in a post-processing step (after {{newline}}).
        return "{{trim}}" if inner.casecmp("trim").zero?

        key = inner.downcase
        match = "{{#{expanded_raw_inner}}}"

        default_name = inner.split(/[ :]/, 2).first.to_s.strip.downcase
        name, args = @invocation_syntax.parse(inner, default_name: default_name)
        name_sym = name.to_s.strip.downcase.to_sym

        invocation = ::TavernKit::Macro::Invocation.new(
          raw: inner,
          key: key,
          name: name_sym,
          args: args,
          offset: base_offset,
          raw_content_hash: raw_content_hash,
          pick_seed: pick_seed,
          allow_outlets: allow_outlets,
          env: env,
          rng: rng,
          now: now,
        )

        # 1) Exact raw-key override: vars["datetimeformat yyyy"] style.
        if (value = lookup(env, key))
          return evaluate_macro_value(value, invocation, match: match)
        end

        # 2) Named env macro.
        if (value = lookup(env, name_sym))
          return evaluate_macro_value(value, invocation, match: match)
        end

        # 3) Built-ins.
        if @builtins_registry && @builtins_registry.key?(name_sym)
          return evaluate_macro_value(@builtins_registry.get(name_sym), invocation, match: match)
        end

        unknown_result(match)
      end

      # Extract a balanced `{{ ... }}` span starting at +start_i+.
      #
      # Supports nested macros inside the tag body by tracking depth.
      # Escaped braces (e.g., `\\{` / `\\}`) are ignored for nesting purposes.
      #
      # @return [Array<(String,String,Integer)>] [full_tag, body, end_index]
      def extract_macro_span(str, start_i)
        n = str.bytesize
        i = start_i + 2
        depth = 1

        # Need at least 2 bytes for a delimiter check.
        while i < n - 1
          b = str.getbyte(i)

          # Skip escaped braces inside the tag.
          if b == 92 # \\
            nb = str.getbyte(i + 1)
            if nb == 123 || nb == 125 # \{ or \}
              i += 2
              next
            end
          end

          # Nested macro start.
          if b == 123 && str.getbyte(i + 1) == 123
            depth += 1
            i += 2
            next
          end

          # Macro end.
          if b == 125 && str.getbyte(i + 1) == 125
            depth -= 1
            i += 2
            if depth == 0
              full = str.byteslice(start_i, i - start_i)
              body = str.byteslice(start_i + 2, i - start_i - 4)
              return [full, body, i]
            end
            next
          end

          i += 1
        end

        nil
      end

      # ----------------------------------------------------------------------
      # Macro value evaluation
      # ----------------------------------------------------------------------

      def evaluate_macro_value(value, invocation, match:)
        callable = if value.is_a?(Proc)
          value
        elsif value.respond_to?(:call)
          value
        end

        result = if callable.nil?
          value
        else
          arity = if callable.is_a?(Proc)
            callable.arity
          else
            callable.method(:call).arity
          end

          if arity == 0
            callable.call
          elsif arity == 1 || arity == -1
            callable.call(invocation)
          else
            callable.call(nil, invocation)
          end
        end

        return unknown_result(match) if result.equal?(::TavernKit::Macro::UNRESOLVED)

        sanitize_macro_value(result)
      rescue StandardError
        unknown_result(match)
      end

      def unknown_result(match)
        case @unknown
        when :keep
          match.to_s
        when :empty
          ""
        else
          match.to_s
        end
      end

      def sanitize_macro_value(value)
        case value
        when String
          value
        when nil
          ""
        when Time
          value.utc.iso8601
        when DateTime
          value.new_offset(0).to_time.utc.iso8601
        when Date
          Time.utc(value.year, value.month, value.day).iso8601
        when Hash, Array
          JSON.generate(value)
        else
          value.to_s
        end
      rescue StandardError
        ""
      end

      # ----------------------------------------------------------------------
      # Env helpers (mirrors Macro::SillyTavernV1::Engine behavior)
      # ----------------------------------------------------------------------

      def normalize_keys!(vars)
        vars.transform_keys! do |k|
          k.is_a?(Symbol) ? k : k.to_s.to_sym
        end
        vars
      end

      def lookup(env, key)
        return nil if key.nil?

        env[key.is_a?(Symbol) ? key : key.to_s.to_sym]
      end

      def resolve_variable_store!(env)
        store = env[:local_store]
        env[:local_store] = case store
        when ChatVariables then store
        when Hash then ChatVariables.new(store)
        when nil then ChatVariables.new
        else store
        end
      end

      def resolve_global_variable_store!(env)
        store = env[:global_store]
        env[:global_store] = case store
        when ChatVariables then store
        when Hash then ChatVariables.new(store)
        when nil then ChatVariables.new
        else store
        end
      end

      def wrap_original_once(env)
        return env unless env.is_a?(Hash)
        return env unless env.key?(:original)

        value = env[:original]
        return env if value.respond_to?(:call)

        used = false
        one_shot = lambda do |_invocation = nil|
          return "" if used

          used = true
          value.to_s
        end

        env.merge(original: one_shot)
      rescue StandardError
        env
      end

      def current_time
        @clock ? @clock.call : Time.now
      end

      # ----------------------------------------------------------------------
      # Post processing
      # ----------------------------------------------------------------------

      def post_process(str)
        out = str.to_s

        # Remove trim directives and surrounding newlines.
        out = out.gsub(/(?:\r?\n)*\{\{trim\}\}(?:\r?\n)*/i, "")

        # Unescape braces (ST MacroEngine unescapes \\{ / \\} after processing).
        out = out.gsub(/\\([{}])/) { Regexp.last_match(1) }

        out
      end
    end
  end
end
