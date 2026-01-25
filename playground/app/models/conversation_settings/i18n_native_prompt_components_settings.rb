# frozen_string_literal: true

module ConversationSettings
  class I18nNativePromptComponentsSettings
    include ConversationSettings::Base

    define_schema do
      title "Native Prompt Components"
      description "Optional translation of prompt components when mode=native (improves target-language consistency)."

      property :enabled, T::Boolean,
        default: false,
        description: "Enable translating prompt components to target_lang in native mode."

      property :preset, T::Boolean,
        default: true,
        description: "Translate preset prompts (main_prompt, post_history_instructions, authors_note)."

      property :character, T::Boolean,
        default: false,
        description: "Translate character card fields (description/personality/scenario/etc.)."

      property :lore, T::Boolean,
        default: false,
        description: "Translate activated Lore / World Info snippets (prompt-injected content)."
    end

    def enabled?
      enabled == true
    end

    def preset?
      enabled? && preset == true
    end

    def character?
      enabled? && character == true
    end

    def lore?
      enabled? && lore == true
    end

    define_ui_extensions(
      enabled: { control: "toggle", label: "Enable", group: "Translation", order: 12 },
      preset: { control: "toggle", label: "Translate Preset Prompts", group: "Translation", order: 13 },
      character: { control: "toggle", label: "Translate Character Card", group: "Translation", order: 14 },
      lore: { control: "toggle", label: "Translate Lore/World Info", group: "Translation", order: 15 },
    )
  end
end
