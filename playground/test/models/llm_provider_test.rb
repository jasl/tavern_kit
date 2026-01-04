# frozen_string_literal: true

require "test_helper"

class LLMProviderTest < ActiveSupport::TestCase
  fixtures :llm_providers

  test "get_default persists a deterministic fallback when no default is set" do
    Setting.delete("llm.default_provider_id")

    provider = LLMProvider.get_default
    assert provider, "Expected get_default to return a provider when providers exist"

    assert_equal provider.id.to_s, Setting.get("llm.default_provider_id").to_s
  end

  test "get_default repairs a stored default_provider_id that points to a missing provider" do
    Setting.set("llm.default_provider_id", 999_999)

    provider = LLMProvider.get_default
    assert provider, "Expected get_default to pick a fallback provider"

    assert_equal provider.id.to_s, Setting.get("llm.default_provider_id").to_s
  end

  test "get_default seeds presets and sets a default when providers table is empty" do
    SpaceMembership.update_all(llm_provider_id: nil)
    LLMProvider.delete_all
    Setting.delete("llm.default_provider_id")

    provider = LLMProvider.get_default
    assert provider, "Expected get_default to seed presets and return a provider"
    assert_equal "OpenAI", provider.name

    assert_equal provider.id.to_s, Setting.get("llm.default_provider_id").to_s
  end
end
