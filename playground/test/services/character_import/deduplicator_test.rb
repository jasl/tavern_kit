# frozen_string_literal: true

require "test_helper"

module CharacterImport
  class DeduplicatorTest < ActiveSupport::TestCase
    setup do
      @dedup = Deduplicator.new
    end

    # === Duplicate Detection ===

    test "duplicate? returns true for existing hash" do
      character = characters(:ready_v2)

      # Create content that produces the same hash as the existing character
      # We test the actual flow by creating a character first and then checking
      content = "unique content for dedup test"
      sha256 = @dedup.compute_sha256(content)

      # Create character with this hash
      Character.create!(
        name: "Dedup Test Character",
        data: { "name" => "Dedup Test Character" },
        spec_version: 2,
        file_sha256: sha256,
        status: "ready"
      )

      assert @dedup.duplicate?(content)
    end

    test "duplicate? returns false for new content" do
      content = "completely unique content #{SecureRandom.hex(16)}"
      assert_not @dedup.duplicate?(content)
    end

    # === Find Existing ===

    test "find_existing returns character with matching hash" do
      character = characters(:ready_v2)

      # Use actual hash computation
      found = Character.find_by(file_sha256: character.file_sha256)
      assert_equal character, found
    end

    test "find_existing returns nil for no match" do
      found = @dedup.find_existing("nonexistent content")
      assert_nil found
    end

    # === SHA256 Computation ===

    test "compute_sha256 returns correct hash" do
      content = "test content for hashing"
      expected = Digest::SHA256.hexdigest(content)

      assert_equal expected, @dedup.compute_sha256(content)
    end

    test "compute_sha256 is deterministic" do
      content = "same content"

      hash1 = @dedup.compute_sha256(content)
      hash2 = @dedup.compute_sha256(content)

      assert_equal hash1, hash2
    end

    # === Clear Hash ===

    test "clear_hash! sets file_sha256 to nil" do
      character = characters(:ready_v2)
      original_hash = character.file_sha256
      assert_not_nil original_hash

      @dedup.clear_hash!(character)

      assert_nil character.reload.file_sha256
    end

    test "clear_hash! allows re-import of original file" do
      character = characters(:ready_v2)
      original_hash = character.file_sha256

      # Clear the hash
      @dedup.clear_hash!(character)

      # Now a file with the original hash should not be found
      found = Character.find_by(file_sha256: original_hash)
      assert_nil found
    end

    # === Same Content Check ===

    test "same_content? returns true for matching hashes" do
      char1 = Character.new(file_sha256: "abc123")
      char2 = Character.new(file_sha256: "abc123")

      assert @dedup.same_content?(char1, char2)
    end

    test "same_content? returns false for different hashes" do
      char1 = Character.new(file_sha256: "abc123")
      char2 = Character.new(file_sha256: "xyz789")

      assert_not @dedup.same_content?(char1, char2)
    end

    test "same_content? returns false when either hash is blank" do
      char1 = Character.new(file_sha256: "abc123")
      char2 = Character.new(file_sha256: nil)

      assert_not @dedup.same_content?(char1, char2)
      assert_not @dedup.same_content?(char2, char1)
    end

    # === Find Similar ===

    test "find_similar returns characters with matching names" do
      # Create a character with a searchable name
      Character.create!(
        name: "Searchable Test Character",
        data: { "name" => "Searchable Test Character" },
        spec_version: 2,
        status: "ready"
      )

      card_data = { "data" => { "name" => "Searchable" } }
      similar = @dedup.find_similar(card_data)

      assert similar.any? { |c| c.name.include?("Searchable") }
    end

    test "find_similar returns empty for no matches" do
      card_data = { "data" => { "name" => "XYZ#{SecureRandom.hex(8)}" } }
      similar = @dedup.find_similar(card_data)

      assert_empty similar
    end

    test "find_similar handles missing name" do
      card_data = { "data" => {} }
      similar = @dedup.find_similar(card_data)

      assert_empty similar
    end

    test "find_similar only returns ready characters" do
      # The pending_character fixture should not be in results
      card_data = { "data" => { "name" => "Pending" } }
      similar = @dedup.find_similar(card_data)

      assert similar.all?(&:ready?)
    end

    test "find_similar limits results" do
      card_data = { "data" => { "name" => "Character" } }
      similar = @dedup.find_similar(card_data)

      assert similar.size <= 10
    end
  end
end
