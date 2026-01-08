# frozen_string_literal: true

require "test_helper"

class PresetMissingUiTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :admin
  end

  test "conversation page does not crash when no presets exist" do
    Preset.delete_all
    Setting.delete("preset.default_id")

    get conversation_url(conversations(:general_main), target_membership_id: space_memberships(:admin_in_general).id)
    assert_response :success
  end
end
