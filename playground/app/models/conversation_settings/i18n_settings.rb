# frozen_string_literal: true

module ConversationSettings
  # Translation / language settings for a Space (conversation-level behavior).
  #
  # This is intentionally scoped to prompt-building and message display concerns,
  # aligning with SillyTavern-style "Chat Translation" semantics.
  #
  class I18nSettings
    include ConversationSettings::Base

    define_schema do
      title "Language & Translation"
      description "Translation settings for conversations in this Space."

      property :mode, String,
        default: "off",
        enum: %w[off translate_both native hybrid],
        description: "Translation mode: off, translate_both (ST-style), native (model speaks target language), hybrid (auto)."

      property :internal_lang, String,
        default: "en",
        description: "Internal language used for canonical prompt text (MVP default: en)."

      property :target_lang, String,
        default: "zh-CN",
        description: "UI display language (translation target)."

      property :source_lang, String,
        default: "auto",
        enum: %w[auto en zh-CN zh-TW ja ko],
        description: "Source language hint for translation (MVP: auto)."

      property :prompt_preset, String,
        default: "strict_roleplay_v1",
        description: "Translator prompt preset key."
    end

    def translate_both?
      mode.to_s == "translate_both"
    end

    def translation_needed?
      return false unless translate_both?

      internal = internal_lang.to_s
      target = target_lang.to_s

      internal.present? && target.present? && internal != target
    end

    define_nested_schemas(
      provider: "ConversationSettings::I18nProviderSettings",
      chunking: "ConversationSettings::I18nChunkingSettings",
      cache: "ConversationSettings::I18nCacheSettings",
      masking: "ConversationSettings::I18nMaskingSettings",
    )

    define_ui_extensions(
      mode: { control: "select", label: "Mode", group: "Translation", order: 1 },
      target_lang: { control: "select", label: "Target Language", group: "Translation", order: 2 },
      provider: { label: "Provider", group: "Translation", order: 3 },
      chunking: { label: "Chunking", group: "Translation", order: 4 },
      cache: { label: "Cache", group: "Translation", order: 5 },
      masking: { label: "Masking", group: "Translation", order: 6 },
    )
  end
end

ConversationSettings::Registry.register(:i18n_settings, ConversationSettings::I18nSettings)
