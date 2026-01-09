# frozen_string_literal: true

require "test_helper"

class LockableTest < ActiveSupport::TestCase
  setup do
    @lorebook = Lorebook.create!(name: "Test Lorebook")
  end

  teardown do
    @lorebook&.destroy
  end

  test "locked? returns false when locked_at is nil" do
    assert_nil @lorebook.locked_at
    assert_not @lorebook.locked?
  end

  test "locked? returns true when locked_at is present" do
    @lorebook.update_column(:locked_at, Time.current)
    assert @lorebook.locked?
  end

  test "lock! sets locked_at timestamp" do
    assert_nil @lorebook.locked_at

    @lorebook.lock!

    assert_not_nil @lorebook.reload.locked_at
    assert @lorebook.locked?
  end

  test "unlock! clears locked_at timestamp" do
    @lorebook.update_column(:locked_at, Time.current)
    assert @lorebook.locked?

    @lorebook.unlock!

    assert_nil @lorebook.reload.locked_at
    assert_not @lorebook.locked?
  end

  test "lock! bypasses before_update callback" do
    # First lock the record via update_column (simulating already locked)
    @lorebook.update_column(:locked_at, 1.hour.ago)
    assert @lorebook.locked?

    # unlock! should still work even though record is locked
    @lorebook.unlock!
    assert_not @lorebook.reload.locked?

    # lock! should work on unlocked record
    @lorebook.lock!
    assert @lorebook.reload.locked?
  end

  test "prevent_update_when_locked blocks regular updates" do
    @lorebook.lock!

    result = @lorebook.update(name: "New Name")

    assert_not result
    assert_equal "Test Lorebook", @lorebook.reload.name
    assert_includes @lorebook.errors[:base], "Record is locked"
  end

  test "prevent_destroy_when_locked blocks deletion" do
    @lorebook.lock!

    result = @lorebook.destroy

    assert_not result
    assert Lorebook.exists?(@lorebook.id)
    assert_includes @lorebook.errors[:base], "Record is locked"
  end

  test "unlocked records can be updated" do
    result = @lorebook.update(name: "New Name")

    assert result
    assert_equal "New Name", @lorebook.reload.name
  end

  test "unlocked records can be destroyed" do
    result = @lorebook.destroy

    assert result
    assert_not Lorebook.exists?(@lorebook.id)
  end
end
