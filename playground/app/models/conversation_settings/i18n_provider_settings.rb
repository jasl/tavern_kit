# frozen_string_literal: true

module ConversationSettings
  class I18nProviderSettings
    include ConversationSettings::Base

    define_schema do
      title "Translation Provider"
      description "Translation provider configuration."

      property :kind, String,
        default: "llm",
        enum: %w[llm],
        description: "Provider kind (MVP: llm only)."

      property :llm_provider_id, T.nilable(Integer),
        default: nil,
        description: "Optional LLMProvider override for translation (nil = use speaker/default provider)."

      property :model_override, T.nilable(String),
        default: nil,
        description: "Optional model override for translation."
    end

    define_ui_extensions(
      llm_provider_id: { control: "select", label: "LLM Provider", group: "Translation", order: 10 },
      model_override: { control: "text", label: "Model Override", group: "Translation", order: 11 },
    )
  end
end
