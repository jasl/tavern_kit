# frozen_string_literal: true

module TavernKit
  module Lore
    # Parses CCv3 @@decorator syntax from lorebook entry content.
    #
    # Decorators are inline settings that override or extend the entry's
    # field values. They appear at the start of the content, one per line,
    # before the actual entry content.
    #
    # Supported decorators (CCv3 spec):
    # - @@depth N - Insert at message depth N
    # - @@role system|user|assistant - Set message role
    # - @@position before_desc|after_desc|... - Set insertion position
    # - @@scan_depth N - Override scan depth for this entry
    # - @@activate_only_after N - Only activate after N messages
    # - @@activate_only_every N - Only activate every N messages
    # - @@constant - Always activate
    # - @@dont_activate - Never activate via keywords
    # - @@activate - Force activate (cancels @@dont_activate)
    # - @@additional_keys a,b,c - Add extra activation keys
    # - @@exclude_keys a,b,c - Exclude these keys from activation
    # - @@ignore_on_max_context - Skip this entry when context is full
    #
    # Fallback decorators (@@@name) apply only when the entry wasn't
    # directly activated but was triggered recursively.
    #
    # @example
    #   content = <<~CONTENT
    #     @@depth 2
    #     @@role assistant
    #     This is the actual content.
    #   CONTENT
    #
    #   parser = DecoratorParser.new
    #   result = parser.parse(content)
    #   result[:decorators]
    #   # => { depth: 2, role: "assistant" }
    #   result[:content]
    #   # => "This is the actual content."
    #
    # @see https://github.com/kwaroran/character-card-spec-v3
    class DecoratorParser
      # Standard decorator: @@name or @@name value
      DECORATOR_PATTERN = /\A@@(\w+)(?:\s+(.+))?\z/

      # Fallback decorator: @@@name (applies only on recursive activation)
      FALLBACK_PATTERN = /\A@@@(\w+)(?:\s+(.+))?\z/

      # Decorators that take no value (flags)
      FLAG_DECORATORS = Set.new(%w[constant dont_activate activate ignore_on_max_context use_regex case_sensitive]).freeze

      # Decorators that take numeric values
      NUMERIC_DECORATORS = Set.new(%w[depth scan_depth activate_only_after activate_only_every]).freeze

      # Decorators that take list values (comma-separated)
      LIST_DECORATORS = Set.new(%w[additional_keys exclude_keys]).freeze

      # Valid position values
      VALID_POSITIONS = Set.new(%w[
        before_desc after_desc before_char_defs after_char_defs
        before_example_messages after_example_messages
        top_an bottom_an at_depth in_chat depth outlet
      ]).freeze

      # Valid role values
      VALID_ROLES = Set.new(%w[system user assistant]).freeze

      # Parses decorator lines from entry content.
      #
      # @param content [String] the raw entry content
      # @return [Hash] with keys:
      #   - :decorators [Hash] parsed decorator name => value
      #   - :fallback_decorators [Hash] parsed fallback decorator name => value
      #   - :content [String] content after decorators are stripped
      def parse(content)
        return { decorators: {}, fallback_decorators: {}, content: "" } if content.nil? || content.empty?

        lines = content.lines
        decorators = {}
        fallback_decorators = {}
        content_start = nil

        lines.each_with_index do |line, idx|
          stripped = line.strip

          # Empty lines before content are skipped
          if stripped.empty?
            next
          end

          # Check for fallback decorator first (@@@)
          if (match = stripped.match(FALLBACK_PATTERN))
            name, value = match[1], match[2]
            parsed_value = parse_decorator_value(name.downcase, value)
            fallback_decorators[name.downcase.to_sym] = parsed_value
            next
          end

          # Check for standard decorator (@@)
          if (match = stripped.match(DECORATOR_PATTERN))
            name, value = match[1], match[2]
            parsed_value = parse_decorator_value(name.downcase, value)
            decorators[name.downcase.to_sym] = parsed_value
            next
          end

          # First non-decorator, non-empty line marks content start
          content_start = idx
          break
        end

        # Content is everything from content_start onwards
        # If content_start is nil, all lines were decorators/empty - return empty content
        remaining = content_start.nil? ? "" : lines[content_start..].join

        {
          decorators: decorators,
          fallback_decorators: fallback_decorators,
          content: remaining,
        }
      end

      # Applies parsed decorators to an entry's attributes.
      #
      # @param entry_attrs [Hash] entry attributes to modify
      # @param decorators [Hash] parsed decorators from parse()
      # @param is_fallback [Boolean] whether to apply fallback decorators
      # @return [Hash] modified attributes
      def apply(entry_attrs, decorators:, fallback_decorators: {}, is_fallback: false)
        attrs = entry_attrs.dup

        # Choose which decorators to apply
        applicable = is_fallback ? fallback_decorators : decorators

        applicable.each do |name, value|
          case name
          when :depth
            attrs[:depth] = value.to_i
          when :role
            attrs[:role] = value.to_sym if VALID_ROLES.include?(value.to_s)
          when :position
            attrs[:position] = normalize_position(value.to_s)
          when :scan_depth
            attrs[:scan_depth] = value.to_i
          when :activate_only_after
            attrs[:activate_only_after] = value.to_i
          when :activate_only_every
            attrs[:activate_only_every] = value.to_i
          when :constant
            attrs[:constant] = true
          when :dont_activate
            attrs[:dont_activate] = true
          when :activate
            attrs[:dont_activate] = false
          when :ignore_on_max_context
            attrs[:ignore_on_max_context] = true
          when :additional_keys
            # Merge with existing keys
            attrs[:keys] = (Array(attrs[:keys]) + Array(value)).uniq
          when :exclude_keys
            # Store separately for filtering
            attrs[:exclude_keys] = Array(value)
          end
        end

        attrs
      end

      private

      def parse_decorator_value(name, value)
        name = name.downcase

        # Flag decorators (no value needed)
        if FLAG_DECORATORS.include?(name)
          return true
        end

        # Numeric decorators
        if NUMERIC_DECORATORS.include?(name)
          return value.to_s.strip.to_i
        end

        # List decorators (comma-separated)
        if LIST_DECORATORS.include?(name)
          return parse_list(value)
        end

        # Role decorator
        if name == "role"
          role = value.to_s.strip.downcase
          return role if VALID_ROLES.include?(role)
          return nil
        end

        # Position decorator
        if name == "position"
          pos = value.to_s.strip.downcase
          return normalize_position(pos)
        end

        # Default: return trimmed string value
        value.to_s.strip
      end

      def parse_list(value)
        return [] if value.nil? || value.to_s.strip.empty?

        value.to_s.split(",").map(&:strip).reject(&:empty?)
      end

      def normalize_position(value)
        pos = value.to_s.strip.downcase

        # Map common aliases to canonical names
        case pos
        when "before_desc", "before_main", "before_char_defs"
          :before_char_defs
        when "after_desc", "after_main", "after_char_defs"
          :after_char_defs
        when "before_example_messages"
          :before_example_messages
        when "after_example_messages"
          :after_example_messages
        when "top_an", "top_of_an"
          :top_of_an
        when "bottom_an", "bottom_of_an"
          :bottom_of_an
        when "at_depth", "depth", "in_chat"
          :at_depth
        when "outlet"
          :outlet
        else
          :after_char_defs # default
        end
      end
    end
  end
end
