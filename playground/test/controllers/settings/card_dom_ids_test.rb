# frozen_string_literal: true

require "test_helper"

class Settings::CardDomIdsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :admin

    @preset = Preset.create!(
      name: "DOM ID Test Preset",
      description: "Preset used for DOM id assertions",
      user: users(:admin),
      generation_settings: {
        "temperature" => 0.7,
        "top_p" => 1.0,
        "max_context_tokens" => 1024,
        "max_response_tokens" => 256,
      },
      preset_settings: { "main_prompt" => "Test" }
    )

    @lorebook = Lorebook.create!(
      name: "DOM ID Test Lorebook",
      description: "Lorebook used for DOM id assertions",
      user: users(:admin),
      visibility: "public"
    )

    @invite_code = InviteCode.generate!(created_by: users(:admin), note: "DOM ID Test")
  end

  teardown do
    @preset&.destroy
    @lorebook&.destroy
    @invite_code&.destroy
  end

  test "llm providers index renders stable provider card id" do
    provider = llm_providers(:mock_local)

    get settings_llm_providers_url

    assert_response :success
    assert_select "#provider_#{provider.id}"
  end

  test "presets index renders stable preset card id" do
    get settings_presets_url

    assert_response :success
    assert_select "#preset_#{@preset.id}"
  end

  test "lorebooks index renders stable lorebook card id" do
    get settings_lorebooks_url

    assert_response :success
    assert_select "#lorebook_#{@lorebook.id}"
  end

  test "users index renders stable user card id" do
    user = users(:admin)

    get settings_users_url

    assert_response :success
    assert_select "#user_#{user.id}"
  end

  test "invite codes index renders stable invite code card id" do
    get settings_invite_codes_url

    assert_response :success
    assert_select "#invite_code_#{@invite_code.id}"
  end
end
