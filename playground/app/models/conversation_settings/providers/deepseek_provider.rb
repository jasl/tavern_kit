# frozen_string_literal: true

module ConversationSettings
  module Providers
    # DeepSeek provider settings.
    #
    class DeepseekProvider
      include ConversationSettings::Base

      schema_id "schema://settings/providers/deepseek"

      define_schema do
        title "DeepSeek Settings"
        description "Provider-specific prompt budget settings for DeepSeek."
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

ConversationSettings::Registry.register(:deepseek_provider, ConversationSettings::Providers::DeepseekProvider)
