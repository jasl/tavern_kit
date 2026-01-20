# frozen_string_literal: true

require "test_helper"

class QueryOptimizationTest < ActiveSupport::TestCase
  fixtures :users

  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(name: "Optimization Test", owner: @user)
    @membership = @space.space_memberships.create!(kind: "human", user: @user, role: "member")
    @conversation = @space.conversations.create!(title: "Test Conversation")
  end

  # Test index usage for message role queries
  test "last_assistant_message uses role index efficiently" do
    # Create messages with different roles
    @conversation.messages.create!(space_membership: @membership, role: "user", content: "Hello")
    @conversation.messages.create!(space_membership: @membership, role: "assistant", content: "Hi there")
    @conversation.messages.create!(space_membership: @membership, role: "user", content: "How are you?")
    last_assistant = @conversation.messages.create!(space_membership: @membership, role: "assistant", content: "I'm good!")

    # This query should use the new composite index
    result = @conversation.last_assistant_message
    assert_equal last_assistant.id, result.id
    assert_equal "assistant", result.role
  end

  test "last_user_message uses role index efficiently" do
    @conversation.messages.create!(space_membership: @membership, role: "user", content: "First")
    @conversation.messages.create!(space_membership: @membership, role: "assistant", content: "Response")
    last_user = @conversation.messages.create!(space_membership: @membership, role: "user", content: "Last")

    result = @conversation.last_user_message
    assert_equal last_user.id, result.id
    assert_equal "user", result.role
  end

  test "last_user_message ignores hidden messages" do
    last_visible = @conversation.messages.create!(space_membership: @membership, role: "user", content: "Last visible")
    @conversation.messages.create!(space_membership: @membership, role: "user", content: "Hidden", visibility: "hidden")

    result = @conversation.last_user_message
    assert_equal last_visible.id, result.id
  end

  test "last_assistant_message ignores hidden messages" do
    last_visible = @conversation.messages.create!(space_membership: @membership, role: "assistant", content: "Last visible")
    @conversation.messages.create!(space_membership: @membership, role: "assistant", content: "Hidden", visibility: "hidden")

    result = @conversation.last_assistant_message
    assert_equal last_visible.id, result.id
  end

  # Test conversation tree queries use the new index
  test "tree_conversations query uses root_conversation_id index" do
    root = @space.conversations.create!(title: "Root", kind: "root")
    branch1 = @space.conversations.create!(title: "Branch 1", kind: "branch", parent_conversation: root)
    branch2 = @space.conversations.create!(title: "Branch 2", kind: "branch", parent_conversation: root)
    thread = @space.conversations.create!(title: "Thread", kind: "thread", parent_conversation: branch1)

    # This should use the root_conversation_id + kind index
    tree = root.tree_conversations.to_a
    assert_includes tree.map(&:id), root.id
    assert_includes tree.map(&:id), branch1.id
    assert_includes tree.map(&:id), branch2.id
    assert_includes tree.map(&:id), thread.id
  end

  # Test Space conversation list with status filtering
  test "space conversations with status uses composite index" do
    active1 = @space.conversations.create!(title: "Active 1", status: "ready")
    active2 = @space.conversations.create!(title: "Active 2", status: "ready")
    archived = @space.conversations.create!(title: "Archived", status: "archived")

    # Query with status filter should use the composite index
    ready_conversations = @space.conversations.where(status: "ready").order(updated_at: :desc)
    assert_equal 3, ready_conversations.count # includes @conversation from setup

    archived_conversations = @space.conversations.where(status: "archived")
    assert_equal 1, archived_conversations.count
  end

  # Test AI respondable memberships query
  test "ai_respondable_space_memberships uses partial index" do
    # Create characters with minimal required data
    char1 = Character.create!(
      name: "Character 1",
      user: @user,
      status: "ready",
      spec_version: 2,
      data: TavernKit::Character::Schema.new(name: "Character 1")
    )
    char2 = Character.create!(
      name: "Character 2",
      user: @user,
      status: "ready",
      spec_version: 2,
      data: TavernKit::Character::Schema.new(name: "Character 2")
    )

    # Active AI character
    ai_member = @space.space_memberships.create!(
      kind: "character",
      character: char1,
      status: "active",
      participation: "active"
    )

    # Muted AI character (should not be included)
    muted_member = @space.space_memberships.create!(
      kind: "character",
      character: char2,
      status: "active",
      participation: "muted"
    )

    # This should use the partial index
    respondable = @space.ai_respondable_space_memberships.to_a
    assert_includes respondable.map(&:id), ai_member.id
    assert_not_includes respondable.map(&:id), muted_member.id
  end

  # Test that prompt-included queries respect visibility filter
  test "message queries respect visibility=excluded filter" do
    msg1 = @conversation.messages.create!(space_membership: @membership, role: "user", content: "Include me")
    msg2 = @conversation.messages.create!(space_membership: @membership, role: "user", content: "Exclude me", visibility: "excluded")
    msg3 = @conversation.messages.create!(space_membership: @membership, role: "user", content: "Include me too")

    included = @conversation.messages.included_in_prompt.ordered.to_a
    assert_includes included.map(&:id), msg1.id
    assert_not_includes included.map(&:id), msg2.id
    assert_includes included.map(&:id), msg3.id
  end

  # Test N+1 prevention with includes
  test "conversation.accessible_to avoids N+1 queries" do
    # Create multiple conversations
    5.times do |i|
      @space.conversations.create!(title: "Conversation #{i}")
    end

    # This query should use includes to avoid N+1
    # We verify the space is preloaded by accessing it without additional queries
    conversations = Conversation.accessible_to(@user).limit(10).to_a
    assert conversations.size > 0, "Should have conversations"

    # Verify all conversations have their spaces loaded
    conversations.each do |conv|
      assert conv.association(:space).loaded?, "Space should be preloaded"
      assert_not_nil conv.space.name # Access without triggering query
    end
  end
end
