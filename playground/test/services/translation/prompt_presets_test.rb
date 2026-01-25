# frozen_string_literal: true

require "test_helper"

class Translation::PromptPresetsTest < ActiveSupport::TestCase
  test "resolves preset with optional overrides" do
    overrides =
      ConversationSettings::I18nTranslatorPromptsSettings.new(
        system_prompt: "SYS",
        user_prompt_template: "X <textarea>%{text}</textarea>",
        repair_system_prompt: "RSYS",
        repair_user_prompt_template: "R <textarea>%{text}</textarea>",
      )

    primary = Translation::PromptPresets.resolve(key: "strict_roleplay_v1", overrides: overrides)
    assert_equal "SYS", primary.system_prompt
    assert_includes primary.user_prompt_template, "<textarea>%{text}</textarea>"

    repair = Translation::PromptPresets.resolve(key: "repair_roleplay_v1", overrides: overrides, repair: true)
    assert_equal "RSYS", repair.system_prompt
    assert_includes repair.user_prompt_template, "R <textarea>%{text}</textarea>"
  end

  test "user prompt template must include %{text}" do
    error =
      assert_raises(Translation::PromptTemplateError) do
        Translation::PromptPresets.user_prompt(
          template: "no text here",
          text: "Hello",
          source_lang: "en",
          target_lang: "zh-CN",
          glossary_lines: "",
          ntl_lines: "",
        )
      end

    assert_includes error.message, "%{text}"
  end

  test "user prompt formatting supports lexicon placeholders" do
    prompt =
      Translation::PromptPresets.user_prompt(
        template: "%{glossary_lines}%{ntl_lines}<textarea>%{text}</textarea>",
        text: "Hello",
        source_lang: "en",
        target_lang: "zh-CN",
        glossary_lines: "Glossary:\n- Eden => 伊甸\n\n",
        ntl_lines: "Do not translate:\n- LLM\n\n",
      )

    assert_includes prompt, "Eden => 伊甸"
    assert_includes prompt, "Do not translate"
    assert_includes prompt, "<textarea>Hello</textarea>"
  end
end
