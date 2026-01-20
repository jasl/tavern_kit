# frozen_string_literal: true

require "test_helper"

class ConversationBranchTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Test User",
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    @character = Character.create!(
      name: "Test Character",
      spec_version: 2,
      status: "ready",
      data: { name: "Test Character", first_mes: "Hello!" }
    )

    @space = Spaces::Playground.create!(
      name: "Test Space",
      owner: @user
    )

    @membership = @space.space_memberships.create!(
      character: @character,
      user: @user
    )

    @conversation = @space.conversations.create!(
      title: "Root Conversation",
      kind: "root"
    )

    # Add some messages
    @msg1 = @conversation.messages.create!(
      space_membership: @membership,
      role: "assistant",
      content: "First message",
      seq: 1
    )

    @msg2 = @conversation.messages.create!(
      space_membership: @membership,
      role: "user",
      content: "Second message",
      seq: 2
    )

    @msg3 = @conversation.messages.create!(
      space_membership: @membership,
      role: "assistant",
      content: "Third message",
      seq: 3
    )
  end

  # --- create_branch! tests ---

  test "create_branch! creates a branch conversation" do
    result = @conversation.create_branch!(from_message: @msg2)

    assert result.success?
    assert result.conversation.persisted?
    assert_equal "branch", result.conversation.kind
    assert_equal @conversation, result.conversation.parent_conversation
    assert_equal @msg2, result.conversation.forked_from_message
  end

  test "create_branch! copies messages up to fork point" do
    result = @conversation.create_branch!(from_message: @msg2)

    branch = result.conversation
    assert_equal 2, branch.messages.count

    messages = branch.messages.ordered
    assert_equal "First message", messages[0].content
    assert_equal "Second message", messages[1].content
  end

  test "create_branch! uses custom title" do
    result = @conversation.create_branch!(from_message: @msg2, title: "My Branch")

    assert_equal "My Branch", result.conversation.title
  end

  test "create_branch! uses default title when not provided" do
    result = @conversation.create_branch!(from_message: @msg2)

    assert_equal "Branch", result.conversation.title
  end

  test "create_branch! sets visibility" do
    result = @conversation.create_branch!(from_message: @msg2, visibility: "private")

    assert result.conversation.private_conversation?
  end

  test "create_branch! sets root_conversation_id" do
    result = @conversation.create_branch!(from_message: @msg2)

    assert_equal @conversation.root_conversation_id, result.conversation.root_conversation_id
  end

  test "create_branch! fails for message not in conversation" do
    other_conversation = @space.conversations.create!(
      title: "Other",
      kind: "root"
    )
    other_msg = other_conversation.messages.create!(
      space_membership: @membership,
      role: "assistant",
      content: "Other",
      seq: 1
    )

    result = @conversation.create_branch!(from_message: other_msg)

    assert_not result.success?
    assert_match(/does not belong/, result.error)
  end

  test "create_branch! fails for non-playground spaces" do
    group_space = Spaces::Discussion.create!(
      name: "Discussion Space",
      owner: @user
    )

    group_conversation = group_space.conversations.create!(
      title: "Group Chat",
      kind: "root"
    )

    group_membership = group_space.space_memberships.create!(
      character: @character,
      user: @user
    )

    msg = group_conversation.messages.create!(
      space_membership: group_membership,
      role: "assistant",
      content: "Hello",
      seq: 1
    )

    result = group_conversation.create_branch!(from_message: msg)

    assert_not result.success?
    assert_match(/only allowed in Playground/, result.error)
  end

  # --- create_thread! tests ---

  test "create_thread! creates a thread conversation" do
    result = @conversation.create_thread!(from_message: @msg2)

    assert result.success?
    assert_equal "thread", result.conversation.kind
    assert_equal @conversation, result.conversation.parent_conversation
  end

  test "create_thread! works in non-playground spaces" do
    discussion_space = Spaces::Discussion.create!(
      name: "Discussion Space",
      owner: @user
    )

    discussion_conversation = discussion_space.conversations.create!(
      title: "Discussion Chat",
      kind: "root"
    )

    discussion_membership = discussion_space.space_memberships.create!(
      character: @character,
      user: @user
    )

    msg = discussion_conversation.messages.create!(
      space_membership: discussion_membership,
      role: "assistant",
      content: "Hello",
      seq: 1
    )

    result = discussion_conversation.create_thread!(from_message: msg)

    assert result.success?
    assert_equal "thread", result.conversation.kind
  end

  # --- create_checkpoint! tests ---

  test "create_checkpoint! creates a checkpoint conversation" do
    result = @conversation.create_checkpoint!(from_message: @msg2)

    assert result.success?
    assert_equal "checkpoint", result.conversation.kind
    assert_equal @conversation, result.conversation.parent_conversation
  end

  test "create_checkpoint! copies messages up to checkpoint" do
    result = @conversation.create_checkpoint!(from_message: @msg2)

    checkpoint = result.conversation
    assert_equal 2, checkpoint.messages.count
  end

  test "create_checkpoint! uses custom title" do
    result = @conversation.create_checkpoint!(from_message: @msg2, title: "Save Point 1")

    assert_equal "Save Point 1", result.conversation.title
  end

  # --- Message cloning tests ---

  test "branch copies message metadata" do
    @msg1.update!(metadata: { "custom" => "data" })

    result = @conversation.create_branch!(from_message: @msg1)

    branch_msg = result.conversation.messages.first
    assert_equal({ "custom" => "data" }, branch_msg.metadata)
  end

  test "branch copies message visibility" do
    @msg1.update!(visibility: "excluded")

    result = @conversation.create_branch!(from_message: @msg1)

    branch_msg = result.conversation.messages.first
    assert branch_msg.visibility_excluded?
  end

  test "branch sets origin_message_id to track source" do
    result = @conversation.create_branch!(from_message: @msg1)

    branch_msg = result.conversation.messages.first
    assert_equal @msg1.id, branch_msg.origin_message_id
  end

  test "branch copies message swipes" do
    # Add swipes to message
    swipe1 = @msg1.message_swipes.create!(position: 0, content: "Swipe 0")
    swipe2 = @msg1.message_swipes.create!(position: 1, content: "Swipe 1")
    @msg1.update!(active_message_swipe: swipe2, content: swipe2.content)

    result = @conversation.create_branch!(from_message: @msg1)

    branch_msg = result.conversation.messages.first
    assert_equal 2, branch_msg.message_swipes.count

    cloned_swipes = branch_msg.message_swipes.order(:position)
    assert_equal "Swipe 0", cloned_swipes[0].content
    assert_equal "Swipe 1", cloned_swipes[1].content

    # Active swipe should be preserved
    assert_not_nil branch_msg.active_message_swipe
    assert_equal "Swipe 1", branch_msg.active_message_swipe.content
    assert_equal "Swipe 1", branch_msg.content
  end
end
