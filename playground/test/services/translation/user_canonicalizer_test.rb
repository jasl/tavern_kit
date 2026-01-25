# frozen_string_literal: true

require "test_helper"

class Translation::UserCanonicalizerTest < ActiveSupport::TestCase
  test "stores canonical text for user messages in prompt window" do
    space =
      Spaces::Playground.create!(
        name: "I18n Space",
        owner: users(:admin),
        prompt_settings: { "i18n" => { "mode" => "translate_both" } }
      )
    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")

    message = conversation.messages.create!(space_membership: user_membership, role: "user", content: "你好")

    conversation.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)
    space.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)
    users(:admin).update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)

    result =
      Translation::Service::Result.new(
        translated_text: "Hello",
        cache_hit: false,
        chunks: 1,
        provider_usage: { prompt_tokens: 100, completion_tokens: 50 },
        warnings: [],
      )

    Translation::Service.any_instance.expects(:translate!).once.returns(result)

    settings = space.prompt_settings&.i18n
    history_scope = conversation.messages.ordered.with_participant

    updated =
      Translation::UserCanonicalizer
        .new(conversation: conversation, speaker: speaker, history_scope: history_scope, settings: settings)
        .ensure_canonical_for_prompt!

    assert_equal 1, updated

    canonical = message.reload.metadata&.dig("i18n", "canonical")
    assert_equal "Hello", canonical&.dig("text")
    assert_equal "en", canonical&.dig("internal_lang")
    assert canonical&.dig("input_sha256").present?
    assert canonical&.dig("settings_sha256").present?

    conversation.reload
    space.reload
    users(:admin).reload
    assert_equal 100, conversation.prompt_tokens_total
    assert_equal 50, conversation.completion_tokens_total
    assert_equal 100, space.prompt_tokens_total
    assert_equal 50, space.completion_tokens_total
    assert_equal 100, users(:admin).prompt_tokens_total
    assert_equal 50, users(:admin).completion_tokens_total
  end

  test "retranslates when user message content changes" do
    space =
      Spaces::Playground.create!(
        name: "I18n Space (Retx)",
        owner: users(:admin),
        prompt_settings: { "i18n" => { "mode" => "translate_both" } }
      )
    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")

    message = conversation.messages.create!(space_membership: user_membership, role: "user", content: "你好")

    result1 =
      Translation::Service::Result.new(
        translated_text: "Hello",
        cache_hit: false,
        chunks: 1,
        provider_usage: nil,
        warnings: [],
      )

    result2 =
      Translation::Service::Result.new(
        translated_text: "Goodbye",
        cache_hit: false,
        chunks: 1,
        provider_usage: nil,
        warnings: [],
      )

    Translation::Service.any_instance.expects(:translate!).twice.returns(result1, result2)

    settings = space.prompt_settings&.i18n
    history_scope = conversation.messages.ordered.with_participant

    Translation::UserCanonicalizer
      .new(conversation: conversation, speaker: speaker, history_scope: history_scope, settings: settings)
      .ensure_canonical_for_prompt!

    canonical = message.reload.metadata&.dig("i18n", "canonical")
    assert_equal "Hello", canonical&.dig("text")

    message.update!(content: "再见")

    Translation::UserCanonicalizer
      .new(conversation: conversation, speaker: speaker, history_scope: history_scope, settings: settings)
      .ensure_canonical_for_prompt!

    canonical = message.reload.metadata&.dig("i18n", "canonical")
    assert_equal "Goodbye", canonical&.dig("text")
  end

  test "does not translate when text is already likely internal language" do
    space =
      Spaces::Playground.create!(
        name: "I18n Space (English)",
        owner: users(:admin),
        prompt_settings: { "i18n" => { "mode" => "translate_both" } }
      )
    user_membership = space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin), position: 0)
    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 1)
    conversation = space.conversations.create!(title: "Main")

    conversation.messages.create!(space_membership: user_membership, role: "user", content: "Hello world")

    Translation::Service.any_instance.expects(:translate!).never

    settings = space.prompt_settings&.i18n
    history_scope = conversation.messages.ordered.with_participant

    updated =
      Translation::UserCanonicalizer
        .new(conversation: conversation, speaker: speaker, history_scope: history_scope, settings: settings)
        .ensure_canonical_for_prompt!

    assert_equal 0, updated
  end
end
