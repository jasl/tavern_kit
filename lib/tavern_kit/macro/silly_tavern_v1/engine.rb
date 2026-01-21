# frozen_string_literal: true

require "time"
require "json"
require "date"

require_relative "../../chat_variables"
require_relative "../invocation"
require_relative "../invocation_syntax"
require_relative "../pipeline"
require_relative "../packs/silly_tavern"

module TavernKit
  module Macro::SillyTavernV1
    # Expands SillyTavern-style macros in the form of {{macro}}.
    #
    # Core placeholders and ST-compatible utilities:
    # - {{char}}, {{user}}, {{persona}}, {{original}}
    # - date/time/random/dice helpers
    #
    # Notes:
    # - Case-insensitive macro names.
    # - Pass-based evaluation (ST-like); not a recursive macro parser.
    # - Unknown macros are left untouched by default.
    class Engine
      # NOTE: This expander intentionally mirrors SillyTavern's macro evaluation model:
      # it runs multiple targeted regex passes in a fixed order (pre-env → env → post-env),
      # rather than attempting to parse arbitrary `{{...}}` spans.
      #
      # This is required for ST compatibility because ST allows "nested" macros in the sense that
      # earlier passes can introduce macro text that later passes must still expand
      # (e.g., `{{charPrompt}}` containing `{{char}}`, or `{{random::{{char}},x}}`).
      #
      # See: tmp/SillyTavern/public/scripts/macros.js (evaluateMacros) and public/script.js (substituteParams).

      # Macro keys that are not real placeholders and should not be treated as env macro keys.
      RESERVED_ENV_KEYS = %w[
        outlets
        local_store
        global_store
        pick_seed
      ].freeze

      # Post-env macros executed by ST after env substitutions.
      #
      # These are handled explicitly (with ST-like ordering) so they can also expand inside
      # text produced by env macros (e.g., description containing {{time}}).
      POST_ENV_NAMES = %i[
        maxprompt
        lastmessage
        lastmessageid
        lastusermessage
        lastcharmessage
        firstincludedmessageid
        firstdisplayedmessageid
        lastswipeid
        currentswipeid
        reverse
        time
        date
        weekday
        isotime
        isodate
        datetimeformat
        idle_duration
        time_utc
        outlet
        timediff
        banned
        random
        pick
      ].freeze

      def initialize(
        unknown: :keep,
        clock: nil,
        rng: nil,
        pick_seed: nil,
        builtins_registry: nil,
        pipeline_registry: nil,
        invocation_syntax: nil
      )
        @unknown = unknown
        @clock = if clock.nil?
          -> { Time.now }
        elsif clock.respond_to?(:execute)
          clock
        else
          -> { clock }
        end
        @rng = rng
        @pick_seed = pick_seed
        @builtins_registry = builtins_registry.nil? ? ::TavernKit::Macro::Packs::SillyTavern.utilities_registry : builtins_registry
        unless @builtins_registry.respond_to?(:get)
          raise ArgumentError, "builtins_registry must respond to #get"
        end

        @invocation_syntax = invocation_syntax.nil? ? ::TavernKit::Macro::Packs::SillyTavern.invocation_syntax : invocation_syntax
        unless @invocation_syntax.respond_to?(:parse)
          raise ArgumentError, "invocation_syntax must respond to #parse"
        end

        resolved_pipeline_registry = pipeline_registry.nil? ? ::TavernKit::Macro::Packs::SillyTavern.pipeline_registry : pipeline_registry
        @pipeline = ::TavernKit::Macro::Pipeline.new(resolved_pipeline_registry)
      end

      def expand(text, vars = {}, allow_outlets: true)
        return "" if text.nil?

        str = text.to_s
        return str if str.empty?

        env = normalize_keys!(vars)
        resolve_variable_store(env)
        resolve_global_variable_store(env)

        raw_content = str.dup
        raw_content_hash = stable_hash(raw_content)
        pick_seed = lookup(env, "pick_seed") || @pick_seed
        now = current_time

        # ST behavior: {{original}} expands only once per evaluation pass.
        env_eval = wrap_original_once(env.dup)

        # Optional host-defined preprocessing (default registry is empty).
        str = @pipeline.apply(str)

        # === 1) Pre-env macro passes (ST order) ===
        str = expand_pre_env_macros(
          str,
          env: env_eval,
          allow_outlets: allow_outlets,
          raw_content_hash: raw_content_hash,
          pick_seed: pick_seed,
          now: now,
        )

        # === 2) Env macro passes ===
        str = expand_env_macros(
          str,
          env: env_eval,
          allow_outlets: allow_outlets,
          raw_content_hash: raw_content_hash,
          pick_seed: pick_seed,
          now: now,
        )

        # === 3) Post-env macro passes (ST order) ===
        str = expand_post_env_macros(
          str,
          env: env_eval,
          allow_outlets: allow_outlets,
          raw_content_hash: raw_content_hash,
          pick_seed: pick_seed,
          now: now,
        )

        # Optional behavior: remove any unresolved {{...}} placeholders.
        if @unknown == :empty
          str = remove_unresolved_placeholders(str)
        end

        str
      end

      private

      def build_invocation(raw:, key:, offset:, raw_content_hash:, pick_seed:, allow_outlets:, env:, rng:, now:)
        syntax = @invocation_syntax
        name, args = syntax.parse(raw, default_name: key)

        ::TavernKit::Macro::Invocation.new(
          raw: raw,
          key: key,
          name: name.to_s.downcase.to_sym,
          args: args,
          offset: offset,
          raw_content_hash: raw_content_hash,
          pick_seed: pick_seed,
          allow_outlets: allow_outlets,
          env: env,
          rng: rng,
          now: now,
        )
      end

      def evaluate_macro_value(value, invocation)
        callable = if value.is_a?(Proc)
          value
        elsif value.respond_to?(:execute)
          value
        end

        return sanitize_macro_value(value) unless callable

        arity = if callable.is_a?(Proc)
          callable.arity
        else
          callable.method(:execute).arity
        end

        result = if arity == 0
          callable.call
        else
          callable.call(invocation)
        end
        sanitize_macro_value(result)
      rescue StandardError
        ""
      end

      def evaluate_builtin_value(value, invocation, match)
        callable = if value.is_a?(Proc)
          value
        elsif value.respond_to?(:execute)
          value
        end

        result = if callable.nil?
          value
        else
          arity = if callable.is_a?(Proc)
            callable.arity
          else
            callable.method(:execute).arity
          end

          if arity == 0
            callable.call
          elsif arity == 1 || arity == -1
            callable.call(invocation)
          else
            callable.call(nil, invocation)
          end
        end

        if result.equal?(::TavernKit::Macro::UNRESOLVED)
          @unknown == :empty ? "" : match
        else
          sanitize_macro_value(result)
        end
      rescue StandardError
        ""
      end

      def expand_pre_env_macros(str, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        out = str.to_s
        return out if out.empty?

        # NOTE: We intentionally do not implement ST legacy <USER>/<BOT>/<CHAR> here.
        # TavernKit explicitly does not support those tokens.

        # Dice roll macro: {{roll:d20}} / {{roll d20}} / {{roll:2d6+1}}
        out = out.gsub(/\{\{roll[ :][^}]+\}\}/i) do |match|
          offset = Regexp.last_match.begin(0) || 0
          replace_match(
            match,
            offset: offset,
            env: env,
            allow_outlets: allow_outlets,
            raw_content_hash: raw_content_hash,
            pick_seed: pick_seed,
            now: now,
          )
        end

        # Variable macros (ST setvar/getvar/addvar/incvar/decvar + global variants).
        out = out.gsub(/\{\{setvar::[^}]+\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }
        out = out.gsub(/\{\{addvar::[^}]+\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }
        out = out.gsub(/\{\{incvar::[^}]+\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }
        out = out.gsub(/\{\{decvar::[^}]+\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }
        out = out.gsub(/\{\{getvar::[^}]+\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }

        out = out.gsub(/\{\{setglobalvar::[^}]+\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }
        out = out.gsub(/\{\{addglobalvar::[^}]+\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }
        out = out.gsub(/\{\{incglobalvar::[^}]+\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }
        out = out.gsub(/\{\{decglobalvar::[^}]+\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }
        out = out.gsub(/\{\{getglobalvar::[^}]+\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }

        # TavernKit alias: {{var::name}} / {{var::name::index}}
        out = out.gsub(/\{\{var::[^}]+\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }

        # Utility macros
        out = out.gsub(/\{\{newline\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }

        # ST trim directive: runs after newline replacement (so it can remove newlines produced by {{newline}}).
        out = out.gsub(/(?:\r?\n)*\{\{trim\}\}(?:\r?\n)*/i, "")

        out = out.gsub(/\{\{noop\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }
        out = out.gsub(/\{\{input\}\}/i) { |m| replace_match(m, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:) }

        out
      end

      def expand_env_macros(str, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        out = str.to_s
        return out if out.empty?

        env_keys = env_macro_keys(env)
        return out if env_keys.empty?

        env_keys.each do |key|
          # Skip macros that ST evaluates in the post-env phase so they can also apply
          # inside text produced by env macro substitutions.
          next if POST_ENV_NAMES.include?(key.to_s.downcase.to_sym)

          pattern = /\{\{#{Regexp.escape(key)}\}\}/i
          out = out.gsub(pattern) do |match|
            offset = Regexp.last_match.begin(0) || 0
            replace_match(
              match,
              raw_inner: key,
              offset: offset,
              env: env,
              allow_outlets: allow_outlets,
              raw_content_hash: raw_content_hash,
              pick_seed: pick_seed,
              now: now,
            )
          end
        end

        out
      end

      def expand_post_env_macros(str, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        out = str.to_s
        return out if out.empty?

        # NOTE: Ordering here mirrors ST's postEnvMacros list.
        %w[
          maxPrompt
          lastMessage
          lastMessageId
          lastUserMessage
          lastCharMessage
          firstIncludedMessageId
          firstDisplayedMessageId
          lastSwipeId
          currentSwipeId
        ].each do |name|
          out = out.gsub(/\{\{#{Regexp.escape(name)}\}\}/i) do |match|
            replace_match(match, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
          end
        end

        out = out.gsub(/\{\{reverse:(.+?)\}\}/i) do |match|
          replace_match(match, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        end

        # ST comment blocks: processed after reverse (and after env macros).
        out = out.gsub(/\{\{\/\/[\s\S]*?\}\}/m, "")

        %w[
          time
          date
          weekday
          isotime
          isodate
        ].each do |name|
          out = out.gsub(/\{\{#{Regexp.escape(name)}\}\}/i) do |match|
            replace_match(match, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
          end
        end

        out = out.gsub(/\{\{datetimeformat +[^}]*\}\}/i) do |match|
          replace_match(match, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        end

        out = out.gsub(/\{\{idle_duration\}\}/i) do |match|
          replace_match(match, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        end

        out = out.gsub(/\{\{time_utc[-+]\d+\}\}/i) do |match|
          replace_match(match, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        end

        out = out.gsub(/\{\{outlet::.+?\}\}/i) do |match|
          replace_match(match, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        end

        out = out.gsub(/\{\{timediff::.*?::.*?\}\}/i) do |match|
          replace_match(match, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        end

        out = out.gsub(/\{\{banned +\".*\"\}\}/i) do |match|
          replace_match(match, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        end

        out = out.gsub(/\{\{random\s?::?[^}]+\}\}/i) do |match|
          replace_match(match, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        end

        out = out.gsub(/\{\{pick\s?::?[^}]+\}\}/i) do |match|
          replace_match(match, offset: Regexp.last_match.begin(0) || 0, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        end

        out
      end

      def replace_match(match, raw_inner: nil, offset:, env:, allow_outlets:, raw_content_hash:, pick_seed:, now:)
        raw = raw_inner || unwrap(match)
        key = raw.to_s.strip.downcase

        invocation = build_invocation(
          raw: raw.to_s.strip,
          key: key,
          offset: offset,
          raw_content_hash: raw_content_hash,
          pick_seed: pick_seed,
          allow_outlets: allow_outlets,
          env: env,
          rng: @rng,
          now: now,
        )

        # Custom overrides (MacroRegistry / macro_vars / overrides).
        #
        # Priority:
        # - Exact raw key match (e.g., :"datetimeformat yyyy-mm-dd")
        # - Base macro name (e.g., :datetimeformat)
        custom_value = lookup(env, key)
        custom_value = lookup(env, invocation.name) if custom_value.nil?
        return evaluate_macro_value(custom_value, invocation) unless custom_value.nil?

        builtin = @builtins_registry.get(invocation.name)
        return @unknown == :empty ? "" : match if builtin.nil?

        evaluate_builtin_value(builtin, invocation, match)
      end

      def unwrap(match)
        s = match.to_s
        return s unless s.start_with?("{{") && s.end_with?("}}")

        s[2..-3]
      end

      def env_macro_keys(env)
        keys = []
        seen = {}

        env.each_key do |k|
          next if k.nil?

          key_str = k.to_s
          next if key_str.strip.empty?
          next if RESERVED_ENV_KEYS.include?(key_str)

          # Skip any key containing braces; those aren't valid ST macro keys.
          next if key_str.include?("{{") || key_str.include?("}}")

          normalized = key_str.downcase
          next if seen[normalized]

          seen[normalized] = true
          keys << key_str
        end

        keys
      end

      def wrap_original_once(env)
        return env unless env.is_a?(Hash)
        return env unless env.key?(:original)

        value = env[:original]
        return env if value.respond_to?(:execute)

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

      def remove_unresolved_placeholders(str)
        s = str.to_s
        return s if s.empty?

        prev = nil
        cur = s
        # Iteratively remove simple (non-nested) placeholders.
        5.times do
          break if cur == prev

          prev = cur
          cur = cur.gsub(/\{\{[^{}]*\}\}/, "")
        end

        cur
      end

      def normalize_keys!(vars)
        return {} unless vars.is_a?(Hash)

        # Replace string keys with symbol keys in-place so mutations are visible to callers.
        string_keys = vars.keys.select { |k| k.is_a?(String) }
        string_keys.each do |k|
          vars[k.to_sym] = vars.delete(k)
        end
        vars
      rescue FrozenError
        # If the hash is frozen, return a normalized copy instead.
        vars.transform_keys { |k| k.to_sym rescue k }
      end

      def lookup(vars, key)
        return nil unless vars.is_a?(Hash)

        vars[key.to_sym]
      end

      def resolve_variable_store(vars)
        store = if vars.is_a?(Hash)
          TavernKit::ChatVariables.wrap(vars[:local_store])
        else
          TavernKit::ChatVariables.new
        end

        begin
          vars[:local_store] = store
        rescue StandardError
          # Ignore if vars is frozen or does not allow mutation.
        end
        store
      end

      def resolve_global_variable_store(vars)
        store = if vars.is_a?(Hash)
          TavernKit::ChatVariables.wrap(vars[:global_store])
        else
          TavernKit::ChatVariables.new
        end

        begin
          vars[:global_store] = store
        rescue StandardError
          # Ignore if vars is frozen or does not allow mutation.
        end
        store
      end

      def current_time
        t = @clock.execute
        t.is_a?(Time) ? t : Time.parse(t.to_s)
      rescue StandardError
        Time.now
      end

      def stable_hash(value)
        ::TavernKit::Macro::Invocation.stable_hash(value.to_s)
      end
    end
  end
end
