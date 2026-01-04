# frozen_string_literal: true

module LLMSettings
  module Providers
    # Anthropic (Claude) provider settings.
    #
    class AnthropicProvider
      include LLMSettings::Base

      schema_id "schema://settings/providers/anthropic"

      define_schema do
        title "Anthropic Settings"
        description "Provider-specific prompt budget settings for Anthropic (Claude)."
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

LLMSettings::Registry.register(:anthropic_provider, LLMSettings::Providers::AnthropicProvider)
