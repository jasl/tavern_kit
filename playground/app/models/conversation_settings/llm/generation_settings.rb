# frozen_string_literal: true

module ConversationSettings
  module LLM
    # Generation settings for LLM prompt budgeting and sampling parameters.
    #
    class GenerationSettings
      include ConversationSettings::Base

      define_schema do
        title "Generation Settings"
        description "LLM generation parameters for prompt budgeting and sampling."

        property :max_context_tokens, Integer,
          default: 8192,
          minimum: 256,
          maximum: 200_000,
          description: "Context window token limit used for prompt trimming."

        property :max_response_tokens, Integer,
          default: 512,
          minimum: 1,
          maximum: 8192,
          description: "Reserved tokens for the model's response (reduces available prompt budget)."

        property :temperature, Float,
          default: 1.0,
          minimum: 0,
          maximum: 2,
          description: "Controls randomness in generation. Lower values make output more focused and deterministic."

        property :top_p, Float,
          default: 1.0,
          minimum: 0,
          maximum: 1,
          description: "Nucleus sampling threshold. Only tokens with cumulative probability up to this value are considered."

        property :top_k, Integer,
          default: 0,
          minimum: 0,
          maximum: 100,
          description: "Limits sampling to the top K most likely tokens. 0 means no limit."

        property :repetition_penalty, Float,
          default: 1.0,
          minimum: 1,
          maximum: 2,
          description: "Penalizes repeated tokens. Values above 1.0 reduce repetition."
      end

    define_ui_extensions(
      max_context_tokens: {
        label: "Max Context (tokens)",
        control: "number",
        tab: "basic",
        order: 1,
      },
      max_response_tokens: {
        label: "Reserved Response (tokens)",
        control: "number",
        tab: "basic",
        order: 2,
      },
      temperature: {
        label: "Temperature",
        control: "slider",
        tab: "basic",
        order: 3,
        range: { min: 0, max: 2, step: 0.01 },
      },
      top_p: {
        label: "Top P",
        control: "slider",
        tab: "basic",
        order: 4,
        range: { min: 0, max: 1, step: 0.01 },
      },
      top_k: {
        label: "Top K",
        control: "number",
        tab: "basic",
        order: 5,
      },
      repetition_penalty: {
        label: "Repetition Penalty",
        control: "slider",
        tab: "basic",
        order: 6,
        range: { min: 1, max: 2, step: 0.01 },
      },
    )
    end
  end
end

ConversationSettings::Registry.register(:generation_settings, ConversationSettings::LLM::GenerationSettings)
