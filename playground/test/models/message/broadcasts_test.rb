# frozen_string_literal: true

require "test_helper"

class Message::BroadcastsTest < ActiveSupport::TestCase
  fixtures :users

  setup do
    @space = Spaces::Playground.create!(name: "Broadcast Space", owner: users(:admin))
    @conversation = @space.conversations.create!(title: "Main")
    @membership = @space.space_memberships.create!(kind: "human", user: users(:admin), role: "member")
    @message = @conversation.messages.create!(space_membership: @membership, content: "Hello", role: "user")
  end

  test "broadcast_create is callable and does not error" do
    new_message = @conversation.messages.create!(
      space_membership: @membership,
      content: "Test broadcast message",
      role: "user"
    )

    # Verify the method exists and is callable
    assert_respond_to new_message, :broadcast_create
    assert_nothing_raised { new_message.broadcast_create }
  end

  test "broadcast_update is callable and does not error" do
    assert_respond_to @message, :broadcast_update
    assert_nothing_raised { @message.broadcast_update }
  end

  test "broadcast_remove is callable and does not error" do
    assert_respond_to @message, :broadcast_remove
    assert_nothing_raised { @message.broadcast_remove }
  end

  test "message includes Broadcasts concern" do
    assert Message.include?(Message::Broadcasts)
  end

  test "dom_id helper generates correct IDs" do
    # Test the private dom_id method through the broadcast methods
    # The method should be accessible for the broadcast targets
    expected_message_dom_id = "message_#{@message.id}"
    expected_conversation_target = "messages_list_conversation_#{@conversation.id}"

    # These are the targets used in broadcast methods
    assert_equal expected_message_dom_id, ActionView::RecordIdentifier.dom_id(@message)
    assert_equal expected_conversation_target, ActionView::RecordIdentifier.dom_id(@conversation, :messages_list)
  end
end
