# frozen_string_literal: true

require "test_helper"

class Translation::ServiceTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "translates and preserves tokens" do
    masking = ConversationSettings::I18nMaskingSettings.new({})
    chunking = ConversationSettings::I18nChunkingSettings.new({ max_chars: 10_000 })
    cache = ConversationSettings::I18nCacheSettings.new({ enabled: true, ttl_seconds: 60 })
    provider = llm_providers(:openai)

    text = "Hello {{user}}!\nVisit https://example.com"
    masked = Translation::Masker.new(masking: masking).mask(text)
    raw = "<textarea>#{masked.text}</textarea>"

    Translation::Providers::LLM.any_instance.expects(:translate!).once.returns([raw, nil])

    request =
      Translation::Service::Request.new(
        text: text,
        source_lang: "en",
        target_lang: "zh-CN",
        prompt_preset: "strict_roleplay_v1",
        provider_kind: "llm",
        provider: provider,
        model: nil,
        masking: masking,
        chunking: chunking,
        cache: cache,
        glossary: nil,
        ntl: nil,
        prompt_overrides: nil,
      )

    service = Translation::Service.new

    result1 = service.translate!(request)
    assert_equal text, result1.translated_text
    assert_equal false, result1.cache_hit
  end

  test "hits cache on subsequent calls" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)

    masking = ConversationSettings::I18nMaskingSettings.new({})
    chunking = ConversationSettings::I18nChunkingSettings.new({ max_chars: 10_000 })
    cache = ConversationSettings::I18nCacheSettings.new({ enabled: true, ttl_seconds: 60 })
    provider = llm_providers(:openai)

    text = "Hello {{user}}!\nVisit https://example.com"
    masked = Translation::Masker.new(masking: masking).mask(text)
    raw = "<textarea>#{masked.text}</textarea>"

    Translation::Providers::LLM.any_instance.expects(:translate!).once.returns([raw, nil])

    request =
      Translation::Service::Request.new(
        text: text,
        source_lang: "en",
        target_lang: "zh-CN",
        prompt_preset: "strict_roleplay_v1",
        provider_kind: "llm",
        provider: provider,
        model: nil,
        masking: masking,
        chunking: chunking,
        cache: cache,
        glossary: nil,
        ntl: nil,
        prompt_overrides: nil,
      )

    service = Translation::Service.new

    result1 = service.translate!(request)
    assert_equal false, result1.cache_hit
    assert_equal text, result1.translated_text

    result2 = service.translate!(request)
    assert_equal true, result2.cache_hit
    assert_equal text, result2.translated_text
  end

  test "glossary cache key only depends on hit entries" do
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)

    masking = ConversationSettings::I18nMaskingSettings.new({})
    chunking = ConversationSettings::I18nChunkingSettings.new({ max_chars: 10_000 })
    cache = ConversationSettings::I18nCacheSettings.new({ enabled: true, ttl_seconds: 60 })
    provider = llm_providers(:openai)

    glossary =
      ConversationSettings::I18nGlossarySettings.new(
        enabled: true,
        entries_json: [{ src: "Eden", dst: "伊甸" }].to_json
      )

    text = "Welcome to Eden."
    raw = "<textarea>#{text}</textarea>"

    Translation::Providers::LLM.any_instance.expects(:translate!).once.returns([raw, nil])

    request1 =
      Translation::Service::Request.new(
        text: text,
        source_lang: "en",
        target_lang: "zh-CN",
        prompt_preset: "strict_roleplay_v1",
        provider_kind: "llm",
        provider: provider,
        model: nil,
        masking: masking,
        chunking: chunking,
        cache: cache,
        glossary: glossary,
        ntl: nil,
        prompt_overrides: nil,
      )

    request2 =
      Translation::Service::Request.new(
        **request1.to_h.merge(
          glossary: ConversationSettings::I18nGlossarySettings.new(
            enabled: true,
            entries_json: [
              { src: "Eden", dst: "伊甸" },
              { src: "Nope", dst: "不会命中" },
            ].to_json
          )
        )
      )

    service = Translation::Service.new

    result1 = service.translate!(request1)
    assert_equal false, result1.cache_hit

    result2 = service.translate!(request2)
    assert_equal true, result2.cache_hit
    assert_equal text, result2.translated_text
  end

  test "repairs when provider output violates contract" do
    masking = ConversationSettings::I18nMaskingSettings.new({})
    chunking = ConversationSettings::I18nChunkingSettings.new({ max_chars: 10_000 })
    cache = ConversationSettings::I18nCacheSettings.new({ enabled: false })
    provider = llm_providers(:openai)

    text = "Hello {{user}}!"
    masked = Translation::Masker.new(masking: masking).mask(text)

    bad = "no textarea here"
    repaired = "<textarea>#{masked.text}</textarea>"

    Translation::Providers::LLM.any_instance.expects(:translate!).twice.returns([bad, nil], [repaired, nil])

    request =
      Translation::Service::Request.new(
        text: text,
        source_lang: "en",
        target_lang: "zh-CN",
        prompt_preset: "strict_roleplay_v1",
        provider_kind: "llm",
        provider: provider,
        model: nil,
        masking: masking,
        chunking: chunking,
        cache: cache,
        glossary: nil,
        ntl: nil,
        prompt_overrides: nil,
      )

    result = Translation::Service.new.translate!(request)
    assert_equal text, result.translated_text
    assert_includes result.warnings.join("\n"), "token mismatch"
  end

  test "aggregates provider usage across chunks" do
    masking = ConversationSettings::I18nMaskingSettings.new({})
    chunking = ConversationSettings::I18nChunkingSettings.new({ max_chars: 6 })
    cache = ConversationSettings::I18nCacheSettings.new({ enabled: false })
    provider = llm_providers(:openai)

    Translation::Providers::LLM.any_instance.expects(:translate!).twice.returns(
      ["<textarea>AAA</textarea>", { prompt_tokens: 10, completion_tokens: 1 }],
      ["<textarea>BBB</textarea>", { prompt_tokens: 7, completion_tokens: 3 }]
    )

    request =
      Translation::Service::Request.new(
        text: "Hello world",
        source_lang: "en",
        target_lang: "zh-CN",
        prompt_preset: "strict_roleplay_v1",
        provider_kind: "llm",
        provider: provider,
        model: nil,
        masking: masking,
        chunking: chunking,
        cache: cache,
        glossary: nil,
        ntl: nil,
        prompt_overrides: nil,
      )

    result = Translation::Service.new.translate!(request)

    assert_equal "AAABBB", result.translated_text
    assert_equal false, result.cache_hit
    assert_equal 2, result.chunks
    assert_equal({ prompt_tokens: 17, completion_tokens: 4 }, result.provider_usage)
  end

  test "raises for unsupported provider kind" do
    masking = ConversationSettings::I18nMaskingSettings.new({})
    chunking = ConversationSettings::I18nChunkingSettings.new({ max_chars: 10_000 })
    cache = ConversationSettings::I18nCacheSettings.new({ enabled: false })
    provider = llm_providers(:openai)

    request =
      Translation::Service::Request.new(
        text: "Hello",
        source_lang: "en",
        target_lang: "zh-CN",
        prompt_preset: "strict_roleplay_v1",
        provider_kind: "nope",
        provider: provider,
        model: nil,
        masking: masking,
        chunking: chunking,
        cache: cache,
        glossary: nil,
        ntl: nil,
        prompt_overrides: nil,
      )

    assert_raises(Translation::ProviderError) do
      Translation::Service.new.translate!(request)
    end
  end
end
