# frozen_string_literal: true

module LLMSettings
  module Providers
    # OpenAI provider settings.
    #
    class OpenAIProvider
      include LLMSettings::Base

      schema_id "schema://settings/providers/openai"

      define_schema do
        title "OpenAI Settings"
        description "Provider-specific prompt budget settings for OpenAI."
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

LLMSettings::Registry.register(:openai_provider, LLMSettings::Providers::OpenAIProvider)
