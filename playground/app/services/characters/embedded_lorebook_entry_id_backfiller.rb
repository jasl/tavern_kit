# frozen_string_literal: true

module Characters
  # Backfill missing/duplicate embedded lorebook entry IDs on a character.
  #
  # Embedded lorebook entries are stored in the character card JSON under:
  #   data.character_book.entries[]
  #
  # Some imported cards omit the optional `id` field. The UI and controllers
  # assume IDs exist for routing, DOM IDs, and reordering.
  #
  # This service assigns a UUID to any entry with a blank ID, and also repairs
  # duplicate IDs by reassigning later duplicates.
  class EmbeddedLorebookEntryIdBackfiller
    def initialize(character)
      @character = character
    end

    # @return [Boolean] true if the character was updated
    def call
      data = @character.data&.to_h&.deep_symbolize_keys || {}
      book = data[:character_book]
      book = book.to_h.deep_symbolize_keys if book.respond_to?(:to_h)
      return false unless book.is_a?(Hash)

      entries = Array(book[:entries]).map { |e| normalize_entry(e) }
      return false if entries.empty?

      seen = {}
      changed = false

      entries = entries.map do |entry|
        id = entry[:id].to_s

        if id.blank? || seen.key?(id)
          id = next_unique_id(seen)
          entry = entry.merge(id: id)
          changed = true
        end

        seen[id] = true
        entry
      end

      return false unless changed

      book[:entries] = entries
      data[:character_book] = book

      @character.update!(data: data)

      true
    end

    private

    def normalize_entry(entry)
      if entry.is_a?(Hash)
        entry.deep_symbolize_keys
      elsif entry.respond_to?(:to_h)
        entry.to_h.deep_symbolize_keys
      else
        {}
      end
    end

    def next_unique_id(seen)
      loop do
        candidate = SecureRandom.uuid
        return candidate unless seen.key?(candidate)
      end
    end
  end
end
