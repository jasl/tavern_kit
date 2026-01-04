# frozen_string_literal: true

require "json"

module TavernKit
  module Lore
    # ST-compatible timed effects manager for World Info entries.
    #
    # Implements:
    # - sticky: stays active for N messages (auto-activates regardless of key match)
    # - cooldown: suppresses activation for N messages after activation (sticky overrides cooldown)
    # - delay: suppresses activation until chat length reaches N (not persisted)
    #
    # Persistence:
    # - State is stored in a TavernKit::ChatVariables store as JSON (string value).
    #
    class TimedEffects
      DEFAULT_STATE_KEY = "__tavern_kit__timed_world_info"

      EFFECT_TYPES = %w[sticky cooldown].freeze

      # @param message_count [Integer] number of chat messages (ST: chat.length)
      # @param entries [Array<Lore::Entry>] all entries visible to this evaluation
      # @param variables_store [ChatVariables::Base] persisted store
      # @param state_key [String] key used in variables_store
      # @param dry_run [Boolean] when true, does not persist changes
      def initialize(message_count:, entries:, variables_store:, state_key: DEFAULT_STATE_KEY, dry_run: false)
        @message_count = message_count.to_i
        @entries = Array(entries)
        @variables_store = variables_store
        @state_key = state_key.to_s
        @dry_run = !!dry_run

        @state = load_state
        @active = { "sticky" => {}, "cooldown" => {} }
      end

      attr_reader :message_count, :state_key

      # Computes the currently active timed effects, and cleans up expired/invalid entries.
      # Mirrors ST's `checkTimedEffects` behavior.
      #
      # @return [void]
      def check!
        ensure_state_structure!
        @active = { "sticky" => {}, "cooldown" => {} }

        process_type!("sticky") { |entry_key, entry| on_sticky_ended(entry_key, entry) }
        process_type!("cooldown") { |_entry_key, _entry| }

        save_state! unless @dry_run
      end

      # @param entry [Lore::Entry]
      # @return [Boolean]
      def delay_active?(entry)
        d = entry.delay
        return false if d.nil?

        @message_count < d.to_i
      end

      # @param entry_key [String]
      # @return [Boolean]
      def sticky_active_key?(entry_key)
        @active["sticky"].key?(entry_key.to_s)
      end

      # @param entry_key [String]
      # @return [Boolean]
      def cooldown_active_key?(entry_key)
        @active["cooldown"].key?(entry_key.to_s)
      end

      # @param entry [Lore::Entry]
      # @return [Boolean]
      def sticky_active?(entry)
        sticky_active_key?(entry_key(entry))
      end

      # @param entry [Lore::Entry]
      # @return [Boolean]
      def cooldown_active?(entry)
        cooldown_active_key?(entry_key(entry))
      end

      # Persist sticky/cooldown effects for newly activated entries.
      #
      # ST behavior: only sets effects when the entry defines the effect (non-zero),
      # and does not overwrite existing metadata for the same key.
      #
      # @param activated_entries [Array<Lore::Entry>]
      # @return [void]
      def set_effects!(activated_entries)
        return if @dry_run

        ensure_state_structure!

        Array(activated_entries).each do |entry|
          set_type_effect!("sticky", entry, protected_flag: false)
          set_type_effect!("cooldown", entry, protected_flag: false)
        end

        save_state!
      end

      # @return [Hash]
      def state
        @state
      end

      private

      def entry_key(entry)
        # Prefer book_name when available (ST: entry.world). Fall back to source for unnamed books.
        src = entry.source ? entry.source.to_s : "unknown"
        book = entry.book_name.to_s.strip
        book = "unnamed" if book.empty?

        "#{src}:#{book}.#{entry.uid}"
      end

      def load_state
        raw = @variables_store[@state_key]
        return { "sticky" => {}, "cooldown" => {} } if raw.nil? || raw.to_s.strip.empty?

        parsed = JSON.parse(raw.to_s)
        parsed.is_a?(Hash) ? parsed : { "sticky" => {}, "cooldown" => {} }
      rescue StandardError
        { "sticky" => {}, "cooldown" => {} }
      end

      def save_state!
        @variables_store[@state_key] = JSON.generate(@state)
      end

      def ensure_state_structure!
        @state = {} unless @state.is_a?(Hash)
        EFFECT_TYPES.each do |type|
          val = @state[type]
          @state[type] = val.is_a?(Hash) ? val : {}
        end
      end

      def process_type!(type)
        type = type.to_s
        effects = @state[type]
        return unless effects.is_a?(Hash)

        effects.to_a.each do |key, data|
          # Invalid structure → drop
          unless data.is_a?(Hash)
            effects.delete(key)
            next
          end

          start_i = data["start"].to_i
          end_i = data["end"].to_i
          protected_flag = !!data["protected"]

          # ST: if chat hasn't advanced since setting and not protected, remove the effect.
          if @message_count <= start_i && !protected_flag
            effects.delete(key)
            next
          end

          entry = find_entry_by_key(key)

          # ST: if entry is missing (e.g., from another character's lorebook), keep until end passed.
          if entry.nil?
            effects.delete(key) if @message_count >= end_i
            next
          end

          # Ignore invalid entries (not configured for this effect anymore).
          configured = case type
          when "sticky" then !entry.sticky.nil?
          when "cooldown" then !entry.cooldown.nil?
          else
            false
          end
          unless configured
            effects.delete(key)
            next
          end

          # Expired?
          if @message_count >= end_i
            effects.delete(key)
            yield(key, entry) if block_given?
            next
          end

          # Still active
          @active[type][key] = true
        end
      end

      def on_sticky_ended(_entry_key, entry)
        # ST: when sticky ends, immediately place the entry on cooldown if it has cooldown.
        return if entry.cooldown.nil?

        key = entry_key(entry)
        effect = build_effect(entry.cooldown, protected_flag: true)
        # ST overwrites any existing cooldown metadata to ensure cooldown starts *after* sticky ends.
        @state["cooldown"][key] = effect

        # Apply cooldown for this evaluation immediately.
        @active["cooldown"][key] = true
      end

      def build_effect(duration, protected_flag:)
        d = duration.to_i
        {
          "start" => @message_count,
          "end" => @message_count + d,
          "protected" => !!protected_flag,
        }
      end

      def set_type_effect!(type, entry, protected_flag:)
        type = type.to_s
        duration = case type
        when "sticky" then entry.sticky
        when "cooldown" then entry.cooldown
        else
          nil
        end
        return if duration.nil?

        key = entry_key(entry)
        @state[type][key] ||= build_effect(duration, protected_flag: protected_flag)
      end

      def find_entry_by_key(key)
        # key format: "#{src}:#{book}.#{uid}"
        parts = key.to_s.split(":", 2)
        return nil if parts.length != 2

        src = parts[0]
        rest = parts[1]
        idx = rest.rindex(".")
        return nil if idx.nil?

        book = rest[0...idx]
        uid = rest[(idx + 1)..]

        @entries.find do |e|
          (e.source ? e.source.to_s : "unknown") == src &&
            (e.book_name.to_s.strip.empty? ? "unnamed" : e.book_name.to_s.strip) == book &&
            e.uid.to_s == uid.to_s
        end
      end
    end
  end
end
