# frozen_string_literal: true

module ConversationSettings
  class I18nNtlSettings
    include ConversationSettings::Base

    define_schema do
      title "Do Not Translate"
      description "Hit-triggered do-not-translate rules injected into translator prompts (JSON textarea)."

      property :enabled, T::Boolean,
        default: true,
        description: "Enable do-not-translate injection."

      property :entries_json, String,
        default: "[]",
        description: "JSON array of NTL entries. Example: [{\"text\":\"{{user}}\"},{\"kind\":\"regex\",\"pattern\":\"\\\\b[A-Z]{2,}\\\\b\"}]."
    end

    define_ui_extensions(
      enabled: { control: "toggle", label: "Enable Do Not Translate", group: "Translation", order: 62 },
      entries_json: { control: "textarea", label: "NTL Entries (JSON)", group: "Translation", order: 63, rows: 6 },
    )
  end
end
