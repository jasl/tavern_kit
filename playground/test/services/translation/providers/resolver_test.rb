# frozen_string_literal: true

require "test_helper"

class Translation::Providers::ResolverTest < ActiveSupport::TestCase
  test "resolves llm adapter" do
    provider = llm_providers(:openai)

    adapter = Translation::Providers::Resolver.resolve(kind: "llm", provider: provider, model: nil)

    assert_instance_of Translation::Providers::LLM, adapter
  end

  test "raises for unsupported provider kind" do
    provider = llm_providers(:openai)

    assert_raises(Translation::ProviderError) do
      Translation::Providers::Resolver.resolve(kind: "nope", provider: provider, model: nil)
    end
  end

  test "raises when llm kind but provider is not an LLMProvider" do
    assert_raises(Translation::ProviderError) do
      Translation::Providers::Resolver.resolve(kind: "llm", provider: Object.new, model: nil)
    end
  end
end
