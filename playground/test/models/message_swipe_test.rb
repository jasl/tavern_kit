# frozen_string_literal: true

require "test_helper"

class MessageSwipeTest < ActiveSupport::TestCase
  fixtures :users, :characters

  def setup
    @space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    @conversation = @space.conversations.create!(title: "Main")
    @membership =
      @space.space_memberships.create!(
        kind: "character",
        character: characters(:ready_v2),
        role: "member",
        position: 0
      )
    @message = @conversation.messages.create!(
      space_membership: @membership,
      role: "assistant",
      content: "Original content"
    )
  end

  test "belongs to message" do
    swipe = @message.message_swipes.create!(position: 0, content: "Test")
    assert_equal @message, swipe.message
  end

  test "validates position is non-negative" do
    swipe = @message.message_swipes.build(position: -1, content: "Test")
    assert_not swipe.valid?
    assert_includes swipe.errors[:position], "must be greater than or equal to 0"
  end

  test "validates position uniqueness within message" do
    @message.message_swipes.create!(position: 0, content: "First")

    duplicate = @message.message_swipes.build(position: 0, content: "Duplicate")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:position], "has already been taken"
  end

  test "ordered scope returns swipes by position" do
    swipe2 = @message.message_swipes.create!(position: 2, content: "Third")
    swipe0 = @message.message_swipes.create!(position: 0, content: "First")
    swipe1 = @message.message_swipes.create!(position: 1, content: "Second")

    assert_equal [swipe0, swipe1, swipe2], @message.message_swipes.ordered.to_a
  end

  test "active? returns true when swipe is the active one" do
    swipe = @message.message_swipes.create!(position: 0, content: "Test")
    @message.update!(active_message_swipe: swipe)

    assert swipe.active?
  end

  test "active? returns false when swipe is not active" do
    swipe1 = @message.message_swipes.create!(position: 0, content: "First")
    swipe2 = @message.message_swipes.create!(position: 1, content: "Second")
    @message.update!(active_message_swipe: swipe2)

    assert_not swipe1.active?
  end

  test "first? returns true for position 0" do
    swipe = @message.message_swipes.create!(position: 0, content: "Test")
    assert swipe.first?
  end

  test "first? returns false for non-zero position" do
    @message.message_swipes.create!(position: 0, content: "First")
    swipe = @message.message_swipes.create!(position: 1, content: "Second")

    assert_not swipe.first?
  end

  test "last? returns true for highest position" do
    @message.message_swipes.create!(position: 0, content: "First")
    swipe = @message.message_swipes.create!(position: 1, content: "Second")

    assert swipe.last?
  end

  test "last? returns false when not at highest position" do
    swipe = @message.message_swipes.create!(position: 0, content: "First")
    @message.message_swipes.create!(position: 1, content: "Second")

    assert_not swipe.last?
  end

  test "counter cache updates message_swipes_count" do
    assert_equal 0, @message.message_swipes_count

    @message.message_swipes.create!(position: 0, content: "First")
    @message.reload
    assert_equal 1, @message.message_swipes_count

    @message.message_swipes.create!(position: 1, content: "Second")
    @message.reload
    assert_equal 2, @message.message_swipes_count
  end
end
