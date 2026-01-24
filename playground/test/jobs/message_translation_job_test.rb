# frozen_string_literal: true

require "test_helper"

class MessageTranslationJobTest < ActiveJob::TestCase
  test "writes translation to message metadata" do
    message = messages(:ai_response)
    message.conversation.space.update!(prompt_settings: message.conversation.space.prompt_settings.to_h.deep_merge(i18n: { "mode" => "translate_both" }))
    Translation::Metadata.mark_pending!(message, target_lang: "zh-CN")

    Translation::Service.any_instance.stubs(:translate!).returns(
      Translation::Service::Result.new(
        translated_text: "你好！",
        cache_hit: true,
        chunks: 1,
        provider_usage: nil,
        warnings: [],
      )
    )

    assert_nil message.metadata.dig("i18n", "translations", "zh-CN", "text")

    MessageTranslationJob.perform_now(message.id)

    message.reload
    assert_equal "你好！", message.metadata.dig("i18n", "translations", "zh-CN", "text")
    assert_nil message.metadata.dig("i18n", "translation_pending", "zh-CN")
  end

  test "clears pending without translating when target_lang matches internal_lang" do
    message = messages(:ai_response)
    message.conversation.space.update!(
      prompt_settings: message.conversation.space.prompt_settings.to_h.deep_merge(i18n: { "mode" => "translate_both", "target_lang" => "en", "internal_lang" => "en" })
    )
    Translation::Metadata.mark_pending!(message, target_lang: "en")

    Translation::Service.any_instance.expects(:translate!).never

    MessageTranslationJob.perform_now(message.id)

    message.reload
    assert_nil message.metadata.dig("i18n", "translation_pending", "en")
    assert_nil message.metadata.dig("i18n", "translations", "en")
  end

  test "falls back to enabled provider when membership provider is disabled" do
    message = messages(:ai_response)

    disabled_provider = message.space_membership.llm_provider
    disabled_provider.update!(disabled: true)

    fallback_provider = llm_providers(:mock_local)
    fallback_provider.update!(disabled: false)
    LLMProvider.set_default!(fallback_provider)

    message.conversation.space.update!(prompt_settings: message.conversation.space.prompt_settings.to_h.deep_merge(i18n: { "mode" => "translate_both" }))
    Translation::Metadata.mark_pending!(message, target_lang: "zh-CN")

    Translation::Service.any_instance.stubs(:translate!).returns(
      Translation::Service::Result.new(
        translated_text: "你好！",
        cache_hit: true,
        chunks: 1,
        provider_usage: nil,
        warnings: [],
      )
    )

    MessageTranslationJob.perform_now(message.id)

    message.reload
    assert_equal "你好！", message.metadata.dig("i18n", "translations", "zh-CN", "text")
  end

  test "writes translation to swipe metadata when swipe_id is provided" do
    message = messages(:ai_response)
    message.conversation.space.update!(prompt_settings: message.conversation.space.prompt_settings.to_h.deep_merge(i18n: { "mode" => "translate_both" }))
    swipe = message.add_swipe!(content: message.content, metadata: {}, conversation_run_id: nil)
    Translation::Metadata.mark_pending!(swipe, target_lang: "zh-CN")

    Translation::Service.any_instance.stubs(:translate!).returns(
      Translation::Service::Result.new(
        translated_text: "测试译文",
        cache_hit: true,
        chunks: 1,
        provider_usage: nil,
        warnings: [],
      )
    )

    MessageTranslationJob.perform_now(message.id, swipe_id: swipe.id)

    swipe.reload
    assert_equal "测试译文", swipe.metadata.dig("i18n", "translations", "zh-CN", "text")
    assert_nil swipe.metadata.dig("i18n", "translation_pending", "zh-CN")
  end
end
