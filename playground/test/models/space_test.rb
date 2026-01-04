# frozen_string_literal: true

require "test_helper"

class SpaceTest < ActiveSupport::TestCase
  fixtures :users, :characters

  test "create_for requires at least one character" do
    assert_raises(ArgumentError) do
      Spaces::Playground.create_for({}, user: users(:admin), characters: [])
    end
  end

  test "requires an owner" do
    space = Spaces::Playground.new(name: "Owner Space")
    assert_not space.valid?
    assert_includes space.errors[:owner], "must exist"
  end

  test "destroying a space with messages succeeds and cleans up dependent records" do
    user = users(:admin)
    character = characters(:ready_v2)

    space = Spaces::Playground.create_for({}, user: user, characters: [character])
    conversation_ids = space.conversations.pluck(:id)

    message_count = Message.where(conversation_id: conversation_ids).count
    membership_count = SpaceMembership.where(space_id: space.id).count
    conversation_count = Conversation.where(space_id: space.id).count

    assert message_count.positive?, "expected create_for to create a greeting message when available"

    assert_difference "Space.count", -1 do
      assert_difference "Conversation.count", -conversation_count do
        assert_difference "Message.count", -message_count do
          assert_difference "SpaceMembership.count", -membership_count do
            space.destroy!
          end
        end
      end
    end
  end

  test "playground? returns true for Spaces::Playground" do
    space = Spaces::Playground.new(name: "Test", owner: users(:admin))
    assert space.playground?
    assert_not space.discussion?
  end

  test "discussion? returns true for Spaces::Discussion" do
    space = Spaces::Discussion.new(name: "Test", owner: users(:admin))
    assert space.discussion?
    assert_not space.playground?
  end
end
