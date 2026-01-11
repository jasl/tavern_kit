# frozen_string_literal: true

require "test_helper"

class Conversations::LastTurnRegeneratorTest < ActiveSupport::TestCase
  fixtures :users, :characters, :llm_providers

  setup do
    @space = Spaces::Playground.create!(
      name: "Test Space",
      owner: users(:admin),
      group_regenerate_mode: "last_turn"
    )
    @user_membership = @space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    @character_membership = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v2),
      llm_provider: llm_providers(:openai)
    )
    @character_membership_2 = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v3),
      llm_provider: llm_providers(:openai)
    )
    @conversation = @space.conversations.create!(title: "Test Conversation", kind: "root")
  end

  # --- Happy Path: Success ---

  test "returns success when user message exists and no fork points" do
    user_msg = create_message(role: "user", content: "Hello")
    ai_msg = create_message(role: "assistant", content: "Hi there!")

    result = Conversations::LastTurnRegenerator.new(conversation: @conversation).call

    assert result.success?
    assert_equal :success, result.outcome
    assert_equal @conversation, result.conversation
    assert_nil result.error
    assert_includes result.deleted_message_ids, ai_msg.id
    refute_includes result.deleted_message_ids, user_msg.id
  end

  test "deletes all messages after last user message" do
    user_msg = create_message(role: "user", content: "Hello")
    ai_msg_1 = create_message(role: "assistant", content: "Response 1")
    ai_msg_2 = create_message(role: "assistant", content: "Response 2")

    assert_difference "Message.count", -2 do
      result = Conversations::LastTurnRegenerator.new(conversation: @conversation).call
      assert result.success?
    end

    assert Message.exists?(user_msg.id)
    refute Message.exists?(ai_msg_1.id)
    refute Message.exists?(ai_msg_2.id)
  end

  test "returns success with empty deleted_message_ids when user message is tail" do
    create_message(role: "user", content: "Hello")

    result = Conversations::LastTurnRegenerator.new(conversation: @conversation).call

    assert result.success?
    assert_equal [], result.deleted_message_ids
  end

  # --- Fork Point Detection (Upfront) ---

  test "returns fallback_branch when messages to delete contain fork points" do
    user_msg = create_message(role: "user", content: "Hello")
    ai_msg = create_message(role: "assistant", content: "Hi there!")

    # Create a branch from the AI message (makes it a fork point)
    Conversations::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: ai_msg,
      kind: "branch"
    ).call

    assert_difference "Conversation.count", 1 do
      result = Conversations::LastTurnRegenerator.new(conversation: @conversation).call

      assert result.fallback_branch?
      assert_equal :fallback_branch, result.outcome
      refute_equal @conversation.id, result.conversation.id
      assert_equal "branch", result.conversation.kind
      assert_equal "#{@conversation.title} (regenerated)", result.conversation.title
    end

    # Original messages should still exist
    assert Message.exists?(user_msg.id)
    assert Message.exists?(ai_msg.id)
  end

  test "fallback branch is forked from last user message" do
    user_msg = create_message(role: "user", content: "Hello")
    create_message(role: "assistant", content: "Hi there!")
    ai_msg_2 = create_message(role: "assistant", content: "Also this")

    # Create a branch from the second AI message
    Conversations::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: ai_msg_2,
      kind: "branch"
    ).call

    result = Conversations::LastTurnRegenerator.new(conversation: @conversation).call

    assert result.fallback_branch?
    branch = result.conversation
    assert_equal user_msg.id, branch.forked_from_message_id
    assert_equal @conversation.id, branch.parent_conversation_id
  end

  # --- No User Messages Case ---

  test "returns nothing_to_regenerate when no user messages exist" do
    # Only create greeting messages (assistant)
    create_message(role: "assistant", content: "Hello! I am a greeting message.")

    result = Conversations::LastTurnRegenerator.new(conversation: @conversation).call

    assert result.nothing_to_regenerate?
    assert_equal :nothing_to_regenerate, result.outcome
    assert_equal @conversation, result.conversation
    assert_nil result.error
    assert_nil result.deleted_message_ids
  end

  test "nothing_to_regenerate preserves greeting messages" do
    greeting = create_message(role: "assistant", content: "Hello! I am a greeting message.")

    assert_no_difference "Message.count" do
      Conversations::LastTurnRegenerator.new(conversation: @conversation).call
    end

    assert Message.exists?(greeting.id)
  end

  test "returns nothing_to_regenerate for empty conversation" do
    result = Conversations::LastTurnRegenerator.new(conversation: @conversation).call

    assert result.nothing_to_regenerate?
  end

  # --- Concurrent Fork (InvalidForeignKey) ---

  test "returns fallback_branch when InvalidForeignKey raised during deletion" do
    user_msg = create_message(role: "user", content: "Hello")
    ai_msg = create_message(role: "assistant", content: "Hi there!")

    # Stub the Message.where relation to raise InvalidForeignKey on delete_all
    # This simulates a concurrent fork creation
    mock_relation = mock("relation")
    mock_relation.stubs(:delete_all).raises(ActiveRecord::InvalidForeignKey.new("FK constraint violation"))
    Message.stubs(:where).returns(mock_relation)

    result = Conversations::LastTurnRegenerator.new(conversation: @conversation).call

    assert result.fallback_branch?
    assert_equal :fallback_branch, result.outcome
    refute_nil result.conversation
    refute_equal @conversation.id, result.conversation.id

    # Note: original messages are untouched since the deletion was aborted
  end

  # --- Callback Invocation ---

  test "calls on_messages_deleted callback with deleted message IDs after successful deletion" do
    create_message(role: "user", content: "Hello")
    ai_msg_1 = create_message(role: "assistant", content: "Response 1")
    ai_msg_2 = create_message(role: "assistant", content: "Response 2")

    callback_called = false
    callback_ids = nil
    callback_conv = nil

    Conversations::LastTurnRegenerator.new(
      conversation: @conversation,
      on_messages_deleted: ->(ids, conv) {
        callback_called = true
        callback_ids = ids
        callback_conv = conv
      }
    ).call

    assert callback_called, "on_messages_deleted callback should be called"
    assert_includes callback_ids, ai_msg_1.id
    assert_includes callback_ids, ai_msg_2.id
    assert_equal @conversation, callback_conv
  end

  test "does not call on_messages_deleted callback when deletion fails with InvalidForeignKey" do
    create_message(role: "user", content: "Hello")
    create_message(role: "assistant", content: "Hi there!")

    # Stub the Message.where relation to raise InvalidForeignKey on delete_all
    mock_relation = mock("relation")
    mock_relation.stubs(:delete_all).raises(ActiveRecord::InvalidForeignKey.new("FK constraint violation"))
    Message.stubs(:where).returns(mock_relation)

    callback_called = false

    Conversations::LastTurnRegenerator.new(
      conversation: @conversation,
      on_messages_deleted: ->(_ids, _conv) { callback_called = true }
    ).call

    refute callback_called, "on_messages_deleted callback should NOT be called on failure"
  end

  test "works without on_messages_deleted callback" do
    create_message(role: "user", content: "Hello")
    create_message(role: "assistant", content: "Hi there!")

    # Should not raise when callback is nil
    result = Conversations::LastTurnRegenerator.new(conversation: @conversation).call
    assert result.success?
  end

  # --- Result Object ---

  test "Result success? returns true only for :success outcome" do
    result = Conversations::LastTurnRegenerator::Result.new(
      outcome: :success,
      conversation: @conversation,
      error: nil,
      deleted_message_ids: []
    )
    assert result.success?
    refute result.fallback_branch?
    refute result.nothing_to_regenerate?
    refute result.error?
  end

  test "Result fallback_branch? returns true only for :fallback_branch outcome" do
    result = Conversations::LastTurnRegenerator::Result.new(
      outcome: :fallback_branch,
      conversation: @conversation,
      error: nil,
      deleted_message_ids: nil
    )
    refute result.success?
    assert result.fallback_branch?
    refute result.nothing_to_regenerate?
    refute result.error?
  end

  test "Result nothing_to_regenerate? returns true only for :nothing_to_regenerate outcome" do
    result = Conversations::LastTurnRegenerator::Result.new(
      outcome: :nothing_to_regenerate,
      conversation: @conversation,
      error: nil,
      deleted_message_ids: nil
    )
    refute result.success?
    refute result.fallback_branch?
    assert result.nothing_to_regenerate?
    refute result.error?
  end

  test "Result error? returns true only for :error outcome" do
    result = Conversations::LastTurnRegenerator::Result.new(
      outcome: :error,
      conversation: @conversation,
      error: "Something went wrong",
      deleted_message_ids: nil
    )
    refute result.success?
    refute result.fallback_branch?
    refute result.nothing_to_regenerate?
    assert result.error?
  end

  # --- Error Cases ---

  test "returns error when branch creation fails" do
    create_message(role: "user", content: "Hello")
    ai_msg = create_message(role: "assistant", content: "Hi there!")

    # Create a fork point
    Conversations::Forker.new(
      parent_conversation: @conversation,
      fork_from_message: ai_msg,
      kind: "branch"
    ).call

    # Create a mock forker result
    forker_result = Struct.new(:success?, :error, :conversation).new(false, "Branch creation failed", nil)
    Conversations::Forker.any_instance.stubs(:call).returns(forker_result)

    result = Conversations::LastTurnRegenerator.new(conversation: @conversation).call

    assert result.error?
    assert_equal :error, result.outcome
    assert_equal "Branch creation failed", result.error
  end

  private

  def create_message(role:, content:, space_membership: nil)
    membership = space_membership || (role == "user" ? @user_membership : @character_membership)
    @conversation.messages.create!(
      space_membership: membership,
      role: role,
      content: content
    )
  end
end
