# frozen_string_literal: true

require "test_helper"

class CharacterDeleteJobTest < ActiveSupport::TestCase
  # === Successful Deletion ===

  test "deletes character successfully" do
    character = characters(:ready_v2)

    assert_difference "Character.count", -1 do
      CharacterDeleteJob.perform_now(character.id)
    end
  end

  test "marks character as deleting before destruction" do
    character = characters(:ready_v2)

    # Track status changes
    statuses = []
    Character.after_update { |c| statuses << c.status if c.id == character.id }

    CharacterDeleteJob.perform_now(character.id)

    assert_includes statuses, "deleting"
  end

  test "purges portrait attachment" do
    character = characters(:ready_v2)

    # Attach a portrait
    character.portrait.attach(
      io: File.open(file_fixture("characters/test_character.png"), "rb"),
      filename: "portrait.png",
      content_type: "image/png"
    )

    assert character.portrait.attached?

    CharacterDeleteJob.perform_now(character.id)

    # Character and portrait should be gone
    assert_raises(ActiveRecord::RecordNotFound) do
      character.reload
    end
  end

  test "cleans up character assets" do
    character = characters(:ready_v2)

    # Create a character asset with a blob
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("test content"),
      filename: "test_asset.png",
      content_type: "image/png"
    )

    character.character_assets.create!(
      blob: blob,
      kind: "icon",
      name: "test_icon",
      ext: ".png"
    )

    assert_equal 1, character.character_assets.count

    assert_difference "CharacterAsset.count", -1 do
      CharacterDeleteJob.perform_now(character.id)
    end
  end

  test "nullifies related character uploads" do
    character = characters(:ready_v2)
    upload = character_uploads(:completed_upload)

    # Ensure the upload is linked to our character
    assert_equal character, upload.character

    CharacterDeleteJob.perform_now(character.id)

    upload.reload
    assert_nil upload.character_id
  end

  # === Edge Cases ===

  test "discards job when character not found" do
    # Should not raise, just discard
    assert_nothing_raised do
      CharacterDeleteJob.perform_now(999_999)
    end
  end

  test "handles character with no attachments" do
    character = characters(:ready_v2)

    # Ensure no attachments
    assert_not character.portrait.attached?

    assert_difference "Character.count", -1 do
      CharacterDeleteJob.perform_now(character.id)
    end
  end

  test "handles character in different states" do
    %i[ready_v2 pending_character failed_character].each do |fixture_name|
      character = characters(fixture_name)

      assert_difference "Character.count", -1, "Failed to delete #{fixture_name}" do
        CharacterDeleteJob.perform_now(character.id)
      end
    end
  end
end
