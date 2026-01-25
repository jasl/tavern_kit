# frozen_string_literal: true

module ConversationSettings
  class I18nTranslatorPromptsSettings
    include ConversationSettings::Base

    define_schema do
      title "Translator Prompts (Overrides)"
      description "Optional prompt overrides for the translator (primary + repair). Blank = use preset defaults."

      property :system_prompt, T.nilable(String),
        default: nil,
        description: "Override system prompt for primary translation."

      property :user_prompt_template, T.nilable(String),
        default: nil,
        description: "Override user prompt template for primary translation. Must include %{text}."

      property :repair_system_prompt, T.nilable(String),
        default: nil,
        description: "Override system prompt for repair translation."

      property :repair_user_prompt_template, T.nilable(String),
        default: nil,
        description: "Override user prompt template for repair translation. Must include %{text}."
    end

    define_ui_extensions(
      system_prompt: { control: "textarea", label: "System Prompt (Primary)", group: "Translation", order: 80, rows: 6 },
      user_prompt_template: { control: "textarea", label: "User Prompt Template (Primary)", group: "Translation", order: 81, rows: 6 },
      repair_system_prompt: { control: "textarea", label: "System Prompt (Repair)", group: "Translation", order: 82, rows: 6 },
      repair_user_prompt_template: { control: "textarea", label: "User Prompt Template (Repair)", group: "Translation", order: 83, rows: 6 },
    )
  end
end
