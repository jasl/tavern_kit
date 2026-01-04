# frozen_string_literal: true

module LLMSettings
  module Providers
    # xAI (Grok) provider settings.
    #
    class XaiProvider
      include LLMSettings::Base

      schema_id "schema://settings/providers/xai"

      define_schema do
        title "xAI Settings"
        description "Provider-specific prompt budget settings for xAI (Grok)."
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

LLMSettings::Registry.register(:xai_provider, LLMSettings::Providers::XaiProvider)
