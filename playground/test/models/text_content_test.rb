# frozen_string_literal: true

require "test_helper"

class TextContentTest < ActiveSupport::TestCase
  test "find_or_create_for creates new record for new content" do
    content = "Hello, world! #{SecureRandom.hex(8)}"

    tc = TextContent.find_or_create_for(content)

    assert tc.persisted?
    assert_equal content, tc.content
    assert_equal Digest::SHA256.hexdigest(content), tc.content_sha256
    assert_equal 1, tc.references_count
  end

  test "find_or_create_for returns existing record for duplicate content without incrementing" do
    content = "Duplicate content #{SecureRandom.hex(8)}"

    tc1 = TextContent.find_or_create_for(content)
    tc2 = TextContent.find_or_create_for(content)

    assert_equal tc1.id, tc2.id
    # NOTE: find_or_create_for does NOT increment - use find_or_create_with_reference! for that
    assert_equal 1, tc1.reload.references_count
  end

  test "find_or_create_with_reference! creates new record with references_count 1" do
    content = "New reference content #{SecureRandom.hex(8)}"

    tc = TextContent.find_or_create_with_reference!(content)

    assert tc.persisted?
    assert_equal content, tc.content
    assert_equal 1, tc.references_count
  end

  test "find_or_create_with_reference! increments existing record" do
    content = "Shared content #{SecureRandom.hex(8)}"

    tc1 = TextContent.find_or_create_with_reference!(content)
    assert_equal 1, tc1.references_count

    tc2 = TextContent.find_or_create_with_reference!(content)

    assert_equal tc1.id, tc2.id
    assert_equal 2, tc1.reload.references_count
  end

  test "find_or_create_with_reference! returns nil for nil content" do
    assert_nil TextContent.find_or_create_with_reference!(nil)
  end

  test "find_or_create_for returns nil for nil content" do
    assert_nil TextContent.find_or_create_for(nil)
  end

  test "find_for returns existing record" do
    content = "Find me #{SecureRandom.hex(8)}"
    tc = TextContent.find_or_create_for(content)

    found = TextContent.find_for(content)

    assert_equal tc.id, found.id
  end

  test "find_for returns nil for non-existent content" do
    assert_nil TextContent.find_for("non-existent-#{SecureRandom.hex(16)}")
  end

  test "shared? returns true when references_count > 1" do
    tc = TextContent.create!(content: "test", content_sha256: SecureRandom.hex(32), references_count: 2)
    assert tc.shared?
  end

  test "shared? returns false when references_count = 1" do
    tc = TextContent.create!(content: "test", content_sha256: SecureRandom.hex(32), references_count: 1)
    refute tc.shared?
  end

  # --- update_if_not_shared! (TOCTOU race condition prevention) ---

  test "update_if_not_shared! succeeds when references_count = 1" do
    tc = TextContent.create!(content: "original", content_sha256: SecureRandom.hex(32), references_count: 1)
    new_content = "updated content"
    new_sha256 = Digest::SHA256.hexdigest(new_content)

    result = tc.update_if_not_shared!(new_content, new_sha256)

    assert result
    assert_equal new_content, tc.content
    assert_equal new_sha256, tc.content_sha256
    assert_equal 1, tc.references_count
  end

  test "update_if_not_shared! fails when references_count > 1" do
    original_content = "original"
    original_sha256 = SecureRandom.hex(32)
    tc = TextContent.create!(content: original_content, content_sha256: original_sha256, references_count: 2)
    new_content = "updated content"
    new_sha256 = Digest::SHA256.hexdigest(new_content)

    result = tc.update_if_not_shared!(new_content, new_sha256)

    refute result
    # Content should NOT be updated
    assert_equal original_content, tc.reload.content
    assert_equal original_sha256, tc.content_sha256
    assert_equal 2, tc.references_count
  end

  test "update_if_not_shared! prevents TOCTOU race when concurrent fork increments references" do
    # Simulate race condition:
    # 1. Edit checks shared? → false (references_count = 1)
    # 2. Fork increments references_count → 2
    # 3. Edit tries atomic update → fails because references_count != 1

    tc = TextContent.create!(content: "original", content_sha256: SecureRandom.hex(32), references_count: 1)

    # Simulate step 2: another process (fork) increments references
    TextContent.where(id: tc.id).update_all("references_count = references_count + 1")

    # Step 3: atomic update should fail
    new_content = "race condition content"
    new_sha256 = Digest::SHA256.hexdigest(new_content)
    result = tc.update_if_not_shared!(new_content, new_sha256)

    refute result, "Atomic update should fail when references_count changed"
    assert_equal "original", tc.reload.content, "Original content should be preserved"
    assert_equal 2, tc.references_count, "References count should be 2 from the concurrent fork"
  end

  test "increment_references! increases count atomically" do
    tc = TextContent.create!(content: "test", content_sha256: SecureRandom.hex(32), references_count: 1)

    tc.increment_references!

    assert_equal 2, tc.references_count
  end

  test "decrement_references! decreases count atomically" do
    tc = TextContent.create!(content: "test", content_sha256: SecureRandom.hex(32), references_count: 3)

    tc.decrement_references!

    assert_equal 2, tc.references_count
  end

  test "batch_increment_references! updates multiple records" do
    tc1 = TextContent.create!(content: "test1", content_sha256: SecureRandom.hex(32), references_count: 1)
    tc2 = TextContent.create!(content: "test2", content_sha256: SecureRandom.hex(32), references_count: 2)

    TextContent.batch_increment_references!([tc1.id, tc2.id])

    assert_equal 2, tc1.reload.references_count
    assert_equal 3, tc2.reload.references_count
  end

  test "batch_increment_references! handles duplicate IDs correctly via tally" do
    tc = TextContent.create!(content: "shared", content_sha256: SecureRandom.hex(32), references_count: 1)

    # Simulate forking 3 messages that all share the same content
    TextContent.batch_increment_references!([tc.id, tc.id, tc.id])

    assert_equal 4, tc.reload.references_count
  end

  test "batch_decrement_references! updates multiple records" do
    tc1 = TextContent.create!(content: "test1", content_sha256: SecureRandom.hex(32), references_count: 3)
    tc2 = TextContent.create!(content: "test2", content_sha256: SecureRandom.hex(32), references_count: 4)

    TextContent.batch_decrement_references!([tc1.id, tc2.id])

    assert_equal 2, tc1.reload.references_count
    assert_equal 3, tc2.reload.references_count
  end

  test "batch_decrement_references! handles duplicate IDs correctly via tally" do
    tc = TextContent.create!(content: "shared", content_sha256: SecureRandom.hex(32), references_count: 5)

    # Simulate deleting 3 messages that all shared the same content
    TextContent.batch_decrement_references!([tc.id, tc.id, tc.id])

    assert_equal 2, tc.reload.references_count
  end

  test "validates presence of content" do
    tc = TextContent.new(content: nil, content_sha256: "abc123")
    refute tc.valid?
    assert_includes tc.errors[:content], "can't be blank"
  end

  test "validates uniqueness of content_sha256" do
    sha = SecureRandom.hex(32)
    TextContent.create!(content: "first", content_sha256: sha)

    tc = TextContent.new(content: "second", content_sha256: sha)
    refute tc.valid?
    assert_includes tc.errors[:content_sha256], "has already been taken"
  end

  test "computes sha256 before validation on create" do
    tc = TextContent.new(content: "auto hash me")
    tc.valid?

    assert_equal Digest::SHA256.hexdigest("auto hash me"), tc.content_sha256
  end

  # --- Cleanup tests ---

  test "cleanup_orphans! deletes records with references_count = 0" do
    orphan = TextContent.create!(content: "orphan", content_sha256: SecureRandom.hex(32), references_count: 0)
    active = TextContent.create!(content: "active", content_sha256: SecureRandom.hex(32), references_count: 1)

    deleted = TextContent.cleanup_orphans!

    assert_operator deleted, :>=, 1
    assert_nil TextContent.find_by(id: orphan.id)
    assert_not_nil TextContent.find_by(id: active.id)
  end

  test "cleanup_orphans! deletes records with negative references_count" do
    negative = TextContent.create!(content: "negative", content_sha256: SecureRandom.hex(32), references_count: -2)
    active = TextContent.create!(content: "active", content_sha256: SecureRandom.hex(32), references_count: 1)

    deleted = TextContent.cleanup_orphans!

    assert_operator deleted, :>=, 1
    assert_nil TextContent.find_by(id: negative.id)
    assert_not_nil TextContent.find_by(id: active.id)
  end

  test "cleanup_orphans! handles large batches" do
    # Create 5 orphans
    orphan_ids =
      5.times.map do |i|
        TextContent.create!(content: "orphan #{i}", content_sha256: SecureRandom.hex(32), references_count: 0).id
      end
    active = TextContent.create!(content: "active", content_sha256: SecureRandom.hex(32), references_count: 1)

    # Delete with small batch size to test looping
    deleted = TextContent.cleanup_orphans!(batch_size: 2)

    assert_operator deleted, :>=, 5
    orphan_ids.each do |id|
      assert_nil TextContent.find_by(id: id)
    end
    assert_not_nil TextContent.find_by(id: active.id)
  end

  test "orphan_count returns count of orphaned records" do
    baseline = TextContent.orphan_count

    TextContent.create!(content: "orphan1", content_sha256: SecureRandom.hex(32), references_count: 0)
    TextContent.create!(content: "orphan2", content_sha256: SecureRandom.hex(32), references_count: -1)
    TextContent.create!(content: "active", content_sha256: SecureRandom.hex(32), references_count: 1)

    assert_equal baseline + 2, TextContent.orphan_count
  end
end
