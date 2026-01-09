# frozen_string_literal: true

require "test_helper"

class Settings::CharactersControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :admin

    @character = characters(:ready_v2)
    @locked_character = characters(:ready_v3)
    @locked_character.update_column(:locked_at, Time.current)
  end

  # === Show Action ===
  test "show renders read-only view" do
    get settings_character_url(@character)

    assert_response :success
    assert_select "h2.card-title", /Basic Info/
  end

  test "show displays lock banner for locked character" do
    get settings_character_url(@locked_character)

    assert_response :success
    assert_select ".alert-warning", /locked/i
  end

  # === Edit Action ===
  test "edit renders form for unlocked character" do
    get edit_settings_character_url(@character)

    assert_response :success
    assert_select "form"
  end

  test "edit redirects to show for locked character" do
    get edit_settings_character_url(@locked_character)

    assert_redirected_to settings_character_url(@locked_character)
  end

  # === Update Action ===
  test "update modifies unlocked character" do
    patch settings_character_url(@character), params: {
      character: { name: "New Name" },
    }

    assert_response :redirect
    @character.reload
    assert_equal "New Name", @character.name
  end

  test "update is blocked for locked character" do
    original_name = @locked_character.name

    patch settings_character_url(@locked_character), params: {
      character: { name: "Hacked Name" },
    }

    assert_redirected_to settings_character_url(@locked_character)
    @locked_character.reload
    assert_equal original_name, @locked_character.name
  end

  test "update via JSON is blocked for locked character" do
    original_name = @locked_character.name

    patch settings_character_url(@locked_character),
          params: { data: { name: "Hacked Name" } }.to_json,
          headers: { "Content-Type": "application/json" }

    assert_response :forbidden
    @locked_character.reload
    assert_equal original_name, @locked_character.name
  end

  # === Destroy Action ===
  test "destroy removes unlocked character" do
    @character.update_column(:status, "ready")

    assert_enqueued_with(job: CharacterDeleteJob) do
      delete settings_character_url(@character)
    end

    assert_redirected_to settings_characters_url
  end

  test "destroy is blocked for locked character" do
    delete settings_character_url(@locked_character)

    assert_redirected_to settings_characters_url
    assert Character.exists?(@locked_character.id)
  end

  # === Duplicate Action ===
  test "duplicate creates a copy with (Copy) suffix" do
    assert_difference "Character.count", 1 do
      post duplicate_settings_character_url(@character)
    end

    assert_response :redirect
    new_character = Character.order(created_at: :desc).first
    assert_equal "#{@character.name} (Copy)", new_character.name
    assert_nil new_character.locked_at
  end

  test "duplicate works for locked character" do
    assert_difference "Character.count", 1 do
      post duplicate_settings_character_url(@locked_character)
    end

    new_character = Character.order(created_at: :desc).first
    assert_nil new_character.locked_at
  end

  # === Lock Action ===
  test "lock sets locked_at timestamp" do
    assert_nil @character.locked_at

    post lock_settings_character_url(@character)

    assert_redirected_to settings_characters_url
    @character.reload
    assert_not_nil @character.locked_at
    assert @character.locked?
  end

  # === Unlock Action ===
  test "unlock clears locked_at timestamp" do
    assert @locked_character.locked?

    post unlock_settings_character_url(@locked_character)

    assert_redirected_to settings_characters_url
    @locked_character.reload
    assert_nil @locked_character.locked_at
    assert_not @locked_character.locked?
  end

  # === Publish Action ===
  test "publish sets visibility to public" do
    @character.update_column(:visibility, "private")
    assert @character.reload.draft?

    post publish_settings_character_url(@character)

    assert_redirected_to settings_characters_url
    @character.reload
    assert_equal "public", @character.visibility
    assert @character.published?
  end

  # === Unpublish Action ===
  test "unpublish sets visibility to private" do
    @character.update_column(:visibility, "public")
    assert @character.reload.published?

    post unpublish_settings_character_url(@character)

    assert_redirected_to settings_characters_url
    @character.reload
    assert_equal "private", @character.visibility
    assert @character.draft?
  end
end
