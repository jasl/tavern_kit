# frozen_string_literal: true

module CharacterImport
  # Handles deduplication logic for character imports.
  #
  # Uses SHA256 hashing of the original file content to detect
  # duplicate imports. This allows the same character to be
  # re-imported after editing (which clears the hash).
  #
  # @example Check for duplicate
  #   dedup = Deduplicator.new
  #   if dedup.duplicate?(file_content)
  #     existing = dedup.find_existing(file_content)
  #   end
  #
  class Deduplicator
    # Check if content has already been imported.
    #
    # @param content [String] file content
    # @return [Boolean]
    def duplicate?(content)
      find_existing(content).present?
    end

    # Find existing character with matching content hash.
    #
    # @param content [String] binary content
    # @return [Character, nil]
    def find_existing(content)
      sha256 = compute_sha256(content)
      Character.find_by(file_sha256: sha256)
    end

    # Compute SHA256 hash of content.
    #
    # @param content [String] binary content
    # @return [String] hex-encoded SHA256
    def compute_sha256(content)
      Digest::SHA256.hexdigest(content)
    end

    # Clear the file hash for a character (allow re-import of original).
    #
    # Called when a character is edited, allowing the original file
    # to be imported as a new character.
    #
    # @param character [Character] the character
    # @return [Boolean]
    def clear_hash!(character)
      character.update!(file_sha256: nil)
    end

    # Check if two characters have the same content.
    #
    # @param char1 [Character] first character
    # @param char2 [Character] second character
    # @return [Boolean]
    def same_content?(char1, char2)
      return false if char1.file_sha256.blank? || char2.file_sha256.blank?

      char1.file_sha256 == char2.file_sha256
    end

    # Find all characters that might be duplicates of a new import.
    #
    # Uses fuzzy matching on name and other attributes.
    #
    # @param card_data [Hash] parsed card data
    # @return [Array<Character>]
    def find_similar(card_data)
      name = card_data.dig("data", "name")
      return [] if name.blank?

      Character
        .ready
        .where("name LIKE ?", "%#{sanitize_for_like(name)}%")
        .limit(10)
    end

    private

    # Sanitize string for LIKE query.
    #
    # @param str [String]
    # @return [String]
    def sanitize_for_like(str)
      str.to_s.gsub(/[%_\\]/) { |m| "\\#{m}" }
    end
  end
end
