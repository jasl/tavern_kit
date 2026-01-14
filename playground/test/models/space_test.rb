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

  test "group? returns true when space has multiple active AI characters" do
    user = users(:admin)
    char1 = characters(:ready_v2)
    char2 = characters(:ready_v3)

    space = Spaces::Playground.create!(name: "Group Test", owner: user)
    SpaceMemberships::Grant.call(space: space, actors: user, role: "owner")
    SpaceMemberships::Grant.call(space: space, actors: char1)
    SpaceMemberships::Grant.call(space: space, actors: char2)

    assert space.group?, "Space with 2 active AI characters should be a group"
  end

  test "group? returns false when space has only one active AI character" do
    user = users(:admin)
    char1 = characters(:ready_v2)

    space = Spaces::Playground.create!(name: "Solo Test", owner: user)
    SpaceMemberships::Grant.call(space: space, actors: user, role: "owner")
    SpaceMemberships::Grant.call(space: space, actors: char1)

    assert_not space.group?, "Space with 1 AI character should not be a group"
  end

  test "group? returns false after removing a character from a two-character space" do
    user = users(:admin)
    char1 = characters(:ready_v2)
    char2 = characters(:ready_v3)

    space = Spaces::Playground.create!(name: "Group Test", owner: user)
    space.space_memberships.grant_to(user, role: "owner")
    space.space_memberships.grant_to(char1)
    space.space_memberships.grant_to(char2)

    assert space.group?, "Initially should be a group"

    # Remove one character
    char2_membership = space.space_memberships.find_by(character: char2)
    char2_membership.remove!(by_user: user)

    assert_not space.group?, "After removing a character, should no longer be a group"
  end

  test "group? ignores human memberships when counting" do
    user = users(:admin)
    char1 = characters(:ready_v2)

    space = Spaces::Playground.create!(name: "Human Test", owner: user)
    space.space_memberships.grant_to(user, role: "owner")
    space.space_memberships.grant_to(char1)

    # Even with 2 total memberships (1 human + 1 AI), should not be a group
    assert_equal 2, space.space_memberships.active.count
    assert_not space.group?, "Human memberships should not count toward group status"
  end

  # Token limit tests
  test "total_tokens_used returns sum of prompt and completion tokens" do
    space = Spaces::Playground.create!(name: "Token Test", owner: users(:admin))
    space.update_columns(prompt_tokens_total: 100, completion_tokens_total: 50)

    assert_equal 150, space.total_tokens_used
  end

  test "effective_token_limit returns nil when no limits are set" do
    space = Spaces::Playground.create!(name: "Token Test", owner: users(:admin))
    Setting.delete("space.max_token_limit")

    assert_nil space.effective_token_limit
  end

  test "effective_token_limit returns nil when space_limit is 0 and no global limit" do
    space = Spaces::Playground.create!(name: "Token Test", owner: users(:admin), token_limit: 0)
    Setting.delete("space.max_token_limit")

    assert_nil space.effective_token_limit
  end

  test "effective_token_limit returns space limit when set and no global limit" do
    space = Spaces::Playground.create!(name: "Token Test", owner: users(:admin), token_limit: 1000)
    Setting.delete("space.max_token_limit")

    assert_equal 1000, space.effective_token_limit
  end

  test "effective_token_limit returns global limit when set and no space limit" do
    space = Spaces::Playground.create!(name: "Token Test", owner: users(:admin))
    Setting.set("space.max_token_limit", "5000")

    assert_equal 5000, space.effective_token_limit
  ensure
    Setting.delete("space.max_token_limit")
  end

  test "effective_token_limit returns the more restrictive limit" do
    space = Spaces::Playground.create!(name: "Token Test", owner: users(:admin), token_limit: 1000)
    Setting.set("space.max_token_limit", "5000")

    # Space limit (1000) is more restrictive than global (5000)
    assert_equal 1000, space.effective_token_limit

    space.update!(token_limit: 10_000)
    # Now global limit (5000) is more restrictive
    assert_equal 5000, space.effective_token_limit
  ensure
    Setting.delete("space.max_token_limit")
  end

  test "token_limit_exceeded? returns false when no limit is set" do
    space = Spaces::Playground.create!(name: "Token Test", owner: users(:admin))
    space.update_columns(prompt_tokens_total: 10_000, completion_tokens_total: 5000)
    Setting.delete("space.max_token_limit")

    assert_not space.token_limit_exceeded?
  end

  test "token_limit_exceeded? returns false when under limit" do
    space = Spaces::Playground.create!(name: "Token Test", owner: users(:admin), token_limit: 1000)
    space.update_columns(prompt_tokens_total: 400, completion_tokens_total: 200)

    assert_not space.token_limit_exceeded?
  end

  test "token_limit_exceeded? returns true when at limit" do
    space = Spaces::Playground.create!(name: "Token Test", owner: users(:admin), token_limit: 1000)
    space.update_columns(prompt_tokens_total: 600, completion_tokens_total: 400)

    assert space.token_limit_exceeded?
  end

  test "token_limit_exceeded? returns true when over limit" do
    space = Spaces::Playground.create!(name: "Token Test", owner: users(:admin), token_limit: 1000)
    space.update_columns(prompt_tokens_total: 800, completion_tokens_total: 500)

    assert space.token_limit_exceeded?
  end

  test "token_limit validation rejects nil" do
    space = Spaces::Playground.new(name: "Token Test", owner: users(:admin), token_limit: nil)
    assert_not space.valid?
    assert_includes space.errors[:token_limit], "is not a number"
  end

  test "token_limit validation allows 0" do
    space = Spaces::Playground.new(name: "Token Test", owner: users(:admin), token_limit: 0)
    assert space.valid?
  end

  test "token_limit validation allows positive integers" do
    space = Spaces::Playground.new(name: "Token Test", owner: users(:admin), token_limit: 1000)
    assert space.valid?
  end

  test "token_limit validation rejects negative values" do
    space = Spaces::Playground.new(name: "Token Test", owner: users(:admin), token_limit: -1)
    assert_not space.valid?
    assert_includes space.errors[:token_limit], "must be greater than or equal to 0"
  end
end
