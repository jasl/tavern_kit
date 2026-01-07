# frozen_string_literal: true

require "test_helper"

class LLMProviderDisabledUiTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :admin
  end

  test "conversation provider selector does not render disabled providers" do
    disabled_provider =
      LLMProvider.create!(
        name: "Disabled UI Provider",
        identification: "openai_compatible",
        base_url: "http://example.test/v1",
        model: "test",
        streamable: true,
        supports_logprobs: false,
        disabled: true,
      )

    get conversation_url(conversations(:general_main))
    assert_response :success

    assert_includes response.body, llm_providers(:openai).name
    assert_not_includes response.body, disabled_provider.name
  end

  test "preset form keeps disabled association without rendering disabled provider" do
    disabled_provider =
      LLMProvider.create!(
        name: "Disabled Preset UI Provider",
        identification: "openai_compatible",
        base_url: "http://example.test/v1",
        model: "test",
        streamable: true,
        supports_logprobs: false,
        disabled: true,
      )

    preset =
      Preset.create!(
        name: "Preset With Disabled Provider",
        llm_provider: disabled_provider,
        generation_settings: ConversationSettings::LLM::GenerationSettings.new,
        preset_settings: ConversationSettings::PresetSettings.new
      )

    get edit_settings_preset_url(preset)
    assert_response :success

    assert_not_includes response.body, disabled_provider.name
    assert_includes response.body, I18n.t("presets.form.disabled_provider_placeholder", default: "— Disabled provider (will use default) —")
    assert_includes response.body,
                    I18n.t(
                      "presets.form.disabled_provider_fallback",
                      default: "This preset is associated with a disabled provider and will fall back to the default provider."
                    )
  end

  test "preset edit page does not crash when its provider was deleted" do
    provider =
      LLMProvider.create!(
        name: "Temporary Provider",
        identification: "openai_compatible",
        base_url: "http://example.test/v1",
        model: "test",
        streamable: true,
        supports_logprobs: false,
        disabled: false,
      )

    preset =
      Preset.create!(
        name: "Preset With Provider",
        llm_provider: provider,
        generation_settings: ConversationSettings::LLM::GenerationSettings.new,
        preset_settings: ConversationSettings::PresetSettings.new
      )

    provider.destroy!
    preset.reload

    get edit_settings_preset_url(preset)
    assert_response :success
  end

  test "conversation page does not crash when no enabled providers exist" do
    LLMProvider.update_all(disabled: true)
    Setting.delete("llm.default_provider_id")

    get conversation_url(conversations(:general_main), target_membership_id: space_memberships(:admin_in_general).id)
    assert_response :success

    assert_includes response.body,
                    I18n.t(
                      "settings.no_provider_warning",
                      default: "No provider configured. Please select one to send messages."
                    )
  end
end
