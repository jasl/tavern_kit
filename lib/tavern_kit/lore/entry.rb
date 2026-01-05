# frozen_string_literal: true

require_relative "key_list"

module TavernKit
  module Lore
    # A single lore entry within a Book (World Info entry).
    #
    # Entries are activated during prompt generation when their keywords
    # are matched in the scan buffer. Activated entries inject their content
    # into the prompt at the configured position.
    class Entry
      POSITIONS = %i[
        before_char_defs after_char_defs before_example_messages after_example_messages
        top_of_an bottom_of_an at_depth outlet
      ].freeze

      SELECTIVE_LOGIC = %i[and_any and_all not_any not_all].freeze
      ROLES = %i[system user assistant].freeze

      POSITION_MAP = {
        0 => :before_char_defs, 1 => :after_char_defs, 2 => :top_of_an, 3 => :bottom_of_an,
        4 => :at_depth, 5 => :before_example_messages, 6 => :after_example_messages, 7 => :outlet,
        "before_char" => :before_char_defs, "before_char_defs" => :before_char_defs,
        "after_char" => :after_char_defs, "after_char_defs" => :after_char_defs,
        "before_main" => :before_char_defs, "after_main" => :after_char_defs,
        "before_example_messages" => :before_example_messages, "after_example_messages" => :after_example_messages,
        "top_an" => :top_of_an, "top_of_an" => :top_of_an, "bottom_an" => :bottom_of_an, "bottom_of_an" => :bottom_of_an,
        "@d" => :at_depth, "at_depth" => :at_depth, "depth" => :at_depth, "in_chat" => :at_depth, "outlet" => :outlet,
      }.freeze

      SELECTIVE_LOGIC_MAP = {
        0 => :and_any, 1 => :not_all, 2 => :not_any, 3 => :and_all,
        "and_any" => :and_any, "and_all" => :and_all, "not_any" => :not_any, "not_all" => :not_all,
      }.freeze

      attr_reader :uid, :comment, :keys, :secondary_keys, :selective, :selective_logic,
                  :content, :enabled, :constant, :insertion_order, :position, :depth, :role,
                  :outlet, :triggers, :scan_depth, :source, :book_name, :raw,
                  :match_persona_description, :match_character_description, :match_character_personality,
                  :match_character_depth_prompt, :match_scenario, :match_creator_notes,
                  :ignore_budget, :use_probability, :probability, :group, :group_override,
                  :group_weight, :use_group_scoring, :automation_id, :sticky, :cooldown, :delay,
                  :exclude_recursion, :prevent_recursion, :delay_until_recursion

      def initialize(uid:, keys:, content:, **opts)
        @uid = uid
        @keys = Array(keys).freeze
        @content = content.to_s
        @secondary_keys = Array(opts[:secondary_keys]).freeze
        @selective = opts.fetch(:selective) { @secondary_keys.any? }
        @selective_logic = opts[:selective_logic] || :and_any
        @enabled = opts.fetch(:enabled, true)
        @constant = opts.fetch(:constant, false)
        @insertion_order = opts[:insertion_order].to_i
        @position = opts[:position] || :after_char_defs
        @depth = opts[:depth].to_i
        @role = opts[:role] || :system
        @outlet = opts[:outlet]&.to_s
        @triggers = Array(opts[:triggers]).uniq.freeze
        @scan_depth = opts[:scan_depth]
        @source = opts[:source]&.to_sym
        @book_name = opts[:book_name]&.to_s
        @comment = opts[:comment]&.to_s
        @raw = opts[:raw]
        @match_persona_description = !!opts[:match_persona_description]
        @match_character_description = !!opts[:match_character_description]
        @match_character_personality = !!opts[:match_character_personality]
        @match_character_depth_prompt = !!opts[:match_character_depth_prompt]
        @match_scenario = !!opts[:match_scenario]
        @match_creator_notes = !!opts[:match_creator_notes]
        @ignore_budget = !!opts[:ignore_budget]
        @use_probability = opts.fetch(:use_probability, true)
        @probability = [[opts[:probability].to_i, 0].max, 100].min
        @probability = 100 if opts[:probability].nil?
        @group = opts[:group]&.to_s&.then { |s| s.strip.empty? ? nil : s }
        @group_override = !!opts[:group_override]
        @group_weight = [opts[:group_weight].to_i, 1].max
        @group_weight = 100 if opts[:group_weight].nil?
        @use_group_scoring = opts[:use_group_scoring]
        @automation_id = opts[:automation_id]&.to_s || ""
        @sticky = positive_int(opts[:sticky])
        @cooldown = positive_int(opts[:cooldown])
        @delay = positive_int(opts[:delay])
        @exclude_recursion = !!opts[:exclude_recursion]
        @prevent_recursion = !!opts[:prevent_recursion]
        @delay_until_recursion = parse_delay_until_recursion(opts[:delay_until_recursion])
      end

      def enabled? = @enabled
      def constant? = @constant
      def match_persona_description? = @match_persona_description
      def match_character_description? = @match_character_description
      def match_character_personality? = @match_character_personality
      def match_character_depth_prompt? = @match_character_depth_prompt
      def match_scenario? = @match_scenario
      def match_creator_notes? = @match_creator_notes

      def has_match_flags?
        @match_persona_description || @match_character_description || @match_character_personality ||
          @match_character_depth_prompt || @match_scenario || @match_creator_notes
      end

      # Returns true if this entry should only activate during recursive scans.
      def delay_until_recursion?
        !@delay_until_recursion.nil? && @delay_until_recursion != false
      end

      # Returns the recursion level at which this entry becomes eligible (1+).
      # Returns nil if delay_until_recursion is not enabled.
      def delay_until_recursion_level
        return nil unless delay_until_recursion?

        @delay_until_recursion == true ? 1 : @delay_until_recursion.to_i
      end

      def triggered_by?(generation_type)
        return true if @triggers.empty?

        @triggers.include?(Coerce.generation_type(generation_type))
      end

      def to_h
        {
          uid: uid, comment: comment, keys: keys, secondary_keys: secondary_keys,
          selective: selective, selective_logic: selective_logic, content: content,
          enabled: enabled, constant: constant, insertion_order: insertion_order,
          position: position, depth: depth, role: role, outlet: outlet, triggers: triggers,
          scan_depth: scan_depth, source: source, book_name: book_name,
          match_persona_description: match_persona_description,
          match_character_description: match_character_description,
          match_character_personality: match_character_personality,
          match_character_depth_prompt: match_character_depth_prompt,
          match_scenario: match_scenario, match_creator_notes: match_creator_notes,
          ignore_budget: ignore_budget, use_probability: use_probability, probability: probability,
          group: group, group_override: group_override, group_weight: group_weight,
          use_group_scoring: use_group_scoring, automation_id: automation_id,
          sticky: sticky, cooldown: cooldown, delay: delay,
          exclude_recursion: exclude_recursion, prevent_recursion: prevent_recursion,
          delay_until_recursion: delay_until_recursion,
        }
      end

      # Creates an Entry from Character Card V2 or SillyTavern World Info hash.
      def self.from_hash(hash, uid: nil, source: nil, book_name: nil)
        h = Utils::HashAccessor.new(hash)

        disable = h[:disable]
        enabled_val = disable.nil? ? h.bool(:enabled, default: true) : !to_bool(disable)

        new(
          uid: uid || h[:uid, :id] || SecureRandom.uuid,
          keys: KeyList.parse(h[:keys, :key]),
          content: h[:content].to_s,
          secondary_keys: KeyList.parse(h[:secondary_keys, :keysecondary]),
          selective: h[:selective].nil? ? nil : to_bool(h[:selective]),
          selective_logic: coerce_selective_logic(h[:selective_logic, :selectiveLogic, :selective_logic_mode]),
          enabled: enabled_val,
          constant: h.bool(:constant, default: false),
          insertion_order: h.int(:insertion_order, :order, :insertionOrder, :priority),
          position: coerce_position(h[:position, :pos]),
          depth: h.int(:depth, :insert_depth),
          role: Coerce.role(h[:role, :depth_role], default: :system),
          outlet: h[:outlet, :outlet_name, :outletName]&.to_s,
          triggers: Coerce.triggers(h[:triggers] || h.dig(:extensions, :triggers)),
          scan_depth: h.positive_int(:scanDepth, :scan_depth, ext_key: :scan_depth),
          source: source,
          book_name: book_name,
          comment: h[:comment, :memo]&.to_s,
          raw: hash,
          match_persona_description: h.bool(:matchPersonaDescription, :match_persona_description, ext_key: :match_persona_description),
          match_character_description: h.bool(:matchCharacterDescription, :match_character_description, ext_key: :match_character_description),
          match_character_personality: h.bool(:matchCharacterPersonality, :match_character_personality, ext_key: :match_character_personality),
          match_character_depth_prompt: h.bool(:matchCharacterDepthPrompt, :match_character_depth_prompt, ext_key: :match_character_depth_prompt),
          match_scenario: h.bool(:matchScenario, :match_scenario, ext_key: :match_scenario),
          match_creator_notes: h.bool(:matchCreatorNotes, :match_creator_notes, ext_key: :match_creator_notes),
          ignore_budget: h.bool(:ignoreBudget, :ignore_budget, ext_key: :ignore_budget),
          use_probability: h.bool(:useProbability, :use_probability, default: true),
          probability: h.int(:probability, ext_key: :probability, default: 100),
          group: h.presence(:group, ext_key: :group),
          group_override: h.bool(:groupOverride, :group_override, ext_key: :group_override),
          group_weight: h.int(:groupWeight, :group_weight, ext_key: :group_weight, default: 100),
          use_group_scoring: h[:useGroupScoring, :use_group_scoring].nil? ? h.dig(:extensions, :use_group_scoring)&.then { |v| to_bool(v) } : to_bool(h[:useGroupScoring, :use_group_scoring]),
          automation_id: h.str(:automationId, :automation_id, ext_key: :automation_id, default: ""),
          sticky: h.positive_int(:sticky, ext_key: :sticky),
          cooldown: h.positive_int(:cooldown, ext_key: :cooldown),
          delay: h.positive_int(:delay, ext_key: :delay),
          exclude_recursion: h.bool(:excludeRecursion, :exclude_recursion, ext_key: :exclude_recursion),
          prevent_recursion: h.bool(:preventRecursion, :prevent_recursion, ext_key: :prevent_recursion),
          delay_until_recursion: coerce_delay_until_recursion(h[:delayUntilRecursion, :delay_until_recursion] || h.dig(:extensions, :delay_until_recursion)),
        )
      end

      def self.coerce_position(value)
        return :after_char_defs unless value
        return value if POSITIONS.include?(value)

        key = value.is_a?(Integer) ? value : value.to_s.strip.downcase
        POSITION_MAP[key] || :after_char_defs
      end

      def self.coerce_selective_logic(value)
        return :and_any unless value

        key = value.is_a?(Integer) ? value : value.to_s.strip.downcase
        SELECTIVE_LOGIC_MAP[key] || :and_any
      end

      def self.to_bool(val)
        return val if val == true || val == false

        %w[1 true yes y on].include?(val.to_s.strip.downcase)
      end

      # Coerce delay_until_recursion value from ST format.
      # ST stores this as: false (disabled), true (level 1), or integer (specific level).
      def self.coerce_delay_until_recursion(value)
        return nil if value.nil?
        return false if value == false || value == 0 || value.to_s.strip.downcase == "false"
        return true if value == true || value.to_s.strip.downcase == "true"

        # Numeric value indicates recursion level
        level = value.to_i
        level.positive? ? level : nil
      end

      private_class_method :coerce_position, :coerce_selective_logic, :to_bool, :coerce_delay_until_recursion

      private

      def positive_int(val)
        return nil unless val

        i = val.to_i
        i.positive? ? i : nil
      end

      # Parse delay_until_recursion value.
      # Returns nil (disabled), false (explicitly disabled), true (level 1), or integer (specific level).
      def parse_delay_until_recursion(value)
        return nil if value.nil?
        return false if value == false || value == 0
        return true if value == true

        level = value.to_i
        level.positive? ? level : nil
      end
    end
  end
end
