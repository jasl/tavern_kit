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

  test "find_or_create_for returns existing record for duplicate content" do
    content = "Duplicate content #{SecureRandom.hex(8)}"

    tc1 = TextContent.find_or_create_for(content)
    tc2 = TextContent.find_or_create_for(content)

    assert_equal tc1.id, tc2.id
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

  test "batch_decrement_references! updates multiple records" do
    tc1 = TextContent.create!(content: "test1", content_sha256: SecureRandom.hex(32), references_count: 3)
    tc2 = TextContent.create!(content: "test2", content_sha256: SecureRandom.hex(32), references_count: 4)

    TextContent.batch_decrement_references!([tc1.id, tc2.id])

    assert_equal 2, tc1.reload.references_count
    assert_equal 3, tc2.reload.references_count
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
end
