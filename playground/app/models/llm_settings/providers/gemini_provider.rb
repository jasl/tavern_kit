# frozen_string_literal: true

module LLMSettings
  module Providers
    # Gemini provider settings.
    #
    class GeminiProvider
      include LLMSettings::Base

      schema_id "schema://settings/providers/gemini"

      define_schema do
        title "Gemini Settings"
        description "Provider-specific prompt budget settings for Gemini."
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

LLMSettings::Registry.register(:gemini_provider, LLMSettings::Providers::GeminiProvider)
