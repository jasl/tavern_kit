# frozen_string_literal: true

module ConversationSettings
  module Providers
    # Qwen provider settings.
    #
    class QwenProvider
      include ConversationSettings::Base

      schema_id "schema://settings/providers/qwen"

      define_schema do
        title "Qwen Settings"
        description "Provider-specific prompt budget settings for Qwen."
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

ConversationSettings::Registry.register(:qwen_provider, ConversationSettings::Providers::QwenProvider)
