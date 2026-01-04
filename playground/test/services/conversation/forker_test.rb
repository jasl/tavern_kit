# frozen_string_literal: true

require "test_helper"

class Conversation::ForkerTest < ActiveSupport::TestCase
  fixtures :users, :spaces, :space_memberships, :conversations, :messages, :characters, :llm_providers

  setup do
    @space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    @user_membership = @space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    @character_membership = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v2),
      llm_provider: llm_providers(:openai)
    )

    @conversation = @space.conversations.create!(title: "Main", kind: "root")

    # Create messages with swipes
    @msg1 = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Hello"
    )

    @msg2 = @conversation.messages.create!(
      space_membership: @character_membership,
      role: "assistant",
      content: "Hi there!"
    )
    # Add swipes to msg2
    @swipe1 = @msg2.message_swipes.create!(position: 0, content: "Hi there!")
    @swipe2 = @msg2.message_swipes.create!(position: 1, content: "Hello! How can I help?")
    @msg2.update!(active_message_swipe: @swipe1)

    @msg3 = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "How are you?"
    )

    @msg4 = @conversation.messages.create!(
      space_membership: @character_membership,
      role: "assistant",
      content: "I'm doing great!"
    )
  end

  # --- Tree Structure Tests ---

  test "branch creates correct tree structure with parent, root, and forked_from_message" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg2,
      kind: "branch"
    ).call

    assert result.success?
    branch = result.conversation

    assert_equal @conversation.id, branch.parent_conversation_id
    assert_equal @conversation.root_conversation_id, branch.root_conversation_id
    assert_equal @msg2.id, branch.forked_from_message_id
    assert_equal "branch", branch.kind
  end

  test "branch title defaults to 'Branch' when not provided" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg2,
      kind: "branch"
    ).call

    assert result.success?
    assert_equal "Branch", result.conversation.title
  end

  test "branch uses provided title" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg2,
      kind: "branch",
      title: "My Custom Branch"
    ).call

    assert result.success?
    assert_equal "My Custom Branch", result.conversation.title
  end

  # --- Message Cloning Tests ---

  test "branch clones messages up to and including fork_from_message" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg2,
      kind: "branch"
    ).call

    assert result.success?
    branch = result.conversation

    # Should have cloned msg1 and msg2 (seq 1 and 2), not msg3 and msg4
    assert_equal 2, branch.messages.count
    assert_equal [1, 2], branch.messages.ordered.pluck(:seq)
  end

  test "cloned messages preserve seq order" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg4,
      kind: "branch"
    ).call

    assert result.success?
    branch = result.conversation

    assert_equal 4, branch.messages.count
    assert_equal [1, 2, 3, 4], branch.messages.ordered.pluck(:seq)
  end

  test "cloned messages preserve role and content" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg2,
      kind: "branch"
    ).call

    assert result.success?
    branch = result.conversation

    cloned_msg1 = branch.messages.find_by(seq: 1)
    cloned_msg2 = branch.messages.find_by(seq: 2)

    assert_equal "user", cloned_msg1.role
    assert_equal "Hello", cloned_msg1.content
    assert_equal @user_membership.id, cloned_msg1.space_membership_id

    assert_equal "assistant", cloned_msg2.role
    assert_equal "Hi there!", cloned_msg2.content
    assert_equal @character_membership.id, cloned_msg2.space_membership_id
  end

  test "cloned messages have origin_message_id set correctly" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg2,
      kind: "branch"
    ).call

    assert result.success?
    branch = result.conversation

    cloned_msg1 = branch.messages.find_by(seq: 1)
    cloned_msg2 = branch.messages.find_by(seq: 2)

    assert_equal @msg1.id, cloned_msg1.origin_message_id
    assert_equal @msg2.id, cloned_msg2.origin_message_id
  end

  # --- Swipe Cloning Tests ---

  test "clones all swipes for messages" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg2,
      kind: "branch"
    ).call

    assert result.success?
    branch = result.conversation

    cloned_msg2 = branch.messages.find_by(seq: 2)
    assert_equal 2, cloned_msg2.message_swipes.count

    positions = cloned_msg2.message_swipes.pluck(:position).sort
    assert_equal [0, 1], positions
  end

  test "cloned swipes preserve content and position" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg2,
      kind: "branch"
    ).call

    assert result.success?
    branch = result.conversation

    cloned_msg2 = branch.messages.find_by(seq: 2)
    cloned_swipe1 = cloned_msg2.message_swipes.find_by(position: 0)
    cloned_swipe2 = cloned_msg2.message_swipes.find_by(position: 1)

    assert_equal "Hi there!", cloned_swipe1.content
    assert_equal "Hello! How can I help?", cloned_swipe2.content
  end

  test "active_message_swipe_id points to correct cloned swipe" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg2,
      kind: "branch"
    ).call

    assert result.success?
    branch = result.conversation

    cloned_msg2 = branch.messages.find_by(seq: 2)
    assert_not_nil cloned_msg2.active_message_swipe
    assert_equal 0, cloned_msg2.active_message_swipe.position
    assert_equal "Hi there!", cloned_msg2.active_message_swipe.content
  end

  test "message_swipes_count is correct after cloning" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg2,
      kind: "branch"
    ).call

    assert result.success?
    branch = result.conversation

    cloned_msg2 = branch.messages.find_by(seq: 2)
    assert_equal 2, cloned_msg2.message_swipes_count
  end

  # --- Visibility Tests ---

  test "branch defaults to shared visibility" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg2,
      kind: "branch"
    ).call

    assert result.success?
    assert_equal "shared", result.conversation.visibility
  end

  test "branch respects provided visibility" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg2,
      kind: "branch",
      visibility: "private"
    ).call

    assert result.success?
    assert_equal "private", result.conversation.visibility
  end

  # --- Validation Tests ---

  test "branch fails for Discussion spaces" do
    discussion_space = Spaces::Discussion.create!(name: "Discussion", owner: users(:admin))
    user_membership = discussion_space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    conversation = discussion_space.conversations.create!(title: "Main", kind: "root")
    message = conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Hello"
    )

    result = Conversation::Forker.new(
      parent_conversation: conversation,
      fork_from_message: message,
      kind: "branch"
    ).call

    assert_not result.success?
    assert_equal "Branching is only allowed in Playground spaces", result.error
  end

  test "thread is allowed in Discussion spaces" do
    discussion_space = Spaces::Discussion.create!(name: "Discussion", owner: users(:admin))
    user_membership = discussion_space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    conversation = discussion_space.conversations.create!(title: "Main", kind: "root")
    message = conversation.messages.create!(
      space_membership: user_membership,
      role: "user",
      content: "Hello"
    )

    result = Conversation::Forker.new(
      parent_conversation: conversation,
      fork_from_message: message,
      kind: "thread"
    ).call

    assert result.success?
    assert_equal "thread", result.conversation.kind
  end

  test "fails when message does not belong to conversation" do
    other_conversation = @space.conversations.create!(title: "Other", kind: "root")
    other_message = other_conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Different conversation"
    )

    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: other_message,
      kind: "branch"
    ).call

    assert_not result.success?
    assert_equal "Message does not belong to the parent conversation", result.error
  end

  # --- Edge Cases ---

  test "branch from first message clones only one message" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg1,
      kind: "branch"
    ).call

    assert result.success?
    branch = result.conversation

    assert_equal 1, branch.messages.count
    assert_equal "Hello", branch.messages.first.content
  end

  test "branch from last message clones all messages" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg4,
      kind: "branch"
    ).call

    assert result.success?
    branch = result.conversation

    assert_equal 4, branch.messages.count
  end

  test "message without swipes is cloned correctly" do
    result = Conversation::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: @msg1,
      kind: "branch"
    ).call

    assert result.success?
    branch = result.conversation

    cloned_msg = branch.messages.first
    assert_equal 0, cloned_msg.message_swipes.count
    assert_nil cloned_msg.active_message_swipe
  end
end
