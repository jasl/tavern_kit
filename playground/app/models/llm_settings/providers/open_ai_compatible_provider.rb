# frozen_string_literal: true

module LLMSettings
  module Providers
    # OpenAI-compatible provider settings.
    #
    class OpenAICompatibleProvider
      include LLMSettings::Base

      schema_id "schema://settings/providers/openai_compatible"

      define_schema do
        title "OpenAI-compatible Settings"
        description "Provider-specific prompt budget settings for OpenAI-compatible APIs."
      end

      define_nested_schemas(
        generation: "LLMSettings::LLM::GenerationSettings",
      )

      define_ui_extensions(
        generation: { label: "Generation", quick: true, order: 10 },
      )
    end
  end
end

LLMSettings::Registry.register(:openai_compatible_provider, LLMSettings::Providers::OpenAICompatibleProvider)
