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

          %{glossary_lines}%{ntl_lines}\
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

          %{glossary_lines}%{ntl_lines}\
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

    def self.resolve(key:, overrides:, repair: false)
      preset = fetch(key)
      return preset if overrides.nil?

      system_prompt =
        if repair
          overrides.respond_to?(:repair_system_prompt) ? overrides.repair_system_prompt.to_s.strip.presence : nil
        else
          overrides.respond_to?(:system_prompt) ? overrides.system_prompt.to_s.strip.presence : nil
        end

      user_prompt_template =
        if repair
          overrides.respond_to?(:repair_user_prompt_template) ? overrides.repair_user_prompt_template.to_s.strip.presence : nil
        else
          overrides.respond_to?(:user_prompt_template) ? overrides.user_prompt_template.to_s.strip.presence : nil
        end

      Preset.new(
        key: preset.key,
        system_prompt: system_prompt || preset.system_prompt,
        user_prompt_template: user_prompt_template || preset.user_prompt_template,
      )
    end

    def self.digest(preset)
      Digest::SHA256.hexdigest("#{preset.system_prompt}\n\n#{preset.user_prompt_template}")
    end

    def self.user_prompt(template:, text:, source_lang:, target_lang:, glossary_lines:, ntl_lines:)
      tpl = template.to_s
      raise PromptTemplateError, "translator user prompt template must include %{text}" unless tpl.include?("%{text}")

      format(
        tpl,
        text: text,
        source_lang: source_lang,
        target_lang: target_lang,
        glossary_lines: glossary_lines.to_s,
        ntl_lines: ntl_lines.to_s,
      )
    rescue KeyError, ArgumentError => e
      raise PromptTemplateError, e.message
    end
  end
end
