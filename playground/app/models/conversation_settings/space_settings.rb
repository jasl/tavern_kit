# frozen_string_literal: true

module ConversationSettings
  # Prompt building settings that apply at the Space level.
  #
  # These settings affect how prompts are constructed for all conversations
  # in the space. Non-prompt-building settings (reply_order, auto_mode, etc.)
  # remain as dedicated columns on the Space model.
  #
  class SpaceSettings
    include ConversationSettings::Base

    schema_id "schema://settings/defs/space"

    define_schema do
      title "Space Prompt Settings"
      description "Prompt building settings that apply at the Space level."

      property :generation_handling_mode, String,
        default: "swap",
        enum: ["swap", "join_include_muted", "join_exclude_muted"],
        description: "How character definitions are included in context for group chat generation. Join modes merge multiple character cards into one, which can blur personalities and confuse who is speaking."

      property :join_prefix, String,
        default: "",
        description: "Only used in Join modes. Supports normal macros, plus {{char}} for the current character and <FIELDNAME> for the current field. Join modes can blur personalities; use Swap if you see voice leakage."

      property :join_suffix, String,
        default: "",
        description: "Only used in Join modes. Supports normal macros, plus {{char}} for the current character and <FIELDNAME> for the current field. Join modes can blur personalities; use Swap if you see voice leakage."

      property :scenario_override, T.nilable(String),
        default: nil,
        description: "Overrides scenario text for all group members (ST: Group Chat Scenario Override)."
    end

    # Use string references for lazy loading
    define_nested_schemas(
      preset: "ConversationSettings::PresetSettings",
      world_info: "ConversationSettings::Resources::WorldInfoSettings",
      memory: "ConversationSettings::Resources::MemorySettings",
      rag: "ConversationSettings::Resources::RagSettings",
    )

    define_ui_extensions(
      generation_handling_mode: {
        control: "select",
        label: "Group Generation Handling",
        group: "Generation",
        order: 1,
        enumLabels: {
          "swap" => "Swap",
          "join_include_muted" => "Join (include muted)",
          "join_exclude_muted" => "Join (exclude muted)",
        },
      },
      join_prefix: {
        control: "textarea",
        label: "Join Prefix",
        group: "Generation",
        order: 2,
        rows: 2,
        visibleWhen: { ref: "generation_handling_mode", in: ["join_include_muted", "join_exclude_muted"] },
      },
      join_suffix: {
        control: "textarea",
        label: "Join Suffix",
        group: "Generation",
        order: 3,
        rows: 2,
        visibleWhen: { ref: "generation_handling_mode", in: ["join_include_muted", "join_exclude_muted"] },
      },
      scenario_override: {
        control: "textarea",
        label: "Scenario Override",
        group: "Generation",
        order: 10,
        rows: 3,
      },
      preset: { label: "Prompt Preset", order: 20 },
      world_info: { label: "World Info", order: 30 },
      memory: { label: "Memory", order: 40 },
      rag: { label: "RAG / Knowledge Base", order: 50 },
    )
  end
end

ConversationSettings::Registry.register(:space_settings, ConversationSettings::SpaceSettings)
