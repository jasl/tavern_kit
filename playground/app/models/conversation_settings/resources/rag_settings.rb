# frozen_string_literal: true

module ConversationSettings
  module Resources
    # RAG / Knowledge Base settings (placeholder - not yet implemented).
    #
    class RagSettings
      include ConversationSettings::Base

      define_schema do
        title "RAG / Knowledge Base Settings"
        description "Retrieval-augmented generation settings."

        property :enabled, T::Boolean,
          default: false,
          description: "Enable retrieval-augmented generation."

        property :top_k, Integer,
          default: 6,
          minimum: 0,
          maximum: 50,
          description: "How many retrieved chunks to inject into context."

        property :min_score, Float,
          default: 0.0,
          minimum: 0.0,
          maximum: 1.0,
          description: "Minimum similarity score threshold (0.0–1.0)."
      end

    define_ui_extensions(
      enabled: { control: "toggle", label: "Enable RAG", quick: false, order: 1, disabled: true },
      top_k: { control: "number", label: "Top K", quick: false, order: 2, disabled: true },
      min_score: { control: "range", label: "Min Score", quick: false, order: 3, disabled: true, range: { min: 0, max: 1, step: 0.01 } },
    )

      # Note: Storage is now handled by EasyTalkCoder serialization on Space.prompt_settings
      # This schema is nested within SpaceSettings as prompt_settings.rag
    end
  end
end

ConversationSettings::Registry.register(:rag_settings, ConversationSettings::Resources::RagSettings)
