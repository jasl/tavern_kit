# frozen_string_literal: true

module ConversationSettings
  module Providers
    # Anthropic (Claude) provider settings.
    #
    class AnthropicProvider
      include ConversationSettings::Base

      schema_id "schema://settings/providers/anthropic"

      define_schema do
        title "Anthropic Settings"
        description "Provider-specific prompt budget settings for Anthropic (Claude)."
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

ConversationSettings::Registry.register(:anthropic_provider, ConversationSettings::Providers::AnthropicProvider)
