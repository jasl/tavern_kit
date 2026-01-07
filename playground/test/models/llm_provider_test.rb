# frozen_string_literal: true

require "test_helper"

class LLMProviderTest < ActiveSupport::TestCase
  fixtures :llm_providers

  test "get_default returns nil when no default is set" do
    Setting.delete("llm.default_provider_id")

    assert_nil LLMProvider.get_default
  end

  test "get_default returns nil when stored default_provider_id points to a missing provider" do
    Setting.set("llm.default_provider_id", 999_999)

    assert_nil LLMProvider.get_default
  end

  test "get_default returns the provider when stored default_provider_id points to an enabled provider" do
    provider = llm_providers(:openai)
    Setting.set("llm.default_provider_id", provider.id)

    assert_equal provider, LLMProvider.get_default
  end

  test "get_default returns nil when stored default_provider_id points to a disabled provider" do
    disabled = llm_providers(:openai)
    disabled.update!(disabled: true)
    Setting.set("llm.default_provider_id", disabled.id)

    assert_nil LLMProvider.get_default
  end

  test "get_default returns nil when no enabled providers exist" do
    LLMProvider.update_all(disabled: true)
    Setting.set("llm.default_provider_id", llm_providers(:openai).id)

    assert_nil LLMProvider.get_default
  end
end
