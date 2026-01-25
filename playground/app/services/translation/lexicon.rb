# frozen_string_literal: true

module Translation
  class Lexicon
    def initialize(glossary:, ntl:)
      @glossary = glossary
      @ntl = ntl
      @warnings = []
      @glossary_entries = parse_glossary_entries
      @ntl_entries = parse_ntl_entries
    end

    attr_reader :warnings

    def build(text)
      glossary_hits = glossary_hits_for(text)
      ntl_hits = ntl_hits_for(text)

      glossary_lines = glossary_hits.any? ? build_glossary_lines(glossary_hits) : ""
      ntl_lines = ntl_hits.any? ? build_ntl_lines(ntl_hits) : ""

      Result.new(
        glossary_lines: glossary_lines,
        ntl_lines: ntl_lines,
        glossary_digest: glossary_lines.present? ? Digest::SHA256.hexdigest(glossary_lines) : "",
        ntl_digest: ntl_lines.present? ? Digest::SHA256.hexdigest(ntl_lines) : "",
      )
    end

    private

    Result = Data.define(:glossary_lines, :ntl_lines, :glossary_digest, :ntl_digest)

    attr_reader :glossary, :ntl, :glossary_entries, :ntl_entries

    def parse_glossary_entries
      return [] unless glossary&.respond_to?(:enabled) && glossary.enabled

      parse_entries_json(glossary.entries_json, context: "glossary").filter_map do |entry|
        src = entry["src"].presence || entry["source"].presence
        dst = entry["dst"].presence || entry["target"].presence
        next if src.blank? || dst.blank?

        { "src" => src, "dst" => dst }
      end.then { |items| uniq_by(items) { |h| h["src"] } }
    end

    def parse_ntl_entries
      return [] unless ntl&.respond_to?(:enabled) && ntl.enabled

      parse_entries_json(ntl.entries_json, context: "ntl").filter_map do |entry|
        kind = entry["kind"].to_s

        if kind == "regex"
          pattern = entry["pattern"].to_s
          next if pattern.blank?

          begin
            { kind: :regex, regex: Regexp.new(pattern) }
          rescue RegexpError => e
            warnings << "ntl regex invalid: #{e.message}"
            next
          end
        else
          literal = entry["text"].presence || entry["pattern"].presence
          next if literal.blank?

          { kind: :literal, text: literal.to_s }
        end
      end
    end

    def glossary_hits_for(text)
      str = text.to_s
      return [] if glossary_entries.empty? || str.empty?

      glossary_entries.filter_map do |entry|
        next unless str.include?(entry.fetch("src"))

        entry
      end
    end

    def ntl_hits_for(text)
      str = text.to_s
      return [] if ntl_entries.empty? || str.empty?

      found = []

      ntl_entries.each do |entry|
        kind = entry.fetch(:kind)

        if kind == :regex
          str.enum_for(:scan, entry.fetch(:regex)).each do
            match = Regexp.last_match&.to_s
            found << match if match.present?
          end
          next
        end

        literal = entry.fetch(:text)
        found << literal if str.include?(literal)
      end

      uniq_preserve_order(found.map(&:to_s).reject(&:empty?))
    end

    def build_glossary_lines(hits)
      body = hits.map { |h| "- #{h.fetch("src")} => #{h.fetch("dst")}" }.join("\n")
      "Glossary (only when relevant):\n#{body}\n\n"
    end

    def build_ntl_lines(hits)
      body = hits.map { |h| "- #{h}" }.join("\n")
      "Do not translate (only when relevant):\n#{body}\n\n"
    end

    def parse_entries_json(json, context:)
      raw = json.to_s
      return [] if raw.blank?

      parsed = JSON.parse(raw)
      return parsed if parsed.is_a?(Array)

      warnings << "#{context} must be a JSON array"
      []
    rescue JSON::ParserError => e
      warnings << "#{context} JSON parse error: #{e.message}"
      []
    end

    def uniq_by(items, &block)
      seen = {}
      items.filter do |item|
        key = block.call(item)
        next false if seen.key?(key)

        seen[key] = true
        true
      end
    end

    def uniq_preserve_order(items)
      seen = {}
      items.filter do |item|
        next false if seen.key?(item)

        seen[item] = true
        true
      end
    end
  end
end
