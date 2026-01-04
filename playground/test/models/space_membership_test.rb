# frozen_string_literal: true

require "test_helper"

class SpaceMembershipTest < ActiveSupport::TestCase
  fixtures :users, :characters, :llm_providers

  test "kind=human requires user_id" do
    space = Spaces::Playground.create!(name: "Validation Space", owner: users(:admin))

    membership = space.space_memberships.new(kind: "human")
    assert_not membership.valid?
    assert_includes membership.errors[:user_id], "must be present for human memberships"
  end

  test "kind=character requires character_id and forbids user_id" do
    space = Spaces::Playground.create!(name: "Validation Space", owner: users(:admin))

    membership = space.space_memberships.new(kind: "character", user: users(:admin))
    assert_not membership.valid?
    assert_includes membership.errors[:character_id], "must be present for character memberships"
    assert_includes membership.errors[:user_id], "must be blank for character memberships"
  end

  test "allows a human membership to also carry a character persona" do
    space = Spaces::Playground.create!(name: "Validation Space", owner: users(:admin))

    membership =
      space.space_memberships.create!(
        kind: "human",
        user: users(:member),
        character: characters(:ready_v2),
        role: "member"
      )

    assert membership.kind_human?
    assert membership.user?
    assert membership.character?
    assert membership.copilot_none?
  end

  test "requires user+character for full copilot" do
    space = Spaces::Playground.create!(name: "Validation Space", owner: users(:admin))

    missing_character = space.space_memberships.new(kind: "human", user: users(:member), copilot_mode: "full")
    assert_not missing_character.valid?
    assert_includes missing_character.errors[:copilot_mode], "requires both a user and a character"

    ok =
      space.space_memberships.create!(
        kind: "human",
        user: users(:member),
        character: characters(:ready_v2),
        copilot_mode: "full",
        role: "member"
      )
    assert ok.copilot_full?
  end

  test "playground spaces allow only one human membership" do
    space = Spaces::Playground.create!(name: "Playground Space", owner: users(:admin))
    space.space_memberships.create!(kind: "human", user: users(:admin), role: "owner")

    second = space.space_memberships.new(kind: "human", user: users(:member), role: "member")
    assert_not second.valid?
    assert_includes second.errors[:kind], "only one human membership is allowed in a playground space"
  end

  test "enabling full copilot without steps defaults to a safe budget" do
    space = Spaces::Playground.create!(name: "Copilot Budget Space", owner: users(:admin))

    membership =
      space.space_memberships.create!(
        kind: "human",
        user: users(:member),
        character: characters(:ready_v2),
        copilot_mode: "none",
        role: "member"
      )

    membership.update!(copilot_mode: "full")

    assert membership.reload.copilot_full?
    assert_equal SpaceMembership::DEFAULT_COPILOT_STEPS, membership.copilot_remaining_steps
  end

  test "full copilot enforces a 1..10 step budget" do
    space = Spaces::Playground.create!(name: "Copilot Budget Space", owner: users(:admin))

    membership =
      space.space_memberships.new(
        kind: "human",
        user: users(:member),
        character: characters(:ready_v2),
        copilot_mode: "full",
        copilot_remaining_steps: 11,
        role: "member"
      )

    assert_not membership.valid?
    assert membership.errors[:copilot_remaining_steps].any?
  end

  test "provider_identification returns nil when effective provider is nil" do
    space = Spaces::Playground.create!(name: "Provider Space", owner: users(:admin))

    membership =
      space.space_memberships.create!(
        kind: "human",
        user: users(:admin),
        role: "member"
      )

    membership.define_singleton_method(:effective_llm_provider) { nil }
    assert_nil membership.provider_identification
  end
end
