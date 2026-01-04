# frozen_string_literal: true

module LLMSettings
  # Per-space participant settings.
  # Active provider is derived from participant.llm_provider_id;
  # provider-specific blocks are gated by UI context.
  #
  class ParticipantSettings
    include LLMSettings::Base

    # Inner class for providers grouping - defined first since it's referenced by LlmSettings
    class ProvidersSettings
      include LLMSettings::Base

      define_schema do
        title "Provider Settings"
        description "Provider-specific settings."
      end

      # Use string references for lazy loading
      define_nested_schemas(
        openai: "LLMSettings::Providers::OpenAIProvider",
        anthropic: "LLMSettings::Providers::AnthropicProvider",
        gemini: "LLMSettings::Providers::GeminiProvider",
        xai: "LLMSettings::Providers::XaiProvider",
        deepseek: "LLMSettings::Providers::DeepseekProvider",
        qwen: "LLMSettings::Providers::QwenProvider",
        openai_compatible: "LLMSettings::Providers::OpenAICompatibleProvider",
      )

      define_ui_extensions(
        openai: { label: "OpenAI", provider: "openai", order: 1, visibleWhen: { context: "provider_identification", const: "openai" } },
        anthropic: { label: "Claude", provider: "anthropic", order: 2, visibleWhen: { context: "provider_identification", const: "anthropic" } },
        gemini: { label: "Gemini", provider: "gemini", order: 3, visibleWhen: { context: "provider_identification", const: "gemini" } },
        xai: { label: "Grok", provider: "xai", order: 4, visibleWhen: { context: "provider_identification", const: "xai" } },
        deepseek: { label: "DeepSeek", provider: "deepseek", order: 5, visibleWhen: { context: "provider_identification", const: "deepseek" } },
        qwen: { label: "Qwen", provider: "qwen", order: 6, visibleWhen: { context: "provider_identification", const: "qwen" } },
        openai_compatible: { label: "OpenAI-compatible", provider: "openai_compatible", order: 7, visibleWhen: { context: "provider_identification", const: "openai_compatible" } },
      )
    end

    # Inner class for LLM settings grouping
    class LlmSettings
      include LLMSettings::Base

      define_schema do
        title "LLM Settings"
        description "LLM provider settings for this participant."
      end

      define_nested_schemas(
        providers: ProvidersSettings,
      )

      define_ui_extensions(
        providers: { control: "group", label: "Provider Settings", order: 2, quick: true },
      )
    end

    schema_id "schema://settings/defs/participant"
    schema_tab name: "Participant", icon: "bot", order: 3

    define_schema do
      title "Participant Settings"
      description "Per-space participant settings. Active provider is derived from participant.llm_provider_id; provider-specific blocks are gated by UI context."
    end

    # LLM providers nested under llm.providers
    define_nested_schemas(
      llm: LlmSettings,
    )

    define_ui_extensions(
      llm: { control: "group", label: "LLM", order: 1, quick: true },
    )
  end
end

LLMSettings::Registry.register(:participant_settings, LLMSettings::ParticipantSettings)
