# frozen_string_literal: true

require "test_helper"

class PresetTest < ActiveSupport::TestCase
  fixtures :llm_providers

  test "get_default returns nil when unset or invalid" do
    Preset.delete_all
    Setting.delete("preset.default_id")

    assert_nil Preset.get_default

    Setting.set("preset.default_id", "999999")
    assert_nil Preset.get_default
  end

  test "get_default returns the configured preset when present" do
    preset =
      Preset.create!(
        name: "Configured Default Preset",
        generation_settings: ConversationSettings::LLM::GenerationSettings.new,
        preset_settings: ConversationSettings::PresetSettings.new
      )

    Preset.set_default!(preset)
    assert_equal preset, Preset.get_default
  end

  test "has_valid_provider? returns false and falls back when provider is disabled" do
    default_provider = llm_providers(:mock_local)
    Setting.set("llm.default_provider_id", default_provider.id)

    disabled_provider =
      LLMProvider.create!(
        name: "Disabled Preset Provider",
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

    assert_not preset.has_valid_provider?
    assert_equal default_provider, preset.effective_llm_provider
  end

  test "has_valid_provider? returns true when provider is enabled" do
    provider = llm_providers(:openai)

    preset =
      Preset.create!(
        name: "Preset With Provider",
        llm_provider: provider,
        generation_settings: ConversationSettings::LLM::GenerationSettings.new,
        preset_settings: ConversationSettings::PresetSettings.new
      )

    assert preset.has_valid_provider?
    assert_equal provider, preset.effective_llm_provider
  end
end
