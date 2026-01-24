# frozen_string_literal: true

require "test_helper"

class Conversations::FirstMessagesCreatorTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    clear_enqueued_jobs
  end

  test "enqueues translation for first_mes when translate_both is enabled" do
    space = spaces(:general)
    space.update!(prompt_settings: space.prompt_settings.to_h.deep_merge(i18n: { "mode" => "translate_both" }))

    conversation = space.conversations.create!(title: "First Messages")

    created = nil
    assert_enqueued_jobs 1, only: MessageTranslationJob do
      created = Conversations::FirstMessagesCreator.execute(conversation: conversation)
    end

    message = created.first
    assert_equal true, message.reload.metadata.dig("i18n", "translation_pending", space.prompt_settings.i18n.target_lang)
  ensure
    conversation&.destroy!
  end

  test "does not enqueue translation when mode is off" do
    space = spaces(:general)
    space.update!(prompt_settings: space.prompt_settings.to_h.deep_merge(i18n: { "mode" => "off" }))

    conversation = space.conversations.create!(title: "First Messages (No Translation)")

    created = nil
    assert_enqueued_jobs 0, only: MessageTranslationJob do
      created = Conversations::FirstMessagesCreator.execute(conversation: conversation)
    end

    message = created.first
    assert_nil message.reload.metadata.dig("i18n", "translation_pending")
  ensure
    conversation&.destroy!
  end
end
