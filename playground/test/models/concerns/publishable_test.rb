# frozen_string_literal: true

require "test_helper"

class PublishableTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @other_user = users(:member)

    # Create test lorebooks with different visibility
    @public_lorebook = Lorebook.create!(
      name: "Public Lorebook",
      user: @user,
      visibility: "public"
    )

    @private_lorebook = Lorebook.create!(
      name: "Private Lorebook",
      user: @user,
      visibility: "private"
    )

    @other_private = Lorebook.create!(
      name: "Other Private",
      user: @other_user,
      visibility: "private"
    )
  end

  teardown do
    @public_lorebook&.destroy
    @private_lorebook&.destroy
    @other_private&.destroy
  end

  test "published? returns true when visibility is public" do
    assert @public_lorebook.published?
  end

  test "published? returns false when visibility is private" do
    assert_not @private_lorebook.published?
  end

  test "draft? returns true when visibility is private" do
    assert @private_lorebook.draft?
  end

  test "draft? returns false when visibility is public" do
    assert_not @public_lorebook.draft?
  end

  test "publish! sets visibility to public" do
    assert @private_lorebook.draft?

    @private_lorebook.publish!

    assert_equal "public", @private_lorebook.reload.visibility
    assert @private_lorebook.published?
  end

  test "unpublish! sets visibility to private" do
    assert @public_lorebook.published?

    @public_lorebook.unpublish!

    assert_equal "private", @public_lorebook.reload.visibility
    assert @public_lorebook.draft?
  end

  test "publish! bypasses locked state" do
    @private_lorebook.update_column(:locked_at, Time.current)
    assert @private_lorebook.locked?

    @private_lorebook.publish!

    assert @private_lorebook.reload.published?
  end

  test "unpublish! bypasses locked state" do
    @public_lorebook.update_column(:locked_at, Time.current)
    assert @public_lorebook.locked?

    @public_lorebook.unpublish!

    assert @public_lorebook.reload.draft?
  end

  # === accessible_to scope tests ===
  # Note: Lorebook.accessible_to uses accessible_to_system_or_owned which has special behavior:
  # - For anonymous users: only system lorebooks (user_id = NULL) that are public
  # - For logged-in users: system public + own records (any visibility)

  test "accessible_to returns only system public records for anonymous users" do
    # Create a system lorebook (no owner)
    system_lorebook = Lorebook.create!(name: "System Lorebook", user: nil, visibility: "public")

    result = Lorebook.accessible_to(nil)

    assert_includes result, system_lorebook
    # User-owned lorebooks are NOT visible to anonymous users
    assert_not_includes result, @public_lorebook
    assert_not_includes result, @private_lorebook

    system_lorebook.destroy
  end

  test "accessible_to returns all own records for owner" do
    result = Lorebook.accessible_to(@user)

    assert_includes result, @public_lorebook
    assert_includes result, @private_lorebook
    assert_not_includes result, @other_private
  end

  test "accessible_to excludes other users lorebooks" do
    result = Lorebook.accessible_to(@other_user)

    # Other user cannot see @user's lorebooks (even if public, unless system)
    assert_not_includes result, @public_lorebook
    assert_not_includes result, @private_lorebook
    # But can see their own
    assert_includes result, @other_private
  end

  # === Soft constraint behavior ===
  # The key behavior is that visibility controls access for NEW associations,
  # but existing associations remain valid even after making private

  test "unpublishing keeps record accessible to owner" do
    @public_lorebook.unpublish!

    result = Lorebook.accessible_to(@user)
    assert_includes result, @public_lorebook
  end
end
