# frozen_string_literal: true

module Translation
  class PromptPresets
    Preset = Data.define(:key, :system_prompt, :user_prompt_template)

    STRICT_ROLEPLAY_V1 =
      Preset.new(
        key: "strict_roleplay_v1",
        system_prompt: <<~SYSTEM.strip,
          You are a translation engine for chat roleplay text.

          Rules:
          - Translate the provided text into the target language.
          - Preserve formatting exactly (newlines, indentation, Markdown).
          - Preserve all MASK tokens exactly, e.g. ⟦MASK_0⟧ (do not change, remove, or add any).
          - Output ONLY a single <textarea>...</textarea> block, with the translated text inside.
        SYSTEM
        user_prompt_template: <<~USER.strip,
          Target language: %{target_lang}
          Source language: %{source_lang}

          <textarea>%{text}</textarea>
        USER
      )

    REPAIR_ROLEPLAY_V1 =
      Preset.new(
        key: "repair_roleplay_v1",
        system_prompt: <<~SYSTEM.strip,
          You are a translation repair engine.

          Rules:
          - Do NOT change any MASK tokens like ⟦MASK_0⟧.
          - Do NOT change line breaks or paragraph structure.
          - Output ONLY a single <textarea>...</textarea> block.
        SYSTEM
        user_prompt_template: <<~USER.strip,
          Target language: %{target_lang}

          <textarea>%{text}</textarea>
        USER
      )

    PRESETS = {
      STRICT_ROLEPLAY_V1.key => STRICT_ROLEPLAY_V1,
      REPAIR_ROLEPLAY_V1.key => REPAIR_ROLEPLAY_V1,
    }.freeze

    def self.fetch(key)
      PRESETS.fetch(key.to_s) { PRESETS.fetch(STRICT_ROLEPLAY_V1.key) }
    end

    def self.user_prompt(key:, text:, source_lang:, target_lang:)
      preset = fetch(key)
      format(preset.user_prompt_template, text: text, source_lang: source_lang, target_lang: target_lang)
    end
  end
end
