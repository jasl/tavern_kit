# frozen_string_literal: true

require "test_helper"

class TextContentCleanupJobTest < ActiveJob::TestCase
  test "cleans up orphaned TextContent records" do
    orphan = TextContent.create!(
      content: "orphan",
      content_sha256: SecureRandom.hex(32),
      references_count: 0
    )
    active = TextContent.create!(
      content: "active",
      content_sha256: SecureRandom.hex(32),
      references_count: 1
    )

    TextContentCleanupJob.perform_now

    assert_nil TextContent.find_by(id: orphan.id)
    assert_not_nil TextContent.find_by(id: active.id)
  end

  test "accepts custom batch_size" do
    # Just verify it doesn't raise
    assert_nothing_raised do
      TextContentCleanupJob.perform_now(batch_size: 100)
    end
  end
end
