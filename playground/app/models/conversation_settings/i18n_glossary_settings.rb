# frozen_string_literal: true

module ConversationSettings
  class I18nGlossarySettings
    include ConversationSettings::Base

    define_schema do
      title "Glossary"
      description "Hit-triggered glossary entries injected into translator prompts (JSON textarea)."

      property :enabled, T::Boolean,
        default: true,
        description: "Enable glossary injection."

      property :entries_json, String,
        default: "[]",
        description: "JSON array of glossary entries. Example: [{\"src\":\"Eden\",\"dst\":\"伊甸\"}]."
    end

    define_ui_extensions(
      enabled: { control: "toggle", label: "Enable Glossary", group: "Translation", order: 60 },
      entries_json: { control: "textarea", label: "Glossary Entries (JSON)", group: "Translation", order: 61, rows: 6 },
    )
  end
end
