# frozen_string_literal: true

module ConversationSettings
  module Providers
    # xAI (Grok) provider settings.
    #
    class XaiProvider
      include ConversationSettings::Base

      schema_id "schema://settings/providers/xai"

      define_schema do
        title "xAI Settings"
        description "Provider-specific prompt budget settings for xAI (Grok)."
      end

      define_nested_schemas(
        generation: "ConversationSettings::LLM::GenerationSettings",
      )

      define_ui_extensions(
        generation: { label: "Generation", quick: true, order: 10 },
      )
    end
  end
end

ConversationSettings::Registry.register(:xai_provider, ConversationSettings::Providers::XaiProvider)
