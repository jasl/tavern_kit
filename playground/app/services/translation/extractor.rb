# frozen_string_literal: true

module Translation
  class Extractor
    TEXTAREA_PATTERN = /<textarea[^>]*>(.*?)<\/textarea>/m.freeze

    def self.extract!(raw)
      match = TEXTAREA_PATTERN.match(raw.to_s)
      raise ExtractionError, "missing <textarea> wrapper" unless match

      match[1]
    end
  end
end
