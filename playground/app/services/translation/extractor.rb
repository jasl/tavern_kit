# frozen_string_literal: true

module Translation
  class Extractor
    TEXTAREA_PATTERN = /<textarea[^>]*>(.*?)<\/textarea>/mi.freeze
    FENCED_CODE_BLOCK_PATTERN = /```(?:[^\n]*)\n(.*?)```/m.freeze

    def self.extract!(raw)
      extract_with_strategy!(raw).first
    end

    def self.extract_with_strategy!(raw)
      text = raw.to_s

      match = TEXTAREA_PATTERN.match(text)
      return [match[1], "textarea"] if match

      if text.match?(/<textarea/i) || text.match?(/<\/textarea>/i)
        raise ExtractionError, "malformed <textarea> wrapper"
      end

      match = FENCED_CODE_BLOCK_PATTERN.match(text)
      return [match[1], "codeblock"] if match

      if text.include?("```")
        raise ExtractionError, "malformed fenced code block wrapper"
      end

      return [text, "raw"] unless text.empty?

      raise ExtractionError, "missing translation wrapper"
    end
  end
end
