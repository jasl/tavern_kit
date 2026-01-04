# frozen_string_literal: true

require "test_helper"

class SpaceMembershipLifecycleTest < ActiveSupport::TestCase
  setup do
    @space = spaces(:general)
    @user = users(:admin)
    @character = characters(:ready_v3)
  end

  # ──────────────────────────────────────────────────────────────────
  # Status enum tests
  # ──────────────────────────────────────────────────────────────────

  test "status defaults to active for character memberships" do
    # Use character membership to avoid "only one human" validation
    membership = SpaceMembership.new(
      space: @space,
      character: @character,
      kind: "character"
    )
    membership.save!
    assert membership.active_membership?
    assert_equal "active", membership.status
  end

  test "status enum includes expected values" do
    assert_equal %w[active removed], SpaceMembership::STATUSES
  end

  test "invalid status raises ArgumentError" do
    membership = space_memberships(:admin_in_general)
    # Rails enums raise ArgumentError when assigning invalid values
    assert_raises(ArgumentError) do
      membership.status = "invalid"
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # Participation enum tests
  # ──────────────────────────────────────────────────────────────────

  test "participation defaults to active for character memberships" do
    # Use character membership to avoid "only one human" validation
    membership = SpaceMembership.new(
      space: @space,
      character: @character,
      kind: "character"
    )
    membership.save!
    assert membership.participation_active?
    assert_equal "active", membership.participation
  end

  test "participation enum includes expected values" do
    assert_equal %w[active muted observer], SpaceMembership::PARTICIPATIONS
  end

  test "invalid participation raises ArgumentError" do
    membership = space_memberships(:admin_in_general)
    # Rails enums raise ArgumentError when assigning invalid values
    assert_raises(ArgumentError) do
      membership.participation = "invalid"
    end
  end

  # ──────────────────────────────────────────────────────────────────
  # remove! method tests
  # ──────────────────────────────────────────────────────────────────

  test "remove! sets status to removed" do
    membership = space_memberships(:character_in_general)

    membership.remove!

    assert membership.removed_membership?
    assert_equal "removed", membership.status
  end

  test "remove! sets participation to muted" do
    membership = space_memberships(:character_in_general)

    membership.remove!

    assert membership.participation_muted?
    assert_equal "muted", membership.participation
  end

  test "remove! sets removed_at timestamp" do
    membership = space_memberships(:character_in_general)

    freeze_time do
      membership.remove!
      assert_equal Time.current, membership.removed_at
    end
  end

  test "remove! sets removed_by when provided" do
    membership = space_memberships(:character_in_general)

    membership.remove!(by_user: @user, reason: "Testing removal")

    assert_equal @user, membership.removed_by
    assert_equal "Testing removal", membership.removed_reason
  end

  test "remove! clears copilot_mode and unread_at" do
    membership = space_memberships(:admin_in_general)
    membership.update!(copilot_mode: "full", copilot_remaining_steps: 5, character: @character)
    membership.update!(unread_at: Time.current)

    membership.remove!

    assert_equal "none", membership.copilot_mode
    assert_nil membership.unread_at
  end

  # ──────────────────────────────────────────────────────────────────
  # Scope tests
  # ──────────────────────────────────────────────────────────────────

  test "active scope returns only status=active memberships" do
    membership = space_memberships(:character_in_general)
    membership.remove!

    active_ids = @space.space_memberships.active.pluck(:id)
    assert_not_includes active_ids, membership.id
  end

  test "removed scope returns only status=removed memberships" do
    membership = space_memberships(:character_in_general)
    membership.remove!

    removed_ids = @space.space_memberships.removed.pluck(:id)
    assert_includes removed_ids, membership.id
  end

  test "participating scope returns status=active AND participation=active" do
    membership = space_memberships(:character_in_general)

    # Initially should be in participating
    assert_includes @space.space_memberships.participating.pluck(:id), membership.id

    # Mute participation
    membership.update!(participation: "muted")
    assert_not_includes @space.space_memberships.participating.pluck(:id), membership.id

    # Restore participation but remove from space
    membership.update!(participation: "active")
    membership.remove!
    assert_not_includes @space.space_memberships.participating.pluck(:id), membership.id
  end

  test "muted scope returns participation=muted memberships" do
    membership = space_memberships(:character_in_general)
    membership.update!(participation: "muted")

    muted_ids = @space.space_memberships.muted.pluck(:id)
    assert_includes muted_ids, membership.id
  end

  # ──────────────────────────────────────────────────────────────────
  # display_name tests
  # ──────────────────────────────────────────────────────────────────

  test "display_name returns cached name for removed memberships" do
    membership = space_memberships(:character_in_general)
    original_name = membership.character.name

    membership.remove!(by_user: @user)

    # Should still return the original name, not "[Removed]"
    assert_equal original_name, membership.display_name
    assert membership.removed?
  end

  test "display_name returns character name for active memberships" do
    membership = space_memberships(:character_in_general)
    assert_equal membership.character.name, membership.display_name
  end

  test "display_name_cache is set on create" do
    # Create a new space to avoid duplicate character constraint
    space = Spaces::Playground.create!(name: "Cache Test", owner: @user)
    space.space_memberships.grant_to(@user, role: "owner")

    character = characters(:ready_v2)
    membership = space.space_memberships.create!(
      kind: "character",
      character: character,
      position: 1
    )

    assert_equal character.name, membership.display_name_cache
  end

  test "display_name uses cache even if character is deleted" do
    membership = space_memberships(:character_in_general)
    original_name = membership.character.name

    # Ensure cache is populated
    membership.update_column(:display_name_cache, original_name) unless membership.display_name_cache.present?

    # Simulate character deletion (nullify)
    membership.update_column(:character_id, nil)

    assert_equal original_name, membership.display_name
  end

  test "removed? returns true for removed memberships" do
    membership = space_memberships(:character_in_general)
    assert_not membership.removed?

    membership.remove!(by_user: @user)

    assert membership.removed?
  end

  # ──────────────────────────────────────────────────────────────────
  # Grant/revoke integration tests
  # ──────────────────────────────────────────────────────────────────

  test "revoke_from removes membership" do
    membership = space_memberships(:character_in_general)
    character = membership.character

    @space.space_memberships.revoke_from(character, by_user: @user, reason: "Testing")

    membership.reload
    assert membership.removed_membership?
    assert_equal @user, membership.removed_by
    assert_equal "Testing", membership.removed_reason
  end

  test "grant_to restores removed membership" do
    membership = space_memberships(:character_in_general)
    character = membership.character

    # First remove
    membership.remove!(by_user: @user, reason: "Testing")
    assert membership.removed_membership?

    # Then re-grant
    @space.space_memberships.grant_to(character)

    membership.reload
    assert membership.active_membership?
    assert membership.participation_active?
    assert_nil membership.removed_at
    assert_nil membership.removed_by
    assert_nil membership.removed_reason
  end

  test "revise can revoke memberships with tracking" do
    membership = space_memberships(:character_in_general)
    character = membership.character

    @space.space_memberships.revise(revoked: [character], by_user: @user, reason: "Batch revoke")

    membership.reload
    assert membership.removed_membership?
    assert_equal @user, membership.removed_by
  end

  # ──────────────────────────────────────────────────────────────────
  # Destroy protection tests
  # ──────────────────────────────────────────────────────────────────

  test "direct destroy raises to protect author anchors" do
    membership = space_memberships(:character_in_general)

    error = assert_raises(ActiveRecord::RecordNotDestroyed) do
      membership.destroy!
    end

    assert_match(/cannot be destroyed directly/i, error.message)
    assert_match(/use remove!/i, error.message)
  end

  test "destroy returns false instead of raising" do
    membership = space_memberships(:character_in_general)

    # destroy (without bang) should return false
    result = membership.destroy
    assert_not result, "destroy should return false"
    assert membership.persisted?, "membership should still exist"
  end

  test "memberships can still be destroyed when space is destroyed" do
    # This is tested in space_test.rb but let's verify the cascade works
    space = Spaces::Playground.create!(name: "Cascade Test", owner: @user)
    space.space_memberships.grant_to(@user, role: "owner")
    space.space_memberships.grant_to(@character)

    membership_count = space.space_memberships.count
    assert membership_count.positive?

    assert_difference "SpaceMembership.count", -membership_count do
      space.destroy!
    end
  end
end
