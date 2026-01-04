# frozen_string_literal: true

module LLMSettings
  module Providers
    # DeepSeek provider settings.
    #
    class DeepseekProvider
      include LLMSettings::Base

      schema_id "schema://settings/providers/deepseek"

      define_schema do
        title "DeepSeek Settings"
        description "Provider-specific prompt budget settings for DeepSeek."
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

LLMSettings::Registry.register(:deepseek_provider, LLMSettings::Providers::DeepseekProvider)
