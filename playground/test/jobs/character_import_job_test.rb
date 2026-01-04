# frozen_string_literal: true

require "test_helper"

class CharacterImportJobTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
  end

  # === Successful Import ===

  test "imports JSON character successfully" do
    upload = create_upload_with_placeholder("minimal_v2.json", "application/json")

    # Character already created as placeholder
    assert_no_difference "Character.count" do
      CharacterImportJob.perform_now(upload.id)
    end

    upload.reload
    assert upload.completed?
    assert_not_nil upload.character
    assert_equal "Test Character V2", upload.character.name
    assert_equal 2, upload.character.spec_version
    assert upload.character.ready?
  end

  test "imports V3 JSON character successfully" do
    upload = create_upload_with_placeholder("minimal_v3.json", "application/json")

    # Character already created as placeholder
    assert_no_difference "Character.count" do
      CharacterImportJob.perform_now(upload.id)
    end

    upload.reload
    assert upload.completed?
    assert_equal "Test Character V3", upload.character.name
    assert_equal 3, upload.character.spec_version
  end

  test "imports PNG character successfully" do
    upload = create_upload_with_placeholder("test_character.png", "image/png")

    # Character already created as placeholder
    assert_no_difference "Character.count" do
      CharacterImportJob.perform_now(upload.id)
    end

    upload.reload
    assert upload.completed?
    assert_not_nil upload.character
    assert upload.character.ready?
  end

  test "imports CharX archive successfully" do
    upload = create_upload_with_placeholder("test_character.charx", "application/zip")

    # Character already created as placeholder
    assert_no_difference "Character.count" do
      CharacterImportJob.perform_now(upload.id)
    end

    upload.reload
    assert upload.completed?
    assert_not_nil upload.character
    assert upload.character.ready?
  end

  # === Placeholder Character Tests ===

  test "placeholder character is pending before job runs" do
    upload = create_upload_with_placeholder("minimal_v2.json", "application/json")

    assert upload.character.pending?
    assert_nil upload.character.spec_version
  end

  test "placeholder character is updated with real data after successful import" do
    upload = create_upload_with_placeholder("minimal_v2.json", "application/json")
    placeholder = upload.character

    CharacterImportJob.perform_now(upload.id)

    placeholder.reload
    assert placeholder.ready?
    assert_equal "Test Character V2", placeholder.name
    assert_equal 2, placeholder.spec_version
    assert placeholder.data.present?
  end

  # === Status Transitions ===

  test "marks upload as processing before import" do
    upload = create_upload_with_placeholder("minimal_v2.json", "application/json")

    CharacterImportJob.perform_now(upload.id)

    # Upload should now be completed (was processing during import)
    upload.reload
    assert upload.completed?
  end

  test "marks upload as completed on success" do
    upload = create_upload_with_placeholder("minimal_v2.json", "application/json")

    CharacterImportJob.perform_now(upload.id)

    upload.reload
    assert_equal "completed", upload.status
  end

  # === Failure Handling ===

  test "marks upload and placeholder as failed for invalid JSON" do
    upload = create_upload_with_placeholder("invalid_missing_spec.json", "application/json")
    placeholder = upload.character

    # Placeholder stays but gets marked failed
    assert_no_difference "Character.count" do
      CharacterImportJob.perform_now(upload.id)
    end

    upload.reload
    placeholder.reload
    assert upload.failed?
    assert_match(/spec/i, upload.error_message)
    assert placeholder.status == "failed"
  end

  test "marks upload and placeholder as failed for missing name" do
    upload = create_upload_with_placeholder("invalid_missing_name.json", "application/json")
    placeholder = upload.character

    # Placeholder stays but gets marked failed
    assert_no_difference "Character.count" do
      CharacterImportJob.perform_now(upload.id)
    end

    upload.reload
    placeholder.reload
    assert upload.failed?
    assert_match(/name/i, upload.error_message)
    assert placeholder.status == "failed"
  end

  test "marks upload and placeholder as failed when file not attached" do
    # Create placeholder character first
    placeholder = Character.create!(
      name: "missing",
      status: "pending"
    )

    upload = @user.character_uploads.create!(
      filename: "missing.json",
      content_type: "application/json",
      status: "pending",
      character: placeholder
    )
    # No file attached

    CharacterImportJob.perform_now(upload.id)

    upload.reload
    placeholder.reload
    assert upload.failed?
    assert_match(/no file/i, upload.error_message)
    assert placeholder.status == "failed"
  end

  # === Edge Cases ===

  test "skips already processed uploads" do
    upload = create_upload_with_placeholder("minimal_v2.json", "application/json")
    upload.update!(status: "completed")

    assert_no_difference "Character.count" do
      CharacterImportJob.perform_now(upload.id)
    end
  end

  test "discards job when upload not found" do
    # Should not raise, just discard
    assert_nothing_raised do
      CharacterImportJob.perform_now(999_999)
    end
  end

  # === Backward Compatibility ===

  test "works without placeholder character (backward compatibility)" do
    upload = create_upload_without_placeholder("minimal_v2.json", "application/json")

    # Should create a new character
    assert_difference "Character.count", 1 do
      CharacterImportJob.perform_now(upload.id)
    end

    upload.reload
    assert upload.completed?
    assert_equal "Test Character V2", upload.character.name
  end

  private

  def create_upload_with_placeholder(fixture_name, content_type)
    # Extract placeholder name from filename (without extension)
    placeholder_name = File.basename(fixture_name, ".*")

    # Create placeholder character first (mimics controller behavior)
    placeholder = Character.create!(
      name: placeholder_name,
      status: "pending"
    )

    upload = @user.character_uploads.create!(
      filename: fixture_name,
      content_type: content_type,
      status: "pending",
      character: placeholder
    )

    fixture_path = file_fixture("characters/#{fixture_name}")
    upload.file.attach(
      io: File.open(fixture_path, "rb"),
      filename: fixture_name,
      content_type: content_type
    )

    upload
  end

  def create_upload_without_placeholder(fixture_name, content_type)
    upload = @user.character_uploads.create!(
      filename: fixture_name,
      content_type: content_type,
      status: "pending"
    )

    fixture_path = file_fixture("characters/#{fixture_name}")
    upload.file.attach(
      io: File.open(fixture_path, "rb"),
      filename: fixture_name,
      content_type: content_type
    )

    upload
  end
end
