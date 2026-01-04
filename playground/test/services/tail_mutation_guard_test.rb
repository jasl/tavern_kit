# frozen_string_literal: true

require "test_helper"

class TailMutationGuardTest < ActiveSupport::TestCase
  setup do
    @space = Spaces::Playground.create!(name: "Guard Test", owner: users(:admin))
    @space.space_memberships.grant_to(users(:admin), role: "owner")
    @space.space_memberships.grant_to(characters(:ready_v2))

    @conversation = @space.conversations.create!(title: "Test", kind: "root")
    @user_membership = @space.space_memberships.find_by!(user: users(:admin), kind: "human")
    @ai_membership = @space.space_memberships.find_by!(character: characters(:ready_v2), kind: "character")
  end

  test "tail_message returns nil for empty conversation" do
    guard = TailMutationGuard.new(@conversation)

    assert_nil guard.tail_message
    assert_nil guard.tail_message_id
  end

  test "tail_message returns the only message when there is one" do
    message = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Only message"
    )

    guard = TailMutationGuard.new(@conversation)

    assert_equal message, guard.tail_message
    assert_equal message.id, guard.tail_message_id
  end

  test "tail_message returns the message with highest seq" do
    first = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "First"
    )
    second = @conversation.messages.create!(
      space_membership: @ai_membership,
      role: "assistant",
      content: "Second"
    )
    third = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Third"
    )

    guard = TailMutationGuard.new(@conversation)

    assert_equal third, guard.tail_message
    assert_equal third.id, guard.tail_message_id
    refute_equal first.id, guard.tail_message_id
    refute_equal second.id, guard.tail_message_id
  end

  test "tail? returns true for tail message" do
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "First"
    )
    tail = @conversation.messages.create!(
      space_membership: @ai_membership,
      role: "assistant",
      content: "Tail"
    )

    guard = TailMutationGuard.new(@conversation)

    assert guard.tail?(tail)
  end

  test "tail? returns false for non-tail message" do
    first = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "First"
    )
    @conversation.messages.create!(
      space_membership: @ai_membership,
      role: "assistant",
      content: "Tail"
    )

    guard = TailMutationGuard.new(@conversation)

    refute guard.tail?(first)
  end

  test "tail? returns false for empty conversation" do
    guard = TailMutationGuard.new(@conversation)
    message = Message.new(id: 999)

    refute guard.tail?(message)
  end

  test "tail_message is memoized" do
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "First"
    )

    guard = TailMutationGuard.new(@conversation)

    # Access tail_message twice
    first_call = guard.tail_message
    second_call = guard.tail_message

    # Should be the same object (memoized)
    assert_same first_call, second_call
  end
end
