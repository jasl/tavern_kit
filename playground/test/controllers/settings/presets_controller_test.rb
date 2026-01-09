# frozen_string_literal: true

require "test_helper"

class Settings::PresetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :admin

    @preset = Preset.create!(
      name: "Test Preset",
      description: "A test preset",
      user: users(:admin),
      generation_settings: { "temperature" => 0.7 },
      preset_settings: { "main_prompt" => "Test" }
    )

    @locked_preset = Preset.create!(
      name: "Locked Preset",
      description: "A locked preset",
      user: users(:admin),
      locked_at: Time.current,
      generation_settings: { "temperature" => 0.5 },
      preset_settings: { "main_prompt" => "Locked" }
    )
  end

  teardown do
    @preset&.destroy
    @locked_preset&.destroy
  end

  # === Show Action ===
  test "show renders read-only view" do
    get settings_preset_url(@preset)

    assert_response :success
    assert_select "h2.card-title", /Settings/
  end

  test "show displays lock banner for locked preset" do
    get settings_preset_url(@locked_preset)

    assert_response :success
    assert_select ".alert-warning", /locked/i
  end

  # === Edit Action ===
  test "edit renders form for unlocked preset" do
    get edit_settings_preset_url(@preset)

    assert_response :success
    assert_select "form"
  end

  test "edit redirects to show for locked preset" do
    get edit_settings_preset_url(@locked_preset)

    assert_redirected_to settings_preset_url(@locked_preset)
  end

  # === Update Action ===
  test "update modifies unlocked preset" do
    patch settings_preset_url(@preset), params: {
      preset: { name: "New Name" },
    }

    assert_response :redirect
    @preset.reload
    assert_equal "New Name", @preset.name
  end

  test "update is blocked for locked preset" do
    original_name = @locked_preset.name

    patch settings_preset_url(@locked_preset), params: {
      preset: { name: "Hacked Name" },
    }

    assert_redirected_to settings_preset_url(@locked_preset)
    @locked_preset.reload
    assert_equal original_name, @locked_preset.name
  end

  # === Destroy Action ===
  test "destroy removes unlocked preset" do
    # Make sure this preset is not the default (defaults are stored in Setting)
    # Create a different preset as default if needed
    default_preset = Preset.get_default
    if default_preset == @preset
      other_preset = Preset.create!(
        name: "Other Preset",
        user: users(:admin),
        generation_settings: { "temperature" => 0.5 },
        preset_settings: { "main_prompt" => "Other" }
      )
      Preset.set_default!(other_preset)
    end

    assert_difference "Preset.count", -1 do
      delete settings_preset_url(@preset)
    end

    assert_redirected_to settings_presets_url
  end

  test "destroy is blocked for locked preset" do
    assert_no_difference "Preset.count" do
      delete settings_preset_url(@locked_preset)
    end

    assert_redirected_to settings_presets_url
  end

  test "destroy is blocked for default preset" do
    Preset.set_default!(@preset)

    assert_no_difference "Preset.count" do
      delete settings_preset_url(@preset)
    end

    assert_redirected_to settings_presets_url
  end

  # === Duplicate Action ===
  test "duplicate creates a copy with (Copy) suffix" do
    assert_difference "Preset.count", 1 do
      post duplicate_settings_preset_url(@preset)
    end

    assert_redirected_to settings_presets_url
    new_preset = Preset.order(created_at: :desc).first
    assert_equal "#{@preset.name} (Copy)", new_preset.name
    assert_nil new_preset.locked_at
  end

  test "duplicate copies settings" do
    assert_difference "Preset.count", 1 do
      post duplicate_settings_preset_url(@preset)
    end

    new_preset = Preset.order(created_at: :desc).first
    assert_equal @preset.generation_settings_as_hash, new_preset.generation_settings_as_hash
    assert_equal @preset.preset_settings_as_hash, new_preset.preset_settings_as_hash
  end

  test "duplicate works for locked preset" do
    assert_difference "Preset.count", 1 do
      post duplicate_settings_preset_url(@locked_preset)
    end

    new_preset = Preset.order(created_at: :desc).first
    assert_nil new_preset.locked_at
  end

  # === Lock Action ===
  test "lock sets locked_at timestamp" do
    assert_nil @preset.locked_at

    post lock_settings_preset_url(@preset)

    assert_redirected_to settings_presets_url
    @preset.reload
    assert_not_nil @preset.locked_at
    assert @preset.locked?
  end

  # === Unlock Action ===
  test "unlock clears locked_at timestamp" do
    assert @locked_preset.locked?

    post unlock_settings_preset_url(@locked_preset)

    assert_redirected_to settings_presets_url
    @locked_preset.reload
    assert_nil @locked_preset.locked_at
    assert_not @locked_preset.locked?
  end

  # === Publish Action ===
  test "publish sets visibility to public" do
    @preset.update_column(:visibility, "private")
    assert @preset.reload.draft?

    post publish_settings_preset_url(@preset)

    assert_redirected_to settings_presets_url
    @preset.reload
    assert_equal "public", @preset.visibility
    assert @preset.published?
  end

  # === Unpublish Action ===
  test "unpublish sets visibility to private" do
    @preset.update_column(:visibility, "public")
    assert @preset.reload.published?

    post unpublish_settings_preset_url(@preset)

    assert_redirected_to settings_presets_url
    @preset.reload
    assert_equal "private", @preset.visibility
    assert @preset.draft?
  end
end
