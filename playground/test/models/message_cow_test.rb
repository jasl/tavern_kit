# frozen_string_literal: true

require "test_helper"

class MessageCowTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(name: "COW Test Space", owner: @user)
    @space_membership = @space.space_memberships.create!(user: @user, kind: "human", participation: "active", status: "active")
    @conversation = @space.conversations.create!(title: "COW Test")
  end

  teardown do
    @space.destroy!
  end

  test "creating message creates TextContent record" do
    content = "Hello from COW test #{SecureRandom.hex(8)}"

    message = @conversation.messages.create!(
      space_membership: @space_membership,
      content: content,
      role: "user"
    )

    assert message.text_content.present?, "Message should have text_content"
    assert_equal content, message.text_content.content
    assert_equal content, message.content
    assert_equal 1, message.text_content.references_count
  end

  test "message content getter returns from text_content" do
    content = "Read from text_content #{SecureRandom.hex(8)}"
    message = @conversation.messages.create!(
      space_membership: @space_membership,
      content: content,
      role: "user"
    )

    # Verify content comes from text_content
    assert_equal content, message.content
    assert_equal message.text_content.content, message.content
  end

  test "editing non-shared content updates TextContent in place" do
    message = @conversation.messages.create!(
      space_membership: @space_membership,
      content: "Original content",
      role: "user"
    )

    original_tc_id = message.text_content_id
    assert_equal 1, message.text_content.references_count

    message.content = "Updated content"
    message.save!

    # Should update in place (same text_content_id)
    assert_equal original_tc_id, message.text_content_id
    assert_equal "Updated content", message.content
    assert_equal "Updated content", message.text_content.content
  end

  test "editing shared content creates new TextContent (COW)" do
    # Create first message
    message1 = @conversation.messages.create!(
      space_membership: @space_membership,
      content: "Shared content",
      role: "user"
    )

    # Simulate sharing by incrementing references
    original_tc = message1.text_content
    original_tc.increment_references! # Now references_count = 2

    # Edit the message
    message1.content = "Edited content"
    message1.save!

    # Should have created new TextContent
    assert_not_equal original_tc.id, message1.text_content_id
    assert_equal "Edited content", message1.content
    assert_equal "Edited content", message1.text_content.content

    # Original should still exist with decremented count
    original_tc.reload
    assert_equal "Shared content", original_tc.content
    assert_equal 1, original_tc.references_count
  end

  test "deleting message decrements TextContent references" do
    message = @conversation.messages.create!(
      space_membership: @space_membership,
      content: "To be deleted",
      role: "user"
    )

    tc = message.text_content
    tc.increment_references! # Simulate sharing, now = 2
    assert_equal 2, tc.reload.references_count

    message.destroy!

    assert_equal 1, tc.reload.references_count
  end

  test "MessageSwipe content uses COW" do
    message = @conversation.messages.create!(
      space_membership: @space_membership,
      content: "Message with swipe",
      role: "assistant"
    )

    swipe = message.message_swipes.create!(
      position: 0,
      content: "Swipe content"
    )

    assert swipe.text_content.present?
    assert_equal "Swipe content", swipe.content
    assert_equal 1, swipe.text_content.references_count
  end

  test "MessageSwipe editing with COW" do
    message = @conversation.messages.create!(
      space_membership: @space_membership,
      content: "Message",
      role: "assistant"
    )

    swipe = message.message_swipes.create!(position: 0, content: "Original swipe")
    original_tc = swipe.text_content
    original_tc.increment_references! # Simulate sharing

    swipe.content = "Edited swipe"
    swipe.save!

    assert_not_equal original_tc.id, swipe.text_content_id
    assert_equal "Edited swipe", swipe.content
    assert_equal 1, original_tc.reload.references_count
  end

  test "conversation delete decrements all text_content references" do
    # Create messages with content
    msg1 = @conversation.messages.create!(
      space_membership: @space_membership,
      content: "Message 1",
      role: "user"
    )
    msg2 = @conversation.messages.create!(
      space_membership: @space_membership,
      content: "Message 2",
      role: "assistant"
    )

    # Create swipe
    swipe = msg2.message_swipes.create!(position: 0, content: "Swipe content")

    tc1_id = msg1.text_content_id
    tc2_id = msg2.text_content_id
    tc_swipe_id = swipe.text_content_id

    # Simulate sharing (in real scenario these would be shared with forked messages)
    TextContent.where(id: [tc1_id, tc2_id, tc_swipe_id]).update_all(references_count: 2)

    # Delete conversation
    @conversation.destroy!

    # All references should be decremented
    assert_equal 1, TextContent.find(tc1_id).references_count
    assert_equal 1, TextContent.find(tc2_id).references_count
    assert_equal 1, TextContent.find(tc_swipe_id).references_count
  end
end
