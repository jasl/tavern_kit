# frozen_string_literal: true

require "test_helper"

class Translation::PromptComponentsTranslatorTest < ActiveSupport::TestCase
  test "translates preset prompts in native mode when enabled" do
    space =
      Spaces::Playground.create!(
        name: "Native Prompt Components Space",
        owner: users(:admin),
        prompt_settings: {
          "i18n" => {
            "mode" => "native",
            "target_lang" => "ja",
            "native_prompt_components" => { "enabled" => true, "preset" => true, "character" => false },
          },
        }
      )

    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 0)
    conversation = space.conversations.create!(title: "Main")

    conversation.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)
    space.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)
    users(:admin).update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)

    result1 =
      Translation::Service::Result.new(
        translated_text: "MAIN_JA",
        cache_hit: false,
        chunks: 1,
        provider_usage: { prompt_tokens: 10, completion_tokens: 5 },
        repairs: 0,
        extractor: { "textarea" => 1 },
        warnings: [],
      )

    result2 =
      Translation::Service::Result.new(
        translated_text: "PHI_JA",
        cache_hit: false,
        chunks: 1,
        provider_usage: { prompt_tokens: 10, completion_tokens: 5 },
        repairs: 0,
        extractor: { "textarea" => 1 },
        warnings: [],
      )

    result3 =
      Translation::Service::Result.new(
        translated_text: "AN_JA",
        cache_hit: false,
        chunks: 1,
        provider_usage: { prompt_tokens: 10, completion_tokens: 5 },
        repairs: 0,
        extractor: { "textarea" => 1 },
        warnings: [],
      )

    Translation::Service.any_instance.expects(:translate!).times(3).returns(result1, result2, result3)

    settings = space.prompt_settings&.i18n
    translator = Translation::PromptComponentsTranslator.new(conversation: conversation, speaker: speaker, settings: settings)

    preset = TavernKit::Preset.new(main_prompt: "MAIN", post_history_instructions: "PHI", authors_note: "AN")
    translated = translator.translate_preset(preset)

    assert_equal "MAIN_JA", translated.main_prompt
    assert_equal "PHI_JA", translated.post_history_instructions
    assert_equal "AN_JA", translated.authors_note

    run = conversation.translation_runs.order(created_at: :desc).first
    assert run, "expected a TranslationRun to be created"
    assert_equal "prompt_component_translation", run.kind
    assert run.succeeded?
    assert_equal "en", run.source_lang
    assert_equal "en", run.internal_lang
    assert_equal "ja", run.target_lang
    assert_equal "preset", run.debug["component"]

    running_events = ConversationEvent.for_conversation(conversation.id).where(event_name: "translation_run.running")
    succeeded_events = ConversationEvent.for_conversation(conversation.id).where(event_name: "translation_run.succeeded")
    assert_equal 1, running_events.count
    assert_equal 1, succeeded_events.count
    assert_equal run.id, succeeded_events.first.payload["translation_run_id"]

    conversation.reload
    space.reload
    users(:admin).reload
    assert_equal 30, conversation.prompt_tokens_total
    assert_equal 15, conversation.completion_tokens_total
    assert_equal 30, space.prompt_tokens_total
    assert_equal 15, space.completion_tokens_total
    assert_equal 30, users(:admin).prompt_tokens_total
    assert_equal 15, users(:admin).completion_tokens_total
  end

  test "does not translate prompt components when disabled" do
    space =
      Spaces::Playground.create!(
        name: "Native Prompt Components Space (Disabled)",
        owner: users(:admin),
        prompt_settings: { "i18n" => { "mode" => "native", "target_lang" => "ja" } }
      )

    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 0)
    conversation = space.conversations.create!(title: "Main")

    Translation::Service.any_instance.expects(:translate!).never

    settings = space.prompt_settings&.i18n
    translator = Translation::PromptComponentsTranslator.new(conversation: conversation, speaker: speaker, settings: settings)

    preset = TavernKit::Preset.new(main_prompt: "MAIN", post_history_instructions: "PHI", authors_note: "AN")
    translated = translator.translate_preset(preset)

    assert_equal preset.main_prompt, translated.main_prompt
    assert_equal 0, conversation.translation_runs.count
  end

  test "translates lore blocks in native mode when enabled" do
    space =
      Spaces::Playground.create!(
        name: "Native Prompt Components Space (Lore)",
        owner: users(:admin),
        prompt_settings: {
          "i18n" => {
            "mode" => "native",
            "target_lang" => "ja",
            "native_prompt_components" => { "enabled" => true, "preset" => false, "character" => false, "lore" => true },
          },
        }
      )

    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 0)
    conversation = space.conversations.create!(title: "Main")

    conversation.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)
    space.update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)
    users(:admin).update_columns(prompt_tokens_total: 0, completion_tokens_total: 0)

    result =
      Translation::Service::Result.new(
        translated_text: "LORE_JA",
        cache_hit: false,
        chunks: 1,
        provider_usage: { prompt_tokens: 10, completion_tokens: 5 },
        repairs: 0,
        extractor: { "textarea" => 1 },
        warnings: [],
      )

    Translation::Service.any_instance.expects(:translate!).once.returns(result)

    settings = space.prompt_settings&.i18n
    translator = Translation::PromptComponentsTranslator.new(conversation: conversation, speaker: speaker, settings: settings)

    blocks = [
      TavernKit::Prompt::Block.new(role: :system, content: "SYS", token_budget_group: :system),
      TavernKit::Prompt::Block.new(
        role: :system,
        content: "LORE",
        slot: :world_info_after_char_defs,
        token_budget_group: :lore,
        metadata: { uid: "uid1", position: :after_char_defs }
      ),
    ]
    plan = TavernKit::Prompt::Plan.new(blocks: blocks)

    translated = translator.translate_plan_lore(plan)

    assert_equal "SYS", translated.blocks[0].content
    assert_equal "LORE_JA", translated.blocks[1].content

    run = conversation.translation_runs.order(created_at: :desc).first
    assert run, "expected a TranslationRun to be created"
    assert_equal "prompt_component_translation", run.kind
    assert run.succeeded?
    assert_equal "lore", run.debug["component"]

    conversation.reload
    space.reload
    users(:admin).reload
    assert_equal 10, conversation.prompt_tokens_total
    assert_equal 5, conversation.completion_tokens_total
    assert_equal 10, space.prompt_tokens_total
    assert_equal 5, space.completion_tokens_total
    assert_equal 10, users(:admin).prompt_tokens_total
    assert_equal 5, users(:admin).completion_tokens_total
  end

  test "does not translate lore blocks when lore toggle is off" do
    space =
      Spaces::Playground.create!(
        name: "Native Prompt Components Space (Lore Off)",
        owner: users(:admin),
        prompt_settings: {
          "i18n" => {
            "mode" => "native",
            "target_lang" => "ja",
            "native_prompt_components" => { "enabled" => true, "preset" => false, "character" => false, "lore" => false },
          },
        }
      )

    speaker = space.space_memberships.create!(kind: "character", role: "member", character: characters(:ready_v2), position: 0)
    conversation = space.conversations.create!(title: "Main")

    Translation::Service.any_instance.expects(:translate!).never

    settings = space.prompt_settings&.i18n
    translator = Translation::PromptComponentsTranslator.new(conversation: conversation, speaker: speaker, settings: settings)

    blocks = [
      TavernKit::Prompt::Block.new(role: :system, content: "SYS", token_budget_group: :system),
      TavernKit::Prompt::Block.new(role: :system, content: "LORE", token_budget_group: :lore),
    ]
    plan = TavernKit::Prompt::Plan.new(blocks: blocks)

    translated = translator.translate_plan_lore(plan)

    assert_equal "LORE", translated.blocks[1].content
    assert_equal 0, conversation.translation_runs.count
  end
end
