# frozen_string_literal: true

require "test_helper"

class Settings::LorebooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :admin

    @lorebook = Lorebook.create!(
      name: "Test Lorebook",
      description: "A test lorebook",
      scan_depth: 100,
      token_budget: 2048,
      recursive_scanning: false
    )

    @locked_lorebook = Lorebook.create!(
      name: "Locked Lorebook",
      description: "A locked lorebook",
      locked_at: Time.current
    )
  end

  teardown do
    @lorebook&.destroy
    @locked_lorebook&.destroy
  end

  # === Index Action ===
  test "index renders lorebook list with pagination" do
    get settings_lorebooks_url

    assert_response :success
    assert_select ".space-y-4" # List container
  end

  # === Show Action ===
  test "show renders read-only view" do
    get settings_lorebook_url(@lorebook)

    assert_response :success
    assert_select "h1", /#{@lorebook.name}/
  end

  test "show displays lock banner for locked lorebook" do
    get settings_lorebook_url(@locked_lorebook)

    assert_response :success
    assert_select ".alert-warning", /locked/i
  end

  # === Edit Action ===
  test "edit renders form for unlocked lorebook" do
    get edit_settings_lorebook_url(@lorebook)

    assert_response :success
    assert_select "form"
  end

  test "edit redirects to show for locked lorebook" do
    get edit_settings_lorebook_url(@locked_lorebook)

    assert_redirected_to settings_lorebook_url(@locked_lorebook)
  end

  # === Update Action ===
  test "update modifies unlocked lorebook" do
    patch settings_lorebook_url(@lorebook), params: {
      lorebook: { name: "New Name" },
    }

    assert_response :redirect
    @lorebook.reload
    assert_equal "New Name", @lorebook.name
  end

  test "update is blocked for locked lorebook" do
    original_name = @locked_lorebook.name

    patch settings_lorebook_url(@locked_lorebook), params: {
      lorebook: { name: "Hacked Name" },
    }

    assert_redirected_to settings_lorebook_url(@locked_lorebook)
    @locked_lorebook.reload
    assert_equal original_name, @locked_lorebook.name
  end

  # === Destroy Action ===
  test "destroy removes unlocked lorebook" do
    assert_difference "Lorebook.count", -1 do
      delete settings_lorebook_url(@lorebook)
    end

    assert_redirected_to settings_lorebooks_url
  end

  test "destroy is blocked for locked lorebook" do
    assert_no_difference "Lorebook.count" do
      delete settings_lorebook_url(@locked_lorebook)
    end

    assert_redirected_to settings_lorebooks_url
  end

  # === Duplicate Action ===
  test "duplicate creates a copy with (Copy) suffix" do
    assert_difference "Lorebook.count", 1 do
      post duplicate_settings_lorebook_url(@lorebook)
    end

    assert_response :redirect
    new_lorebook = Lorebook.order(created_at: :desc).first
    assert_equal "#{@lorebook.name} (Copy)", new_lorebook.name
    assert_nil new_lorebook.locked_at
  end

  test "duplicate copies entries" do
    @lorebook.entries.create!(
      uid: "test-entry-1",
      keys: ["keyword"],
      content: "Test content",
      enabled: true
    )

    assert_difference "Lorebook.count", 1 do
      post duplicate_settings_lorebook_url(@lorebook)
    end

    new_lorebook = Lorebook.order(created_at: :desc).first
    assert_equal 1, new_lorebook.entries.count
    assert_equal "Test content", new_lorebook.entries.first.content
  end

  test "duplicate works for locked lorebook" do
    assert_difference "Lorebook.count", 1 do
      post duplicate_settings_lorebook_url(@locked_lorebook)
    end

    new_lorebook = Lorebook.order(created_at: :desc).first
    assert_nil new_lorebook.locked_at
  end

  # === Lock Action ===
  test "lock sets locked_at timestamp" do
    assert_nil @lorebook.locked_at

    post lock_settings_lorebook_url(@lorebook)

    assert_redirected_to settings_lorebooks_url
    @lorebook.reload
    assert_not_nil @lorebook.locked_at
    assert @lorebook.locked?
  end

  # === Unlock Action ===
  test "unlock clears locked_at timestamp" do
    assert @locked_lorebook.locked?

    post unlock_settings_lorebook_url(@locked_lorebook)

    assert_redirected_to settings_lorebooks_url
    @locked_lorebook.reload
    assert_nil @locked_lorebook.locked_at
    assert_not @locked_lorebook.locked?
  end

  # === Publish Action ===
  test "publish sets visibility to public" do
    @lorebook.update_column(:visibility, "private")
    assert @lorebook.reload.draft?

    post publish_settings_lorebook_url(@lorebook)

    assert_redirected_to settings_lorebooks_url
    @lorebook.reload
    assert_equal "public", @lorebook.visibility
    assert @lorebook.published?
  end

  # === Unpublish Action ===
  test "unpublish sets visibility to private" do
    @lorebook.update_column(:visibility, "public")
    assert @lorebook.reload.published?

    post unpublish_settings_lorebook_url(@lorebook)

    assert_redirected_to settings_lorebooks_url
    @lorebook.reload
    assert_equal "private", @lorebook.visibility
    assert @lorebook.draft?
  end
end
