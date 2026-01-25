# frozen_string_literal: true

module Translation
  class Masker
    Masked = Data.define(:text, :replacements, :tokens)

    TOKEN_PATTERN = /⟦MASK_(\d+)⟧/.freeze
    CODE_FENCE_PATTERN = /```.*?```/m.freeze
    INLINE_CODE_PATTERN = /`[^`\n]+`/.freeze
    URL_PATTERN = %r{https?://[^\s)]+}.freeze
    HANDLEBARS_PATTERN = /\{\{[^}]+\}\}/.freeze
    HANDLEBARS_OPEN_PATTERN = /\{\{#\s*([a-zA-Z0-9_]+)[^}]*\}\}/.freeze
    HANDLEBARS_CLOSE_PATTERN = /\{\{\/\s*([a-zA-Z0-9_]+)\s*\}\}/.freeze

    def initialize(masking:)
      @masking = masking
    end

    def mask(text)
      return Masked.new(text: text.to_s, replacements: {}, tokens: []) unless enabled?

      replacements = {}
      tokens = []
      masked = text.to_s.dup
      index = 0

      if protect?(:protect_code_blocks)
        masked, index = mask_pattern(masked, CODE_FENCE_PATTERN, replacements: replacements, tokens: tokens, index: index)
      end

      if protect?(:protect_inline_code)
        masked, index = mask_pattern(masked, INLINE_CODE_PATTERN, replacements: replacements, tokens: tokens, index: index)
      end

      if protect?(:protect_urls)
        masked, index = mask_pattern(masked, URL_PATTERN, replacements: replacements, tokens: tokens, index: index)
      end

      if protect?(:protect_handlebars)
        masked, index = mask_handlebars_blocks(masked, replacements: replacements, tokens: tokens, index: index)
        masked, index = mask_pattern(masked, HANDLEBARS_PATTERN, replacements: replacements, tokens: tokens, index: index)
      end

      Masked.new(text: masked, replacements: replacements, tokens: tokens)
    end

    def unmask(text, replacements:)
      return text.to_s if replacements.empty?

      text.to_s.gsub(TOKEN_PATTERN) do |token|
        replacements.fetch(token, token)
      end
    end

    def validate_tokens!(text, tokens:)
      return if tokens.empty?

      tokens.each do |token|
        count = text.to_s.scan(token).length
        next if count == 1

        raise MaskMismatchError, "token mismatch for #{token} (count=#{count})"
      end
    end

    private

    attr_reader :masking

    def mask_pattern(text, pattern, replacements:, tokens:, index:)
      masked =
        text.to_s.gsub(pattern) do |match|
          token = "⟦MASK_#{index}⟧"
          index += 1
          replacements[token] = match
          tokens << token
          token
        end

      [masked, index]
    end

    def mask_handlebars_blocks(text, replacements:, tokens:, index:)
      ranges = []
      stack = []

      str = text.to_s
      offset = 0

      while offset < str.length
        open_match = HANDLEBARS_OPEN_PATTERN.match(str, offset)
        close_match = HANDLEBARS_CLOSE_PATTERN.match(str, offset)

        next_match =
          if open_match && close_match
            open_match.begin(0) <= close_match.begin(0) ? open_match : close_match
          else
            open_match || close_match
          end

        break unless next_match

        if next_match == open_match
          stack << { name: open_match[1], start: open_match.begin(0) }
          offset = open_match.end(0)
          next
        end

        name = close_match[1]
        if stack.any? && stack.last[:name] == name
          open = stack.pop
          ranges << [open[:start], close_match.end(0)] if stack.empty?
        end

        offset = close_match.end(0)
      end

      return [str, index] if ranges.empty?

      masked = str.dup
      ranges.sort_by!(&:first)

      ranges.reverse_each do |start, finish|
        token = "⟦MASK_#{index}⟧"
        index += 1
        original = masked.slice(start...finish)
        replacements[token] = original
        tokens << token
        masked[start...finish] = token
      end

      [masked, index]
    end

    def enabled?
      masking.respond_to?(:enabled) ? masking.enabled : true
    end

    def protect?(field)
      return true unless masking.respond_to?(field)

      masking.public_send(field)
    end
  end
end
