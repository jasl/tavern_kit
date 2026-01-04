# frozen_string_literal: true

require "test_helper"

class ConversationChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = users(:admin)
    @conversation = conversations(:general_main)
    @membership = space_memberships(:admin_in_general)

    stub_connection current_user: @user
  end

  # ============================================================================
  # Subscription tests
  # ============================================================================

  test "subscribes to conversation when user is a participant" do
    subscribe conversation_id: @conversation.id

    assert subscription.confirmed?
    assert_has_stream_for @conversation
  end

  test "rejects subscription when user is not a participant" do
    other_user = users(:member)
    other_conversation = conversations(:archived_main)

    stub_connection current_user: other_user

    subscribe conversation_id: other_conversation.id

    assert subscription.rejected?
  end

  test "rejects subscription for non-existent conversation" do
    subscribe conversation_id: 999_999

    assert subscription.rejected?
  end

  test "rejects subscription without conversation_id" do
    subscribe

    assert subscription.rejected?
  end

  # ============================================================================
  # Broadcast method tests
  # ============================================================================

  test "broadcast_typing broadcasts typing_start event with styling info" do
    assert_broadcasts(@conversation, 1) do
      ConversationChannel.broadcast_typing(@conversation, membership: @membership, active: true)
    end

    data = last_broadcast_for(@conversation)
    assert_equal "typing_start", data[:type]
    assert_equal @membership.id, data[:space_membership_id]
    assert_equal @membership.display_name, data[:name]
    assert_equal @membership.user?, data[:is_user]
    assert_includes data[:avatar_url], "/portraits/space_memberships/"
    assert_includes %w[chat-bubble-accent chat-bubble-secondary], data[:bubble_class]
  end

  test "broadcast_typing broadcasts typing_stop event with styling info" do
    assert_broadcasts(@conversation, 1) do
      ConversationChannel.broadcast_typing(@conversation, membership: @membership, active: false)
    end

    data = last_broadcast_for(@conversation)
    assert_equal "typing_stop", data[:type]
    assert_equal @membership.id, data[:space_membership_id]
    assert_equal @membership.display_name, data[:name]
    assert_equal @membership.user?, data[:is_user]
    assert_includes data[:avatar_url], "/portraits/space_memberships/"
    assert_includes %w[chat-bubble-accent chat-bubble-secondary], data[:bubble_class]
  end

  test "broadcast_typing uses correct bubble_class for user participant" do
    assert @membership.user?

    ConversationChannel.broadcast_typing(@conversation, membership: @membership, active: true)
    data = last_broadcast_for(@conversation)

    assert_equal "chat-bubble-accent", data[:bubble_class]
  end

  test "broadcast_typing uses correct bubble_class for ai character participant" do
    ai_membership = space_memberships(:character_in_general)
    assert ai_membership.ai_character?
    assert_not ai_membership.user?

    ConversationChannel.broadcast_typing(@conversation, membership: ai_membership, active: true)
    data = last_broadcast_for(@conversation)

    assert_equal "chat-bubble-secondary", data[:bubble_class]
  end

  test "broadcast_stream_chunk broadcasts chunk content" do
    assert_broadcasts(@conversation, 1) do
      ConversationChannel.broadcast_stream_chunk(@conversation, content: "Hello world", space_membership_id: @membership.id)
    end

    data = last_broadcast_for(@conversation)
    assert_equal "stream_chunk", data[:type]
    assert_equal "Hello world", data[:content]
    assert_equal @membership.id, data[:space_membership_id]
  end

  test "broadcast_stream_complete broadcasts completion signal" do
    assert_broadcasts(@conversation, 1) do
      ConversationChannel.broadcast_stream_complete(@conversation, space_membership_id: @membership.id)
    end

    data = last_broadcast_for(@conversation)
    assert_equal "stream_complete", data[:type]
    assert_equal @membership.id, data[:space_membership_id]
  end

  private

  def last_broadcast_for(conversation)
    # Broadcasts are stored as JSON strings, decode and symbolize keys
    broadcasts = ActionCable.server.pubsub.broadcasts(ConversationChannel.broadcasting_for(conversation))
    return {} if broadcasts.empty?

    JSON.parse(broadcasts.last, symbolize_names: true)
  end
end
