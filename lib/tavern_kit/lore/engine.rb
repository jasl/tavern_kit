# frozen_string_literal: true

require_relative "result"
require_relative "../chat_variables"
require_relative "timed_effects"

module TavernKit
  module Lore
    # Evaluates a Lore::Book (SillyTavern World Info / Character Book)
    # against an input text.
    #
    # Supports recursive scanning: when enabled, activated entries' content
    # is added to the scan buffer, potentially triggering additional entries.
    class Engine
      # Safety limits to prevent runaway loops or memory exhaustion.
      DEFAULT_MAX_RECURSION_STEPS = 3
      HARD_MAX_RECURSION_STEPS = 10
      MAX_SCAN_BUFFER_SIZE = 1_000_000 # 1MB

      def initialize(
        token_estimator: TavernKit::TokenEstimator.default,
        match_whole_words: true,
        case_sensitive: false,
        max_recursion_steps: DEFAULT_MAX_RECURSION_STEPS
      )
        unless token_estimator.is_a?(TokenEstimator::Base)
          raise ArgumentError, "token_estimator must be a TavernKit::TokenEstimator::Base, got: #{token_estimator.class}"
        end
        @token_estimator = token_estimator
        unless match_whole_words == true || match_whole_words == false
          raise ArgumentError, "match_whole_words must be a Boolean, got: #{match_whole_words.class}"
        end
        @match_whole_words = match_whole_words

        unless case_sensitive == true || case_sensitive == false
          raise ArgumentError, "case_sensitive must be a Boolean, got: #{case_sensitive.class}"
        end
        @case_sensitive = case_sensitive
        # Clamp to safe range: 0..HARD_MAX_RECURSION_STEPS
        @max_recursion_steps = [[max_recursion_steps.to_i, 0].max, HARD_MAX_RECURSION_STEPS].min
      end

      # @param book [Lore::Book]
      # @param books [Array<Lore::Book>]
      # @param scan_text [String]
      # @param scan_context [Hash, nil] context fields for per-entry match_* flags
      #   - :persona_description [String] user persona description
      #   - :character_description [String] character description
      #   - :character_personality [String] character personality
      #   - :character_depth_prompt [String] depth prompt content
      #   - :scenario [String] scenario text
      #   - :creator_notes [String] creator notes
      # @param token_budget [Integer, nil] overrides combined books' token_budget
      # @param generation_type [Symbol, String, nil] filters entries by trigger type (default: :normal)
      # @return [Lore::Result]
      def evaluate(
        book: nil,
        books: nil,
        scan_text: nil,
        scan_messages: nil,
        scan_depth: nil,
        scan_context: nil,
        scan_injects: nil,
        token_budget: nil,
        insertion_strategy: :sorted_evenly,
        generation_type: :normal,
        # ST parity extensions (optional)
        message_count: nil,
        variables_store: nil,
        timed_effects_key: TimedEffects::DEFAULT_STATE_KEY,
        min_activations: 0,
        min_activations_depth_max: 0,
        use_group_scoring: false,
        forced_activations: nil,
        rng: nil
      )
        books = Array(books || book).compact
        raise ArgumentError, "Lore::Engine#evaluate requires :book or :books" if books.empty?

        messages = if scan_messages
          Array(scan_messages).map(&:to_s)
        else
          scan_text.to_s.split("\n")
        end

        # `scan_depth` is the global/default scan depth (ST: world_info_depth).
        # Entries may override it via `entry.scan_depth` (ST: entry.scanDepth).
        default_depth = scan_depth.nil? ? nil : scan_depth.to_i

        text = scan_text.nil? ? messages.join("\n") : scan_text.to_s
        context = scan_context || {}
        unless generation_type.is_a?(Symbol) && TavernKit::GENERATION_TYPES.include?(generation_type)
          raise ArgumentError,
                "generation_type must be one of #{TavernKit::GENERATION_TYPES.inspect}, got: #{generation_type.inspect}"
        end
        gen_type = generation_type

        effective_budget = compute_effective_budget(books, token_budget)

        entries = books.flat_map(&:entries)

        # Filter entries by generation type triggers
        entries = entries.select { |e| e.triggered_by?(gen_type) }

        # Early return for empty entries.
        if entries.empty?
          return Result.new(books: books, scan_text: text, budget: effective_budget, used_tokens: 0, candidates: [], insertion_strategy: insertion_strategy)
        end

        # ==========================================
        # ST parity settings (min activations, effects)
        # ==========================================
        min_activations = [min_activations.to_i, 0].max
        min_activations_depth_max = [min_activations_depth_max.to_i, 0].max
        min_activations_enabled = min_activations.positive?

        # ST UI parity: min activations and recursion scanning are mutually exclusive.
        recursive_enabled = books.any?(&:recursive_scanning)
        recursive_enabled = false if min_activations_enabled
        recursive_enabled = !!recursive_enabled && @max_recursion_steps.positive?

        # ST `chat.length` equivalent for timed effects. Caller can override.
        # Default: use provided messages length (best-effort).
        msg_count = message_count.nil? ? messages.length : message_count.to_i

        # Persisted variables store (for timed effects JSON state).
        vars_store = TavernKit::ChatVariables.wrap(variables_store)

        rng ||= Random.new

        timed_effects = TimedEffects.new(
          message_count: msg_count,
          entries: entries,
          variables_store: vars_store,
          state_key: timed_effects_key,
          dry_run: false,
        )
        timed_effects.check!

        forced_full, forced_world_uid = index_forced_activations(forced_activations)

        # ==========================================
        # ST-like scanning loop (direct / recursion / min activations)
        # ==========================================
        candidates_by_key = {}
        selected_keys = {}
        selected_groups = {}
        failed_probability = {}
        used = 0
        token_budget_overflowed = false

        recurse_buffer = +""
        recursion_steps = 0
        scan_skew = 0

        # ST parity: delay_until_recursion level tracking.
        # Entries with delay_until_recursion are grouped by level (1, 2, 3...).
        # Initially only level 1 can match; once no matches found, level 2 becomes eligible.
        current_recursion_delay_level = 0
        max_recursion_delay_level = compute_max_recursion_delay_level(entries)

        loop do
          scan_state =
            if recursive_enabled && !recurse_buffer.empty?
              :recursive
            elsif min_activations_enabled && scan_skew.positive?
              :min_activations
            else
              :direct
            end

          pass_default_depth = default_depth
          if min_activations_enabled
            pass_default_depth = pass_default_depth.nil? ? nil : (pass_default_depth + scan_skew)
          end

          activated_now = []

          entries.each do |entry|
            next unless entry.enabled?

            key = entry_key(entry)
            next if selected_keys[key]
            next if failed_probability[key]

            # Timed effects suppression
            if timed_effects.delay_active?(entry)
              next
            end

            sticky_active = timed_effects.sticky_active?(entry)
            cooldown_active = timed_effects.cooldown_active?(entry)
            if cooldown_active && !sticky_active
              next
            end

            # Recursion-only suppression
            if scan_state == :recursive && entry.exclude_recursion && !sticky_active
              next
            end

            # delay_until_recursion suppression (ST parity)
            # Entries with delay_until_recursion only activate during recursive scans
            # at or below the current eligible recursion delay level.
            if entry.delay_until_recursion? && !sticky_active
              # During direct scan, skip delay_until_recursion entries
              if scan_state != :recursive
                next
              end

              # During recursive scan, check if entry's level is eligible
              entry_level = entry.delay_until_recursion_level || 1
              if entry_level > current_recursion_delay_level
                next
              end
            end

            # Forced activation (ST: externalActivations)
            override = forced_full[key] || forced_world_uid[world_uid_key(entry)]
            if override
              forced_entry = build_forced_entry(entry, override)
              cand = candidates_by_key[key] ||= Candidate.new(
                entry: forced_entry,
                matched_primary_keys: ["<forced>"],
                matched_secondary_keys: [],
                activation_type: :forced,
                token_estimate: estimate_tokens(forced_entry.content),
                selected: false,
                dropped_reason: nil,
              )
              cand.entry = forced_entry
              cand.activation_type = :forced
              cand.token_estimate = estimate_tokens(forced_entry.content)
              activated_now << cand
              next
            end

            # Constant activation
            if entry.constant?
              cand = candidates_by_key[key] ||= Candidate.new(
                entry: entry,
                matched_primary_keys: ["<constant>"],
                matched_secondary_keys: [],
                activation_type: :constant,
                token_estimate: estimate_tokens(entry.content),
                selected: false,
                dropped_reason: nil,
              )
              cand.activation_type = :constant
              activated_now << cand
              next
            end

            # Sticky activation
            if sticky_active
              cand = candidates_by_key[key] ||= Candidate.new(
                entry: entry,
                matched_primary_keys: ["<sticky>"],
                matched_secondary_keys: [],
                activation_type: :sticky,
                token_estimate: estimate_tokens(entry.content),
                selected: false,
                dropped_reason: nil,
              )
              cand.activation_type = :sticky
              activated_now << cand
              next
            end

            # Key-based activation
            include_recurse = (scan_state != :min_activations)
            candidate = try_activate_entry(
              entry,
              messages,
              default_scan_depth: pass_default_depth,
              recurse_buffer: recurse_buffer,
              scan_context: context,
              scan_injects: scan_injects,
              activation_type: (scan_state == :recursive ? :recursive : :direct),
              include_recurse: include_recurse,
              message_count: msg_count,
            )
            next if candidate.nil?

            existing = candidates_by_key[key]
            if existing
              # Preserve original match metadata, but refresh activation_type/token estimate.
              existing.activation_type = candidate.activation_type
              existing.token_estimate = candidate.token_estimate
              activated_now << existing
            else
              candidates_by_key[key] = candidate
              activated_now << candidate
            end
          end

          # Nothing new this pass? Stop.
          break if activated_now.empty?

          # Sort: sticky first, then higher insertion_order (ST: order desc)
          activated_now.sort_by! do |c|
            sticky_rank = timed_effects.sticky_active?(c.entry) ? 0 : 1
            [
              sticky_rank,
              -c.entry.insertion_order.to_i,
              c.entry.book_name.to_s,
              c.entry.uid.to_s,
            ]
          end

          # Group filtering (inclusion groups, scoring, weights)
          apply_inclusion_groups!(
            activated_now,
            selected_keys: selected_keys,
            selected_groups: selected_groups,
            timed_effects: timed_effects,
            scan_state: scan_state,
            scan_messages: messages,
            default_scan_depth: pass_default_depth,
            recurse_buffer: recurse_buffer,
            scan_context: context,
            scan_injects: scan_injects,
            use_group_scoring: use_group_scoring,
            rng: rng,
          )

          # Probability + budget acceptance (ST-style)
          ignores_budget_remaining = activated_now.count { |c| c.entry.ignore_budget }

          accepted_this_pass = []
          activated_now.each do |c|
            ignores_budget_remaining -= 1 if c.entry.ignore_budget

            if token_budget_overflowed && !c.entry.ignore_budget
              # ST: after overflow, skip non-ignoreBudget entries (unless we still need to process ignoreBudget items).
              next if ignores_budget_remaining.positive?

              break
            end

            key = entry_key(c.entry)
            if !passes_probability?(c.entry, rng: rng, sticky_active: timed_effects.sticky_active?(c.entry))
              c.selected = false
              c.dropped_reason = "probability_failed"
              failed_probability[key] = true
              next
            end

            # Budget check (ignoreBudget bypasses)
            if !effective_budget.nil? && !c.entry.ignore_budget
              t = c.token_estimate.to_i
              if used + t <= effective_budget
                c.selected = true
                c.dropped_reason = nil
                selected_keys[key] = true
                group_names(c.entry).each { |g| selected_groups[g] = true }
                used += t
                accepted_this_pass << c.entry
              else
                c.selected = false
                c.dropped_reason = "budget_exhausted"
                token_budget_overflowed = true
                next
              end
            else
              c.selected = true
              c.dropped_reason = nil
              selected_keys[key] = true
              group_names(c.entry).each { |g| selected_groups[g] = true }
              used += c.token_estimate.to_i
              accepted_this_pass << c.entry
            end
          end

          # Stop recursion/min activations once budget is overflowed.
          break if token_budget_overflowed

          # Recursion pass
          if recursive_enabled
            recursion_steps += 1
            break if recursion_steps > @max_recursion_steps

            new_recurse_entries = accepted_this_pass.reject(&:prevent_recursion)
            text_for_recurse = +""
            new_recurse_entries.each do |e|
              s = e.content.to_s
              next if s.strip.empty?

              text_for_recurse << "\n" unless text_for_recurse.empty?
              text_for_recurse << s
              truncate_scan_buffer!(text_for_recurse, MAX_SCAN_BUFFER_SIZE)
            end

            if !text_for_recurse.empty?
              recurse_buffer << "\n" unless recurse_buffer.empty?
              recurse_buffer << text_for_recurse
              truncate_scan_buffer!(recurse_buffer, MAX_SCAN_BUFFER_SIZE)

              # ST parity: increment recursion delay level for delay_until_recursion entries.
              # This allows entries at the next level to become eligible on the next pass.
              if current_recursion_delay_level < max_recursion_delay_level
                current_recursion_delay_level += 1
              end

              next
            end

            # No new content to recurse, but we might have delay_until_recursion entries
            # at higher levels waiting. Increment level and try again if possible.
            if current_recursion_delay_level < max_recursion_delay_level && !recurse_buffer.empty?
              current_recursion_delay_level += 1
              next
            end
          end

          # Min activations scan (increase depth)
          if min_activations_enabled && selected_keys.length < min_activations
            next_depth = (default_depth.nil? ? nil : (default_depth + scan_skew + 1))
            over_max = (!next_depth.nil?) && (
              (min_activations_depth_max.positive? && next_depth > min_activations_depth_max) ||
              (next_depth > messages.length)
            )

            unless over_max
              scan_skew += 1
              next
            end
          end

          break
        end

        # Persist new sticky/cooldown state for entries accepted into the prompt.
        timed_effects.set_effects!(candidates_by_key.values.select(&:selected).map(&:entry))

        Result.new(
          books: books,
          scan_text: text,
          budget: effective_budget,
          used_tokens: used,
          candidates: candidates_by_key.values,
          insertion_strategy: insertion_strategy,
        )
      end

      private

      def compute_effective_budget(books, token_budget)
        effective = if !token_budget.nil?
          token_budget.to_i
        else
          budgets = Array(books).map(&:token_budget).compact.map(&:to_i).select { |b| b.positive? }
          budgets.empty? ? nil : budgets.sum
        end

        # Treat zero or negative budget as unlimited.
        (effective && effective.positive?) ? effective : nil
      end

      # Compute the maximum recursion delay level from entries with delay_until_recursion.
      # Returns 0 if no entries have delay_until_recursion set.
      def compute_max_recursion_delay_level(entries)
        max_level = 0
        entries.each do |entry|
          next unless entry.delay_until_recursion?

          level = entry.delay_until_recursion_level || 1
          max_level = level if level > max_level
        end
        max_level
      end

      def try_activate_entry(entry, scan_messages, default_scan_depth:, recurse_buffer:, scan_context: {}, scan_injects: nil,
                             activation_type: :direct, include_recurse: true, message_count: nil)
        # CCv3: @@dont_activate prevents keyword-based activation
        # (entry can still be activated via @@constant or forced activation)
        if entry.dont_activate? && !entry.constant?
          return nil
        end

        if entry.constant?
          return Candidate.new(
            entry: entry,
            matched_primary_keys: ["<constant>"],
            matched_secondary_keys: [],
            activation_type: :constant,
            token_estimate: estimate_tokens(entry.content),
            selected: false,
            dropped_reason: nil,
          )
        end

        # CCv3: @@activate_only_after N - only activate after N messages
        if entry.activate_only_after && message_count
          return nil if message_count.to_i < entry.activate_only_after
        end

        # CCv3: @@activate_only_every N - only activate every N messages
        if entry.activate_only_every && message_count
          return nil unless (message_count.to_i % entry.activate_only_every).zero?
        end

        effective_scan_text = effective_scan_text_for_entry(
          entry,
          scan_messages,
          default_scan_depth: default_scan_depth,
          recurse_buffer: recurse_buffer,
          scan_context: scan_context,
          scan_injects: scan_injects,
          include_recurse: include_recurse,
        )

        case_sensitive = entry_case_sensitive(entry)
        match_whole_words = entry_match_whole_words(entry)

        # CCv3: @@exclude_keys - if any of these keys are found in scan text, don't activate
        if entry.exclude_keys.any?
          exclude_matches = match_any_primary(
            entry.exclude_keys,
            effective_scan_text,
            case_sensitive: case_sensitive,
            match_whole_words: match_whole_words,
            use_regex: false,
          )
          return nil if exclude_matches.any?
        end

        matched_primary = match_any_primary(
          entry.keys,
          effective_scan_text,
          case_sensitive: case_sensitive,
          match_whole_words: match_whole_words,
          use_regex: entry.use_regex?,
        )
        return nil if matched_primary.empty?

        matched_secondary = match_secondary(
          entry,
          effective_scan_text,
          case_sensitive: case_sensitive,
          match_whole_words: match_whole_words,
        )
        return nil unless secondary_pass?(entry, matched_secondary)

        Candidate.new(
          entry: entry,
          matched_primary_keys: matched_primary,
          matched_secondary_keys: matched_secondary,
          activation_type: activation_type,
          token_estimate: estimate_tokens(entry.content),
          selected: false,
          dropped_reason: nil,
        )
      end

      def effective_scan_text_for_entry(entry, scan_messages, default_scan_depth:, recurse_buffer:, scan_context:, scan_injects: nil, include_recurse: true)
        # ST: each entry can override scan depth (entry.scanDepth). If unset, use global depth.
        depth = entry.scan_depth.nil? ? default_scan_depth : entry.scan_depth
        depth = scan_messages.length if depth.nil?
        depth = depth.to_i

        # ST: scanDepth <= 0 means scan nothing; do not append inject/recursion/context buffers.
        base = depth <= 0 ? "" : Array(scan_messages).first(depth).join("\n")
        return "" if depth <= 0

        # 1) Per-entry match_* context fields (persona/character/etc)
        effective = build_entry_scan_text(entry, base, scan_context)

        # 2) Prompt injections marked scan=true (ST: injectBuffer)
        inject_list = Array(scan_injects).map(&:to_s).reject(&:empty?)
        if inject_list.any?
          effective = [effective, inject_list.join("\n")].reject { |s| s.to_s.empty? }.join("\n")
        end

        # 3) Recursive scan buffer (ST: recurseBuffer) — appended last (optional)
        if include_recurse && !recurse_buffer.to_s.strip.empty?
          effective = [effective, recurse_buffer].reject { |s| s.to_s.empty? }.join("\n")
        end

        effective
      end

      def estimate_tokens(text)
        @token_estimator.estimate(text)
      end

      def truncate_scan_buffer!(buffer, max_bytes)
        max = max_bytes.to_i
        return buffer if max <= 0
        return buffer if buffer.bytesize <= max

        tail = buffer.byteslice(-max, max) || +""
        tail = tail.scrub("")
        buffer.replace(tail)
      end

      # ==========================================
      # ST parity helpers
      # ==========================================

      def entry_key(entry)
        src = entry.source ? entry.source.to_s : "unknown"
        book = entry.book_name.to_s.strip
        book = "unnamed" if book.empty?

        "#{src}:#{book}.#{entry.uid}"
      end

      def world_uid_key(entry)
        book = entry.book_name.to_s.strip
        book = "unnamed" if book.empty?
        "#{book}.#{entry.uid}"
      end

      def group_names(entry)
        raw = entry.group.to_s
        return [] if raw.strip.empty?

        raw.split(/,\s*/).map { |s| s.to_s.strip }.reject(&:empty?)
      end

      def passes_probability?(entry, rng:, sticky_active:)
        return true unless entry.use_probability
        return true if entry.probability.to_i >= 100
        return true if sticky_active

        roll = rng.rand * 100
        roll <= entry.probability.to_i
      end

      def index_forced_activations(value)
        forced_full = {}
        forced_world_uid = {}

        Array(value).each do |item|
          next unless item.is_a?(Hash)

          item = Utils.deep_symbolize_keys(item)

          uid = item[:uid]
          uid = item[:id] if uid.nil?
          next if uid.nil?

          # Full key override
          k = item[:entry_key]
          k = item[:key] if k.nil?
          if !k.nil?
            key_str = k.to_s
            if key_str.include?(":") && key_str.include?(".")
              forced_full[key_str] = item
              next
            end
          end

          world = item[:book_name]
          world = item[:world] if world.nil?
          world = item[:book] if world.nil?
          world = world.to_s.strip
          world = "unnamed" if world.empty?

          source = item[:source]
          if !source.nil?
            src = source.to_s.strip
            forced_full["#{src}:#{world}.#{uid}"] = item
          end

          forced_world_uid["#{world}.#{uid}"] = item
        end

        [forced_full, forced_world_uid]
      end

      def build_forced_entry(entry, override)
        # Only override fields explicitly provided; preserve everything else.
        override = override.is_a?(Hash) ? override : {}

        content = fetch_override(override, :content) || entry.content
        position = fetch_override(override, :position, :pos) || entry.position
        depth = fetch_override(override, :depth) || entry.depth
        role = fetch_override(override, :role) || entry.role
        outlet = fetch_override(override, :outlet, :outlet_name, :outletName, :outletName) || entry.outlet
        insertion_order = fetch_override(override, :insertion_order, :order, :insertionOrder, :priority) || entry.insertion_order
        comment = fetch_override(override, :comment, :memo) || entry.comment

        ignore_budget_val = fetch_override_presence(override, :ignoreBudget, :ignore_budget)
        ignore_budget = ignore_budget_val[0] ? truthy?(ignore_budget_val[1]) : entry.ignore_budget

        group = fetch_override(override, :group) || entry.group
        group_override_val = fetch_override_presence(override, :groupOverride, :group_override)
        group_override = group_override_val[0] ? truthy?(group_override_val[1]) : entry.group_override

        group_weight = fetch_override(override, :groupWeight, :group_weight) || entry.group_weight

        use_probability_val = fetch_override_presence(override, :useProbability, :use_probability)
        use_probability = use_probability_val[0] ? truthy?(use_probability_val[1]) : entry.use_probability

        probability = fetch_override(override, :probability) || entry.probability

        use_group_scoring_presence = fetch_override_presence(override, :useGroupScoring, :use_group_scoring)
        use_group_scoring = if use_group_scoring_presence[0]
          v = use_group_scoring_presence[1]
          v.nil? ? nil : truthy?(v)
        else
          entry.use_group_scoring
        end

        automation_id = fetch_override(override, :automationId, :automation_id) || entry.automation_id

        sticky = fetch_override(override, :sticky) || entry.sticky
        cooldown = fetch_override(override, :cooldown) || entry.cooldown
        delay = fetch_override(override, :delay) || entry.delay

        exclude_recursion_val = fetch_override_presence(override, :excludeRecursion, :exclude_recursion)
        exclude_recursion = exclude_recursion_val[0] ? truthy?(exclude_recursion_val[1]) : entry.exclude_recursion

        prevent_recursion_val = fetch_override_presence(override, :preventRecursion, :prevent_recursion)
        prevent_recursion = prevent_recursion_val[0] ? truthy?(prevent_recursion_val[1]) : entry.prevent_recursion

        # Use fetch_override_presence to correctly handle false overrides (false || x == x in Ruby)
        delay_until_recursion_val = fetch_override_presence(override, :delayUntilRecursion, :delay_until_recursion)
        delay_until_recursion = delay_until_recursion_val[0] ? delay_until_recursion_val[1] : entry.delay_until_recursion

        Lore::Entry.new(
          uid: entry.uid,
          keys: entry.keys,
          secondary_keys: entry.secondary_keys,
          selective: entry.selective,
          selective_logic: entry.selective_logic,
          content: content,
          enabled: entry.enabled?,
          constant: entry.constant?,
          insertion_order: insertion_order,
          position: position,
          depth: depth,
          role: role,
          outlet: outlet,
          triggers: entry.triggers,
          scan_depth: entry.scan_depth,
          source: entry.source,
          book_name: entry.book_name,
          comment: comment,
          raw: entry.raw,
          match_persona_description: entry.match_persona_description?,
          match_character_description: entry.match_character_description?,
          match_character_personality: entry.match_character_personality?,
          match_character_depth_prompt: entry.match_character_depth_prompt?,
          match_scenario: entry.match_scenario?,
          match_creator_notes: entry.match_creator_notes?,
          ignore_budget: ignore_budget,
          use_probability: use_probability,
          probability: probability,
          group: group,
          group_override: group_override,
          group_weight: group_weight,
          use_group_scoring: use_group_scoring,
          automation_id: automation_id,
          sticky: sticky,
          cooldown: cooldown,
          delay: delay,
          exclude_recursion: exclude_recursion,
          prevent_recursion: prevent_recursion,
          delay_until_recursion: delay_until_recursion,
        )
      end

      def fetch_override(hash, *keys)
        keys.each do |key|
          return hash[key] if hash.key?(key)

          k = key.to_s
          return hash[k] if hash.key?(k)

          sym = k.to_sym
          return hash[sym] if hash.key?(sym)
        end

        nil
      end

      # Like fetch_override, but returns [present, value] so false/nil can be distinguished.
      def fetch_override_presence(hash, *keys)
        keys.each do |key|
          return [true, hash[key]] if hash.key?(key)

          k = key.to_s
          return [true, hash[k]] if hash.key?(k)

          sym = k.to_sym
          return [true, hash[sym]] if hash.key?(sym)
        end

        [false, nil]
      end

      def apply_inclusion_groups!(candidates, selected_keys:, selected_groups:, timed_effects:, scan_state:, scan_messages:,
                                  default_scan_depth:, recurse_buffer:, scan_context:, scan_injects:, use_group_scoring:, rng:)
        grouped = {}
        candidates.each do |c|
          groups = group_names(c.entry)
          next if groups.empty?

          groups.each do |g|
            (grouped[g] ||= []) << c
          end
        end

        return if grouped.empty?

        removed = {}
        remove_candidate = lambda do |cand, reason|
          return if removed[cand.object_id]

          cand.selected = false
          cand.dropped_reason = reason
          candidates.delete(cand)
          removed[cand.object_id] = true
        end

        grouped.each do |group_name, group_candidates|
          group_candidates = group_candidates.select { |c| !removed[c.object_id] && candidates.include?(c) }
          next if group_candidates.empty?

          sticky_in_group = group_candidates.select { |c| timed_effects.sticky_active?(c.entry) || c.activation_type.to_sym == :sticky }
          if sticky_in_group.any?
            (group_candidates - sticky_in_group).each { |c| remove_candidate.call(c, "group_sticky_loser") }
            next
          end

          if selected_groups[group_name]
            group_candidates.each { |c| remove_candidate.call(c, "group_already_activated") }
            next
          end

          # Group scoring filter
          if !!use_group_scoring || group_candidates.any? { |c| c.entry.use_group_scoring }
            scores = group_candidates.map do |c|
              entry_match_score(
                c.entry,
                scan_state: scan_state,
                scan_messages: scan_messages,
                default_scan_depth: default_scan_depth,
                recurse_buffer: recurse_buffer,
                scan_context: scan_context,
                scan_injects: scan_injects,
              )
            end
            max_score = scores.max || 0

            group_candidates.each_with_index do |c, idx|
              scored = c.entry.use_group_scoring.nil? ? !!use_group_scoring : !!c.entry.use_group_scoring
              next unless scored
              next unless scores[idx] < max_score

              remove_candidate.call(c, "group_score_loser")
            end

            group_candidates = group_candidates.select { |c| !removed[c.object_id] && candidates.include?(c) }
            next if group_candidates.empty?
          end

          next if group_candidates.length <= 1

          # Priority winner: group_override
          overrides = group_candidates.select { |c| c.entry.group_override }
          if overrides.any?
            winner = overrides.max_by { |c| c.entry.insertion_order.to_i }
            (group_candidates - [winner]).each { |c| remove_candidate.call(c, "group_loser") }
            next
          end

          # Weighted random winner
          total_weight = group_candidates.sum { |c| c.entry.group_weight.to_i }
          if total_weight <= 0
            winner = group_candidates.first
          else
            roll = rng.rand * total_weight
            running = 0
            winner = group_candidates.find do |c|
              running += c.entry.group_weight.to_i
              roll <= running
            end
            winner ||= group_candidates.last
          end

          (group_candidates - [winner]).each { |c| remove_candidate.call(c, "group_loser") }
        end
      end

      def entry_match_score(entry, scan_state:, scan_messages:, default_scan_depth:, recurse_buffer:, scan_context:, scan_injects:)
        include_recurse = (scan_state != :min_activations)
        text = effective_scan_text_for_entry(
          entry,
          scan_messages,
          default_scan_depth: default_scan_depth,
          recurse_buffer: recurse_buffer,
          scan_context: scan_context,
          scan_injects: scan_injects,
          include_recurse: include_recurse,
        )

        primary = Array(entry.keys)
        return 0 if primary.empty?

        case_sensitive = entry_case_sensitive(entry)
        match_whole_words = entry_match_whole_words(entry)

        primary_score = primary.count { |k| key_matches?(k, text, case_sensitive: case_sensitive, match_whole_words: match_whole_words) }

        secondary = entry.selective ? Array(entry.secondary_keys) : []
        secondary_score = secondary.count { |k| key_matches?(k, text, case_sensitive: case_sensitive, match_whole_words: match_whole_words) }

        return primary_score if secondary.empty?

        case entry.selective_logic
        when :and_any
          primary_score + secondary_score
        when :and_all
          secondary_score == secondary.length ? (primary_score + secondary_score) : primary_score
        else
          primary_score
        end
      end

      def match_any_primary(keys, text, case_sensitive:, match_whole_words:, use_regex: false)
        keys = Array(keys)
        return [] if keys.empty?

        keys.select { |k| key_matches?(k, text, case_sensitive: case_sensitive, match_whole_words: match_whole_words, use_regex: use_regex) }
      end

      def match_secondary(entry, text, case_sensitive:, match_whole_words:)
        return [] unless entry.selective

        keys = Array(entry.secondary_keys)
        return [] if keys.empty?

        # Secondary keys follow same use_regex setting as primary keys
        keys.select { |k| key_matches?(k, text, case_sensitive: case_sensitive, match_whole_words: match_whole_words, use_regex: entry.use_regex?) }
      end

      def secondary_pass?(entry, matched_secondary)
        return true unless entry.selective

        keys = Array(entry.secondary_keys)
        return true if keys.empty?

        case entry.selective_logic
        in :and_any then matched_secondary.any?
        in :and_all then matched_secondary.length == keys.length
        in :not_any then matched_secondary.empty?
        in :not_all then matched_secondary.length != keys.length
        else
          raise ArgumentError, "Unknown selective_logic: #{entry.selective_logic.inspect}"
        end
      end

      def key_matches?(key, text, case_sensitive: @case_sensitive, match_whole_words: @match_whole_words, use_regex: false)
        return false if key.nil?

        k = key.to_s
        return false if k.strip.empty?

        # CCv3: When use_regex is true, treat key as a regex pattern (not just JS literals)
        if use_regex
          return regex_key_matches?(k, text, case_sensitive: case_sensitive)
        end

        # JS regex literal: /pattern/flags
        # Uses js_regex_to_ruby gem with literal_only: true to only parse
        # strings that look like JS regex literals (e.g., "/pattern/flags").
        # Plain keywords like "cat" return nil and are matched as plain strings.
        if (re = JsRegexToRuby.try_convert(k, literal_only: true))
          return !!(text =~ re)
        end

        haystack = text.to_s
        needle = k

        unless case_sensitive
          haystack = haystack.downcase
          needle = needle.downcase
        end

        return haystack.include?(needle) unless match_whole_words

        # ST behavior:
        # - If the needle contains whitespace (multiple "words"), use substring matching.
        # - Otherwise, use non-word boundaries (JS \W == [^A-Za-z0-9_]).
        words = needle.split(/\s+/)
        return haystack.include?(needle) if words.length > 1

        boundary = "[^A-Za-z0-9_]"
        re = Regexp.new("(?:^|#{boundary})#{Regexp.escape(needle)}(?:$|#{boundary})")
        !!(haystack =~ re)
      end

      # Matches a key as a regex pattern against text.
      # CCv3 specifies that use_regex keys can be JS regex literals (/pattern/flags)
      # or plain patterns. We support both.
      #
      # @param pattern [String] the regex pattern to match
      # @param text [String] the text to search
      # @param case_sensitive [Boolean] whether matching is case-sensitive
      # @return [Boolean] true if pattern matches
      def regex_key_matches?(pattern, text, case_sensitive: true)
        # First try as JS regex literal: /pattern/flags
        if (re = JsRegexToRuby.try_convert(pattern, literal_only: true))
          return !!(text =~ re)
        end

        # Plain pattern string - compile as regex with case sensitivity
        begin
          options = case_sensitive ? 0 : Regexp::IGNORECASE
          re = Regexp.new(pattern, options)
          !!(text =~ re)
        rescue RegexpError
          # Invalid regex pattern - treat as no match
          # This matches ST behavior where invalid regex patterns don't crash
          false
        end
      end

      # Per-entry overrides are stored in entry.case_sensitive (CCv3) or
      # entry.raw (SillyTavern exports). Falls back to engine default.
      def entry_case_sensitive(entry)
        # CCv3: check entry.case_sensitive first (if explicitly set)
        return entry.case_sensitive unless entry.case_sensitive.nil?

        # Legacy: check raw hash for ST format
        raw = entry.raw || {}
        v = if raw.key?("caseSensitive")
          raw["caseSensitive"]
        elsif raw.key?(:caseSensitive)
          raw[:caseSensitive]
        elsif raw.key?("case_sensitive")
          raw["case_sensitive"]
        elsif raw.key?(:case_sensitive)
          raw[:case_sensitive]
        end
        v.nil? ? @case_sensitive : truthy?(v)
      end

      def entry_match_whole_words(entry)
        raw = entry.raw || {}
        v = if raw.key?("matchWholeWords")
          raw["matchWholeWords"]
        elsif raw.key?(:matchWholeWords)
          raw[:matchWholeWords]
        elsif raw.key?("match_whole_words")
          raw["match_whole_words"]
        elsif raw.key?(:match_whole_words)
          raw[:match_whole_words]
        end
        v.nil? ? @match_whole_words : truthy?(v)
      end

      def truthy?(value)
        case value
        in true | false then value
        else
          case value.to_s.strip.downcase
          in "1" | "true" | "yes" | "y" | "on" then true
          in "0" | "false" | "no" | "n" | "off" then false
          else !!value
          end
        end
      end

      # Build effective scan text for an entry by appending context fields
      # based on the entry's match_* flags.
      #
      # ST behavior: each entry can optionally include character/persona fields
      # in its scan buffer via per-entry match_* flags.
      #
      # @param entry [Lore::Entry] the entry to evaluate
      # @param base_scan_text [String] the base scan buffer (chat messages)
      # @param scan_context [Hash] context fields from character/persona
      # @return [String] the effective scan text for this entry
      def build_entry_scan_text(entry, base_scan_text, scan_context)
        # If no match_* flags are set, just return the base text
        return base_scan_text unless entry.has_match_flags?

        parts = [base_scan_text]

        # Append context fields based on match_* flags
        # Using the same joiner as ST: newline
        if entry.match_persona_description? && scan_context[:persona_description].to_s.strip.length > 0
          parts << scan_context[:persona_description]
        end

        if entry.match_character_description? && scan_context[:character_description].to_s.strip.length > 0
          parts << scan_context[:character_description]
        end

        if entry.match_character_personality? && scan_context[:character_personality].to_s.strip.length > 0
          parts << scan_context[:character_personality]
        end

        if entry.match_character_depth_prompt? && scan_context[:character_depth_prompt].to_s.strip.length > 0
          parts << scan_context[:character_depth_prompt]
        end

        if entry.match_scenario? && scan_context[:scenario].to_s.strip.length > 0
          parts << scan_context[:scenario]
        end

        if entry.match_creator_notes? && scan_context[:creator_notes].to_s.strip.length > 0
          parts << scan_context[:creator_notes]
        end

        parts.join("\n")
      end
    end
  end
end
