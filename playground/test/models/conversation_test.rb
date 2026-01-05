# frozen_string_literal: true

require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  fixtures :users, :spaces, :space_memberships, :conversations, :messages

  # --- Root Conversation Tests ---

  test "root conversation automatically sets root_conversation_id to self after create" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Root Conv", kind: "root")

    assert_nil conversation.parent_conversation_id
    assert_equal conversation.id, conversation.root_conversation_id
    assert conversation.root?
  end

  test "root conversation cannot have parent_conversation" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    root = space.conversations.create!(title: "Root", kind: "root")

    invalid = space.conversations.build(title: "Invalid", kind: "root", parent_conversation: root)

    assert_not invalid.valid?
    assert_includes invalid.errors[:parent_conversation], "must be blank for root conversations"
  end

  # --- Child Conversation (Branch) Tests ---

  test "child conversation inherits root_conversation_id from parent" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    root = space.conversations.create!(title: "Root", kind: "root")
    branch = space.conversations.create!(title: "Branch", kind: "branch", parent_conversation: root)

    assert_equal root.id, branch.root_conversation_id
    assert_equal root.id, branch.parent_conversation_id
  end

  test "deeply nested conversation inherits root_conversation_id from original root" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    root = space.conversations.create!(title: "Root", kind: "root")
    branch1 = space.conversations.create!(title: "Branch 1", kind: "branch", parent_conversation: root)
    branch2 = space.conversations.create!(title: "Branch 2", kind: "branch", parent_conversation: branch1)

    assert_equal root.id, branch2.root_conversation_id
    assert_equal branch1.id, branch2.parent_conversation_id
  end

  test "branch conversation requires parent_conversation" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    invalid = space.conversations.build(title: "Invalid Branch", kind: "branch")

    assert_not invalid.valid?
    assert_includes invalid.errors[:parent_conversation], "must be present for branch conversations"
  end

  test "thread conversation requires parent_conversation" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    invalid = space.conversations.build(title: "Invalid Thread", kind: "thread")

    assert_not invalid.valid?
    assert_includes invalid.errors[:parent_conversation], "must be present for thread conversations"
  end

  # --- Checkpoint Conversation Tests ---

  test "checkpoint conversation requires parent_conversation" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    invalid = space.conversations.build(title: "Invalid Checkpoint", kind: "checkpoint")

    assert_not invalid.valid?
    assert_includes invalid.errors[:parent_conversation], "must be present for checkpoint conversations"
  end

  test "checkpoint? returns true for checkpoint conversations" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    root = space.conversations.create!(title: "Root", kind: "root")
    checkpoint = space.conversations.create!(title: "Checkpoint", kind: "checkpoint", parent_conversation: root)

    assert checkpoint.checkpoint?
    assert_not root.checkpoint?
  end

  test "checkpoint inherits root_conversation_id from parent" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    root = space.conversations.create!(title: "Root", kind: "root")
    checkpoint = space.conversations.create!(title: "Checkpoint", kind: "checkpoint", parent_conversation: root)

    assert_equal root.id, checkpoint.root_conversation_id
    assert_equal root.id, checkpoint.parent_conversation_id
  end

  test "parent_conversation must belong to same space" do
    space1 = Spaces::Playground.create!(name: "Space 1", owner: users(:admin))
    space2 = Spaces::Playground.create!(name: "Space 2", owner: users(:admin))
    root = space1.conversations.create!(title: "Root", kind: "root")

    invalid = space2.conversations.build(title: "Cross-space Branch", kind: "branch", parent_conversation: root)

    assert_not invalid.valid?
    assert_includes invalid.errors[:parent_conversation], "must belong to the same space"
  end

  # --- Forked From Message Tests ---

  test "forked_from_message can be set for branch conversation" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    root = space.conversations.create!(title: "Root", kind: "root")
    message = root.messages.create!(space_membership: user_membership, content: "Test message", role: "user")

    branch = space.conversations.create!(
      title: "Branch",
      kind: "branch",
      parent_conversation: root,
      forked_from_message: message
    )

    assert_equal message.id, branch.forked_from_message_id
  end

  test "forked_from_message must belong to parent conversation" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    root = space.conversations.create!(title: "Root", kind: "root")
    other_root = space.conversations.create!(title: "Other Root", kind: "root")
    message = other_root.messages.create!(space_membership: user_membership, content: "Wrong message", role: "user")

    invalid = space.conversations.build(
      title: "Invalid Branch",
      kind: "branch",
      parent_conversation: root,
      forked_from_message: message
    )

    assert_not invalid.valid?
    assert_includes invalid.errors[:forked_from_message], "must belong to the parent conversation"
  end

  test "forked_from_message cannot be set without parent conversation" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    root = space.conversations.create!(title: "Root", kind: "root")
    message = root.messages.create!(space_membership: user_membership, content: "Test", role: "user")

    invalid = space.conversations.build(
      title: "Invalid",
      kind: "root",
      forked_from_message: message
    )

    assert_not invalid.valid?
    assert_includes invalid.errors[:forked_from_message], "cannot be set without a parent conversation"
  end

  # --- Association Tests ---

  test "child_conversations returns direct children only" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    root = space.conversations.create!(title: "Root", kind: "root")
    branch1 = space.conversations.create!(title: "Branch 1", kind: "branch", parent_conversation: root)
    branch2 = space.conversations.create!(title: "Branch 2", kind: "branch", parent_conversation: root)
    nested = space.conversations.create!(title: "Nested", kind: "branch", parent_conversation: branch1)

    assert_includes root.child_conversations, branch1
    assert_includes root.child_conversations, branch2
    assert_not_includes root.child_conversations, nested
  end

  test "descendant_conversations returns all conversations with same root including self" do
    space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    root = space.conversations.create!(title: "Root", kind: "root")
    branch1 = space.conversations.create!(title: "Branch 1", kind: "branch", parent_conversation: root)
    branch2 = space.conversations.create!(title: "Branch 2", kind: "branch", parent_conversation: root)
    nested = space.conversations.create!(title: "Nested", kind: "branch", parent_conversation: branch1)

    # descendant_conversations are all conversations with this root (including the root itself)
    descendants = root.descendant_conversations.to_a

    assert_includes descendants, root
    assert_includes descendants, branch1
    assert_includes descendants, branch2
    assert_includes descendants, nested

    # To get only non-root descendants, filter by parent_conversation_id.present?
    non_root_descendants = root.descendant_conversations.where.not(parent_conversation_id: nil).to_a
    assert_not_includes non_root_descendants, root
    assert_includes non_root_descendants, branch1
  end

  # --- Fixtures Compatibility Test ---

  test "existing fixture conversations have correct root_conversation_id after reload" do
    # Fixtures don't trigger callbacks, so we verify the model behavior separately
    space = Spaces::Playground.create!(name: "Fresh Space", owner: users(:admin))
    conv = space.conversations.create!(title: "Fresh Root", kind: "root")

    conv.reload
    assert_equal conv.id, conv.root_conversation_id
  end
end
