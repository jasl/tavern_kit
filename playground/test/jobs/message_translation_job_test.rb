# frozen_string_literal: true

require "test_helper"

class MessageTranslationJobTest < ActiveJob::TestCase
  test "writes translation to message metadata" do
    message = messages(:ai_response)
    message.conversation.space.update!(prompt_settings: message.conversation.space.prompt_settings.to_h.deep_merge(i18n: { "mode" => "translate_both" }))
    Translation::Metadata.mark_pending!(message, target_lang: "zh-CN")

    conversation = message.conversation
    space = conversation.space
    owner = space.owner

    conversation.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)
    space.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)
    owner.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)

    run =
      TranslationRun.create!(
        conversation: message.conversation,
        message: message,
        kind: "message_translation",
        status: "queued",
        source_lang: "en",
        internal_lang: "en",
        target_lang: "zh-CN",
      )

    Translation::Service.any_instance.stubs(:translate!).returns(
      Translation::Service::Result.new(
        translated_text: "你好！",
        cache_hit: true,
        chunks: 1,
        provider_usage: { prompt_tokens: 100, completion_tokens: 50 },
        warnings: [],
      )
    )

    assert_nil message.metadata.dig("i18n", "translations", "zh-CN", "text")

    MessageTranslationJob.perform_now(run.id)

    message.reload
    assert_equal "你好！", message.metadata.dig("i18n", "translations", "zh-CN", "text")
    assert_nil message.metadata.dig("i18n", "translation_pending", "zh-CN")
    assert_equal "succeeded", run.reload.status

    conversation.reload
    space.reload
    owner.reload
    assert_equal 100, conversation.prompt_tokens_total
    assert_equal 50, conversation.completion_tokens_total
    assert_equal 100, space.prompt_tokens_total
    assert_equal 50, space.completion_tokens_total
    assert_equal 100, owner.prompt_tokens_total
    assert_equal 50, owner.completion_tokens_total

    event_names = ConversationEvent.where(conversation_id: conversation.id).where("event_name LIKE ?", "translation_run.%").pluck(:event_name)
    assert_includes event_names, "translation_run.running"
    assert_includes event_names, "translation_run.succeeded"
  end

  test "persists last_error and clears pending when translation fails" do
    message = messages(:ai_response)
    message.conversation.space.update!(prompt_settings: message.conversation.space.prompt_settings.to_h.deep_merge(i18n: { "mode" => "translate_both" }))
    Translation::Metadata.mark_pending!(message, target_lang: "zh-CN")

    conversation = message.conversation

    run =
      TranslationRun.create!(
        conversation: message.conversation,
        message: message,
        kind: "message_translation",
        status: "queued",
        source_lang: "en",
        internal_lang: "en",
        target_lang: "zh-CN",
      )

    Translation::Service.any_instance.stubs(:translate!).raises(Translation::ProviderError, "boom")

    MessageTranslationJob.perform_now(run.id)

    message.reload
    error = message.metadata.dig("i18n", "last_error")
    assert_equal "translation_failed", error["code"]
    assert_equal "zh-CN", error["target_lang"]
    assert_nil message.metadata.dig("i18n", "translation_pending", "zh-CN")
    assert_equal "failed", run.reload.status

    event_names = ConversationEvent.where(conversation_id: conversation.id).where("event_name LIKE ?", "translation_run.%").pluck(:event_name)
    assert_includes event_names, "translation_run.running"
    assert_includes event_names, "translation_run.failed"
  end

  test "clears pending without translating when target_lang matches internal_lang" do
    message = messages(:ai_response)
    message.conversation.space.update!(
      prompt_settings: message.conversation.space.prompt_settings.to_h.deep_merge(i18n: { "mode" => "translate_both", "target_lang" => "en", "internal_lang" => "en" })
    )
    Translation::Metadata.mark_pending!(message, target_lang: "en")

    run =
      TranslationRun.create!(
        conversation: message.conversation,
        message: message,
        kind: "message_translation",
        status: "queued",
        source_lang: "en",
        internal_lang: "en",
        target_lang: "en",
      )

    Translation::Service.any_instance.expects(:translate!).never

    MessageTranslationJob.perform_now(run.id)

    message.reload
    assert_nil message.metadata.dig("i18n", "translation_pending", "en")
    assert_nil message.metadata.dig("i18n", "translations", "en")
    assert_equal "canceled", run.reload.status
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

    run =
      TranslationRun.create!(
        conversation: message.conversation,
        message: message,
        kind: "message_translation",
        status: "queued",
        source_lang: "en",
        internal_lang: "en",
        target_lang: "zh-CN",
      )

    Translation::Service.any_instance.stubs(:translate!).returns(
      Translation::Service::Result.new(
        translated_text: "你好！",
        cache_hit: true,
        chunks: 1,
        provider_usage: nil,
        warnings: [],
      )
    )

    MessageTranslationJob.perform_now(run.id)

    message.reload
    assert_equal "你好！", message.metadata.dig("i18n", "translations", "zh-CN", "text")
  end

  test "writes translation to swipe metadata when swipe_id is provided" do
    message = messages(:ai_response)
    message.conversation.space.update!(prompt_settings: message.conversation.space.prompt_settings.to_h.deep_merge(i18n: { "mode" => "translate_both" }))
    swipe = message.add_swipe!(content: message.content, metadata: {}, conversation_run_id: nil)
    Translation::Metadata.mark_pending!(swipe, target_lang: "zh-CN")

    run =
      TranslationRun.create!(
        conversation: message.conversation,
        message: message,
        message_swipe: swipe,
        kind: "message_translation",
        status: "queued",
        source_lang: "en",
        internal_lang: "en",
        target_lang: "zh-CN",
      )

    Translation::Service.any_instance.stubs(:translate!).returns(
      Translation::Service::Result.new(
        translated_text: "测试译文",
        cache_hit: true,
        chunks: 1,
        provider_usage: nil,
        warnings: [],
      )
    )

    MessageTranslationJob.perform_now(run.id)

    swipe.reload
    assert_equal "测试译文", swipe.metadata.dig("i18n", "translations", "zh-CN", "text")
    assert_nil swipe.metadata.dig("i18n", "translation_pending", "zh-CN")
  end
end
