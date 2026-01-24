# frozen_string_literal: true

module Translation
  class Masker
    Masked = Data.define(:text, :replacements, :tokens)

    TOKEN_PATTERN = /⟦MASK_(\d+)⟧/.freeze
    CODE_FENCE_PATTERN = /```.*?```/m.freeze
    INLINE_CODE_PATTERN = /`[^`\n]+`/.freeze
    URL_PATTERN = %r{https?://[^\s)]+}.freeze
    HANDLEBARS_BLOCK_PATTERN = /\{\{#\s*([a-zA-Z0-9_]+)[^}]*\}\}.*?\{\{\/\s*\1\s*\}\}/m.freeze
    HANDLEBARS_PATTERN = /\{\{[^}]+\}\}/.freeze

    def initialize(masking:)
      @masking = masking
    end

    def mask(text)
      return Masked.new(text: text.to_s, replacements: {}, tokens: []) unless enabled?

      replacements = {}
      tokens = []
      masked = text.to_s.dup
      index = 0

      rules.each do |pattern|
        masked = masked.gsub(pattern) do |match|
          token = "⟦MASK_#{index}⟧"
          index += 1
          replacements[token] = match
          tokens << token
          token
        end
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

    def enabled?
      masking.respond_to?(:enabled) ? masking.enabled : true
    end

    def rules
      [].tap do |list|
        list << CODE_FENCE_PATTERN if protect?(:protect_code_blocks)
        list << INLINE_CODE_PATTERN if protect?(:protect_inline_code)
        list << URL_PATTERN if protect?(:protect_urls)
        if protect?(:protect_handlebars)
          list << HANDLEBARS_BLOCK_PATTERN
          list << HANDLEBARS_PATTERN
        end
      end
    end

    def protect?(field)
      return true unless masking.respond_to?(field)

      masking.public_send(field)
    end
  end
end
