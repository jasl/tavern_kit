# frozen_string_literal: true

module ConversationSettings
  module Providers
    # Gemini provider settings.
    #
    class GeminiProvider
      include ConversationSettings::Base

      schema_id "schema://settings/providers/gemini"

      define_schema do
        title "Gemini Settings"
        description "Provider-specific prompt budget settings for Gemini."
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

ConversationSettings::Registry.register(:gemini_provider, ConversationSettings::Providers::GeminiProvider)
