# frozen_string_literal: true

require "test_helper"

class MessageTest < ActiveSupport::TestCase
  fixtures :users

  test "assigns seq as max+1 per conversation" do
    space = Spaces::Playground.create!(name: "Seq Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    membership = space.space_memberships.create!(kind: "human", user: users(:admin), role: "member")

    first = conversation.messages.create!(space_membership: membership, role: "user", content: "hello")
    second = conversation.messages.create!(space_membership: membership, role: "user", content: "world")

    assert_equal 1, first.seq
    assert_equal 2, second.seq
  end

  test "seq uniqueness is scoped to conversation" do
    space = Spaces::Playground.create!(name: "Seq Space", owner: users(:admin))
    membership = space.space_memberships.create!(kind: "human", user: users(:admin), role: "member")

    a = space.conversations.create!(title: "A")
    b = space.conversations.create!(title: "B")

    message_a = a.messages.create!(space_membership: membership, role: "user", content: "a")
    message_b = b.messages.create!(space_membership: membership, role: "user", content: "b")

    assert_equal 1, message_a.seq
    assert_equal 1, message_b.seq
  end

  test "respects an explicit seq" do
    space = Spaces::Playground.create!(name: "Seq Space", owner: users(:admin))
    conversation = space.conversations.create!(title: "Main")
    membership = space.space_memberships.create!(kind: "human", user: users(:admin), role: "member")

    message = conversation.messages.create!(space_membership: membership, role: "user", content: "hello", seq: 10)
    assert_equal 10, message.seq
  end

  test "destroy nullifies forked_from_message on forked conversations" do
    space = Spaces::Playground.create!(name: "Fork Space", owner: users(:admin))
    membership = space.space_memberships.create!(kind: "human", user: users(:admin), role: "member")

    root = space.conversations.create!(title: "Root", kind: "root")
    fork_point = root.messages.create!(space_membership: membership, role: "user", content: "fork here")
    branch = space.conversations.create!(
      title: "Branch",
      kind: "branch",
      parent_conversation: root,
      forked_from_message: fork_point
    )

    assert_equal fork_point.id, branch.forked_from_message_id

    fork_point.destroy!
    assert_nil branch.reload.forked_from_message_id
  end
end
