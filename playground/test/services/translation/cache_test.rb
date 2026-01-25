# frozen_string_literal: true

require "test_helper"

class Translation::CacheTest < ActiveSupport::TestCase
  test "cache key changes when provider model changes (no model override)" do
    provider = llm_providers(:openai)

    request =
      Translation::Service::Request.new(
        text: "Hello",
        source_lang: "en",
        target_lang: "zh-CN",
        prompt_preset: "strict_roleplay_v1",
        provider: provider,
        model: nil,
        masking: nil,
        chunking: ConversationSettings::I18nChunkingSettings.new({ max_chars: 10_000 }),
        cache: ConversationSettings::I18nCacheSettings.new({ enabled: true, ttl_seconds: 60 }),
      )

    cache = Translation::Cache.new(enabled: true, ttl_seconds: 60)
    key1 = cache.key_for(request: request, masked_text: "hi")

    provider.update!(model: "gpt-4o-mini")
    key2 = cache.key_for(request: request, masked_text: "hi")

    refute_equal key1, key2
  end

  test "cache key changes when provider endpoint changes" do
    provider = llm_providers(:openai)

    request =
      Translation::Service::Request.new(
        text: "Hello",
        source_lang: "en",
        target_lang: "zh-CN",
        prompt_preset: "strict_roleplay_v1",
        provider: provider,
        model: nil,
        masking: nil,
        chunking: ConversationSettings::I18nChunkingSettings.new({ max_chars: 10_000 }),
        cache: ConversationSettings::I18nCacheSettings.new({ enabled: true, ttl_seconds: 60 }),
      )

    cache = Translation::Cache.new(enabled: true, ttl_seconds: 60)
    key1 = cache.key_for(request: request, masked_text: "hi")

    provider.update!(base_url: "https://api.example.com/v1")
    key2 = cache.key_for(request: request, masked_text: "hi")

    refute_equal key1, key2
  end

  class DummyProvider
    attr_reader :endpoint, :model

    def initialize(endpoint:, model:)
      @endpoint = endpoint
      @model = model
    end
  end

  test "cache key includes provider kind to avoid cross-provider collisions" do
    provider = llm_providers(:openai)
    cache = Translation::Cache.new(enabled: true, ttl_seconds: 60)

    llm_request =
      Translation::Service::Request.new(
        text: "Hello",
        source_lang: "en",
        target_lang: "zh-CN",
        prompt_preset: "strict_roleplay_v1",
        provider: provider,
        model: nil,
        masking: nil,
        chunking: ConversationSettings::I18nChunkingSettings.new({ max_chars: 10_000 }),
        cache: ConversationSettings::I18nCacheSettings.new({ enabled: true, ttl_seconds: 60 }),
      )

    external_request =
      Translation::Service::Request.new(
        text: "Hello",
        source_lang: "en",
        target_lang: "zh-CN",
        prompt_preset: "strict_roleplay_v1",
        provider: DummyProvider.new(endpoint: "https://api.example.com", model: "n/a"),
        model: nil,
        masking: nil,
        chunking: ConversationSettings::I18nChunkingSettings.new({ max_chars: 10_000 }),
        cache: ConversationSettings::I18nCacheSettings.new({ enabled: true, ttl_seconds: 60 }),
      )

    key1 = cache.key_for(request: llm_request, masked_text: "hi")
    key2 = cache.key_for(request: external_request, masked_text: "hi")

    refute_equal key1, key2
  end
end
