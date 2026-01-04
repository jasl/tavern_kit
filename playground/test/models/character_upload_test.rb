# frozen_string_literal: true

require "test_helper"

class CharacterUploadTest < ActiveSupport::TestCase
  fixtures :users, :character_uploads, :characters

  # === Validations ===

  test "valid with user and status" do
    upload = CharacterUpload.new(
      user: users(:admin),
      status: "pending"
    )
    assert upload.valid?
  end

  test "invalid without user" do
    upload = CharacterUpload.new(status: "pending")
    assert_not upload.valid?
    assert_includes upload.errors[:user], "must exist"
  end

  test "invalid with unsupported status" do
    upload = CharacterUpload.new(
      user: users(:admin),
      status: "unknown"
    )
    assert_not upload.valid?
    assert_includes upload.errors[:status], "is not included in the list"
  end

  # === Status Methods ===

  test "mark_processing! updates status" do
    upload = character_uploads(:pending_upload)
    upload.mark_processing!
    assert_equal "processing", upload.reload.status
  end

  test "mark_completed! sets character and status" do
    upload = character_uploads(:processing_upload)
    character = characters(:ready_v2)
    upload.mark_completed!(character)

    upload.reload
    assert_equal "completed", upload.status
    assert_equal character, upload.character
  end

  test "mark_failed! sets error message and status" do
    upload = character_uploads(:processing_upload)
    upload.mark_failed!("Parse error")

    upload.reload
    assert_equal "failed", upload.status
    assert_equal "Parse error", upload.error_message
  end

  # === Status Predicates ===

  test "pending? returns true for pending status" do
    assert character_uploads(:pending_upload).pending?
    assert_not character_uploads(:completed_upload).pending?
  end

  test "processing? returns true for processing status" do
    assert character_uploads(:processing_upload).processing?
    assert_not character_uploads(:pending_upload).processing?
  end

  test "completed? returns true for completed status" do
    assert character_uploads(:completed_upload).completed?
    assert_not character_uploads(:pending_upload).completed?
  end

  test "failed? returns true for failed status" do
    assert character_uploads(:failed_upload).failed?
    assert_not character_uploads(:pending_upload).failed?
  end

  # === Scopes ===

  test "scopes filter by status" do
    assert CharacterUpload.pending.all?(&:pending?)
    assert CharacterUpload.processing.all?(&:processing?)
    assert CharacterUpload.completed.all?(&:completed?)
    assert CharacterUpload.failed.all?(&:failed?)
  end

  test "recent scope orders by created_at desc" do
    uploads = CharacterUpload.recent
    dates = uploads.map(&:created_at)
    assert_equal dates.sort.reverse, dates
  end

  # === Associations ===

  test "belongs to user" do
    upload = character_uploads(:pending_upload)
    assert_instance_of User, upload.user
  end

  test "character association is optional" do
    upload = character_uploads(:pending_upload)
    assert_nil upload.character

    completed = character_uploads(:completed_upload)
    assert_instance_of Character, completed.character
  end
end
