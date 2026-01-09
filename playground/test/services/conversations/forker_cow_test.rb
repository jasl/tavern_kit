# frozen_string_literal: true

require "test_helper"

class Conversations::ForkerCowTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(name: "Fork COW Test", owner: @user)
    @user_membership = @space.space_memberships.create!(
      user: @user,
      kind: "human",
      participation: "active",
      status: "active"
    )
    @conversation = @space.conversations.create!(title: "Parent Conversation")
  end

  teardown do
    @space.destroy!
  end

  test "fork reuses text_content_id for messages (COW)" do
    # Create parent messages
    msg1 = @conversation.messages.create!(
      space_membership: @user_membership,
      content: "Message 1",
      role: "user"
    )
    msg2 = @conversation.messages.create!(
      space_membership: @user_membership,
      content: "Message 2",
      role: "user"
    )

    original_tc_ids = [msg1.text_content_id, msg2.text_content_id]

    # Fork
    result = @conversation.create_branch!(from_message: msg2, title: "Fork", async: false)

    assert result.success?
    forked_conv = result.conversation

    # Forked messages should reuse text_content_ids
    forked_messages = forked_conv.messages.order(:seq)
    assert_equal 2, forked_messages.count

    forked_tc_ids = forked_messages.pluck(:text_content_id)
    assert_equal original_tc_ids.sort, forked_tc_ids.sort

    # References should be incremented
    msg1.text_content.reload
    msg2.text_content.reload
    assert_equal 2, msg1.text_content.references_count
    assert_equal 2, msg2.text_content.references_count
  end

  test "fork reuses text_content_id for swipes (COW)" do
    msg = @conversation.messages.create!(
      space_membership: @user_membership,
      content: "Message with swipes",
      role: "assistant"
    )

    swipe1 = msg.message_swipes.create!(position: 0, content: "Swipe 1")
    swipe2 = msg.message_swipes.create!(position: 1, content: "Swipe 2")
    msg.update!(active_message_swipe: swipe1)

    original_swipe_tc_ids = [swipe1.text_content_id, swipe2.text_content_id]

    # Fork
    result = @conversation.create_branch!(from_message: msg, title: "Fork", async: false)

    assert result.success?
    forked_conv = result.conversation

    # Check forked swipes reuse text_content_ids
    forked_msg = forked_conv.messages.first
    forked_swipes = forked_msg.message_swipes.order(:position)
    assert_equal 2, forked_swipes.count

    forked_swipe_tc_ids = forked_swipes.pluck(:text_content_id)
    assert_equal original_swipe_tc_ids.sort, forked_swipe_tc_ids.sort

    # References should be incremented
    swipe1.text_content.reload
    swipe2.text_content.reload
    assert_equal 2, swipe1.text_content.references_count
    assert_equal 2, swipe2.text_content.references_count
  end

  test "editing forked message creates new TextContent (COW in action)" do
    # Create parent message
    parent_msg = @conversation.messages.create!(
      space_membership: @user_membership,
      content: "Original content",
      role: "user"
    )

    original_tc_id = parent_msg.text_content_id

    # Fork
    result = @conversation.create_branch!(from_message: parent_msg, title: "Fork", async: false)
    forked_conv = result.conversation
    forked_msg = forked_conv.messages.first

    # Both should share same text_content
    assert_equal original_tc_id, forked_msg.text_content_id
    assert_equal 2, TextContent.find(original_tc_id).references_count

    # Edit forked message - should trigger COW
    forked_msg.content = "Edited in fork"
    forked_msg.save!

    # Forked message should have new text_content
    assert_not_equal original_tc_id, forked_msg.text_content_id
    assert_equal "Edited in fork", forked_msg.content

    # Original text_content should have decremented references
    assert_equal 1, TextContent.find(original_tc_id).references_count

    # Parent message should still have original content
    assert_equal "Original content", parent_msg.reload.content
  end

  test "deleting forked conversation decrements text_content references" do
    # Create parent messages
    msg1 = @conversation.messages.create!(
      space_membership: @user_membership,
      content: "Message 1",
      role: "user"
    )
    msg2 = @conversation.messages.create!(
      space_membership: @user_membership,
      content: "Message 2",
      role: "user"
    )

    # Fork
    result = @conversation.create_branch!(from_message: msg2, title: "Fork", async: false)
    forked_conv = result.conversation

    # References should be 2
    assert_equal 2, msg1.text_content.reload.references_count
    assert_equal 2, msg2.text_content.reload.references_count

    # Delete forked conversation
    forked_conv.destroy!

    # References should be back to 1
    assert_equal 1, msg1.text_content.reload.references_count
    assert_equal 1, msg2.text_content.reload.references_count
  end

  test "batch insert performance with many messages" do
    # Create 100 messages
    100.times do |i|
      @conversation.messages.create!(
        space_membership: @user_membership,
        content: "Message #{i} with some content " * 10,
        role: i.even? ? "user" : "assistant"
      )
    end

    fork_message = @conversation.messages.order(:seq).last

    # Measure fork time
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = @conversation.create_branch!(from_message: fork_message, title: "Performance Fork", async: false)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    assert result.success?
    assert_equal 100, result.conversation.messages.count

    # Should be fast (< 1 second for 100 messages)
    assert elapsed < 1.0, "Fork of 100 messages took #{elapsed}s, expected < 1s"
  end

  test "fork preserves active_message_swipe pointer" do
    msg = @conversation.messages.create!(
      space_membership: @user_membership,
      content: "Message with swipes",
      role: "assistant"
    )

    swipe1 = msg.message_swipes.create!(position: 0, content: "Swipe 1")
    swipe2 = msg.message_swipes.create!(position: 1, content: "Swipe 2")
    msg.update!(active_message_swipe: swipe2) # Set position 1 as active

    # Fork
    result = @conversation.create_branch!(from_message: msg, title: "Fork", async: false)
    # Reload to get the updated active_message_swipe_id from database
    forked_msg = result.conversation.messages.first.reload

    # Active swipe should be at same position
    assert forked_msg.active_message_swipe.present?
    assert_equal 1, forked_msg.active_message_swipe.position
    assert_equal "Swipe 2", forked_msg.active_message_swipe.content
  end

  test "fork copies attachments with blob reuse" do
    msg = @conversation.messages.create!(
      space_membership: @user_membership,
      content: "Message with attachment",
      role: "user"
    )

    # Create attachment
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("test image"),
      filename: "test.png",
      content_type: "image/png"
    )
    attachment = msg.message_attachments.create!(blob: blob, name: "screenshot", kind: "image")

    # Fork
    result = @conversation.create_branch!(from_message: msg, title: "Fork", async: false)
    forked_msg = result.conversation.messages.first

    # Attachment should be copied
    assert_equal 1, forked_msg.message_attachments.count

    forked_attachment = forked_msg.message_attachments.first
    assert_equal "screenshot", forked_attachment.name
    assert_equal "image", forked_attachment.kind

    # Blob should be reused (same blob_id)
    assert_equal attachment.blob_id, forked_attachment.blob_id
  end

  test "fork copies multiple attachments" do
    msg = @conversation.messages.create!(
      space_membership: @user_membership,
      content: "Message with attachments",
      role: "user"
    )

    # Create multiple attachments
    blob1 = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("img1"), filename: "1.png", content_type: "image/png")
    blob2 = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("img2"), filename: "2.png", content_type: "image/png")

    msg.message_attachments.create!(blob: blob1, name: "first", kind: "image", position: 0)
    msg.message_attachments.create!(blob: blob2, name: "second", kind: "image", position: 1)

    # Fork
    result = @conversation.create_branch!(from_message: msg, title: "Fork", async: false)
    forked_msg = result.conversation.messages.first

    # Both attachments should be copied
    assert_equal 2, forked_msg.message_attachments.count

    names = forked_msg.message_attachments.order(:position).pluck(:name)
    assert_equal %w[first second], names
  end
end
