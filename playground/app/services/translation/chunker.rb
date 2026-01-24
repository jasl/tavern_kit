# frozen_string_literal: true

module Translation
  class Chunker
    TOKEN_PATTERN = Translation::Masker::TOKEN_PATTERN

    def initialize(max_chars:)
      @max_chars = Integer(max_chars)
    rescue ArgumentError, TypeError
      @max_chars = 1800
    end

    def chunk(text)
      str = text.to_s
      return [""] if str.empty?
      return [str] if str.length <= max_chars

      chunks = []
      current = +""

      str.each_line do |line|
        if current.length + line.length <= max_chars
          current << line
          next
        end

        chunks << current unless current.empty?
        current = +""

        if line.length <= max_chars
          current << line
        else
          chunks.concat(split_long_segment(line))
        end
      end

      chunks << current unless current.empty?
      chunks
    end

    private

    attr_reader :max_chars

    def split_long_segment(segment)
      remaining = segment.to_s
      pieces = []

      while remaining.length > max_chars
        idx = safe_split_index(remaining, max_chars)
        idx = max_chars if idx <= 0
        pieces << remaining.slice(0, idx)
        remaining = remaining.slice(idx, remaining.length)
      end

      pieces << remaining unless remaining.empty?
      pieces
    end

    def safe_split_index(text, desired)
      idx = desired
      text.to_s.enum_for(:scan, TOKEN_PATTERN).each do
        match = Regexp.last_match
        start = match.begin(0)
        finish = match.end(0)
        next unless start < idx && finish > idx

        return finish if start.zero?

        return start
      end
      idx
    end
  end
end
