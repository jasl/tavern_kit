# frozen_string_literal: true

require "test_helper"

class LorebookImportJobTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
  end

  test "imports lorebook JSON successfully" do
    placeholder = Lorebook.create!(
      name: "My Imported Lorebook",
      status: "pending",
      visibility: "private",
      user: @user
    )

    upload = @user.lorebook_uploads.create!(
      filename: "world_one.json",
      content_type: "application/json",
      status: "pending",
      lorebook: placeholder
    )

    fixture_path = file_fixture("lorebooks/world_one.json")
    upload.file.attach(
      io: File.open(fixture_path, "rb"),
      filename: "world_one.json",
      content_type: "application/json"
    )

    assert_no_difference "Lorebook.count" do
      LorebookImportJob.perform_now(upload.id)
    end

    upload.reload
    placeholder.reload

    assert upload.completed?
    assert placeholder.ready?
    assert_equal "My Imported Lorebook", placeholder.name
    assert_equal "Test lorebook one", placeholder.description
    assert_equal 1, placeholder.entries_count
    assert_equal "Dragons exist.", placeholder.entries.first.content
    assert_equal Digest::SHA256.hexdigest(File.binread(fixture_path)), placeholder.file_sha256
  end

  test "deduplicates lorebook import by file_sha256 within the same user scope" do
    fixture_path = file_fixture("lorebooks/world_one.json")
    sha = Digest::SHA256.hexdigest(File.binread(fixture_path))

    existing = Lorebook.create!(
      name: "Existing Lorebook",
      status: "ready",
      visibility: "private",
      user: @user,
      file_sha256: sha
    )

    placeholder = Lorebook.create!(
      name: "Duplicate Placeholder",
      status: "pending",
      visibility: "private",
      user: @user
    )

    upload = @user.lorebook_uploads.create!(
      filename: "world_one.json",
      content_type: "application/json",
      status: "pending",
      lorebook: placeholder
    )

    upload.file.attach(
      io: File.open(fixture_path, "rb"),
      filename: "world_one.json",
      content_type: "application/json"
    )

    assert_difference "Lorebook.count", -1 do
      LorebookImportJob.perform_now(upload.id)
    end

    upload.reload

    assert upload.completed?
    assert_equal existing.id, upload.lorebook_id
    assert_nil Lorebook.find_by(id: placeholder.id)
  end

  test "does not deduplicate across different users" do
    user2 = users(:member)
    fixture_path = file_fixture("lorebooks/world_one.json")
    sha = Digest::SHA256.hexdigest(File.binread(fixture_path))

    Lorebook.create!(
      name: "User1 Existing",
      status: "ready",
      visibility: "private",
      user: @user,
      file_sha256: sha
    )

    placeholder = Lorebook.create!(
      name: "User2 Placeholder",
      status: "pending",
      visibility: "private",
      user: user2
    )

    upload = user2.lorebook_uploads.create!(
      filename: "world_one.json",
      content_type: "application/json",
      status: "pending",
      lorebook: placeholder
    )

    upload.file.attach(
      io: File.open(fixture_path, "rb"),
      filename: "world_one.json",
      content_type: "application/json"
    )

    assert_no_difference "Lorebook.count" do
      LorebookImportJob.perform_now(upload.id)
    end

    upload.reload
    placeholder.reload

    assert upload.completed?
    assert placeholder.ready?
    assert_equal sha, placeholder.file_sha256
  end

  test "marks upload and placeholder as failed for invalid JSON" do
    placeholder = Lorebook.create!(
      name: "Bad Lorebook",
      status: "pending",
      visibility: "private",
      user: @user
    )

    upload = @user.lorebook_uploads.create!(
      filename: "invalid.json",
      content_type: "application/json",
      status: "pending",
      lorebook: placeholder
    )

    fixture_path = file_fixture("lorebooks/invalid.json")
    upload.file.attach(
      io: File.open(fixture_path, "rb"),
      filename: "invalid.json",
      content_type: "application/json"
    )

    LorebookImportJob.perform_now(upload.id)

    upload.reload
    placeholder.reload

    assert upload.failed?
    assert placeholder.failed?
    assert placeholder.import_error.present?
  end
end
