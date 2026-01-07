# frozen_string_literal: true

module ConversationSettings
  # Defaults that apply to a space (independent of any single conversation).
  #
  class SpaceSettings
    include ConversationSettings::Base

    schema_id "schema://settings/defs/space"
    schema_tab name: "Space", icon: "message-square", order: 2

    define_schema do
      title "Space Settings"
      description "Defaults that apply to a space (independent of any single conversation)."

      property :reply_order_strategy, String,
        default: "natural",
        enum: ["manual", "natural", "list", "pooled"],
        description: "Group chat reply order strategy (ST: Manual/Natural/List/Pooled)."

      property :allow_self_responses, T::Boolean,
        default: false,
        description: "Allow consecutive replies from a character due to self-mentions (ST: Allow Self Responses)."

      property :generation_handling_mode, String,
        default: "swap",
        enum: ["swap", "join_include_muted", "join_exclude_muted"],
        description: "How character definitions are included in context for group chat generation. Join modes merge multiple character cards into one, which can blur personalities and confuse who is speaking."

      property :during_generation_user_input_policy, String,
        default: "queue",
        enum: ["queue", "restart", "reject"],
        description: "What to do when a user sends messages while an AI response is generating."

      property :user_turn_debounce_ms, Integer,
        default: 0,
        minimum: 0,
        maximum: 60000,
        description: "Debounce window before starting a user-triggered generation run. Sending another user message resets the timer (ms)."

      property :auto_mode_enabled, T::Boolean,
        default: false,
        description: "After an AI run succeeds, schedule an auto-mode followup run (AI-to-AI) using reply order strategy."

      property :auto_mode_delay_ms, Integer,
        default: 5000,
        minimum: 0,
        maximum: 60000,
        description: "Delay before an auto-mode followup run starts (ms)."

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
      reply_order_strategy: { control: "select", label: "Reply Order Strategy", order: 1, quick: true },
      allow_self_responses: { control: "toggle", label: "Allow Self Responses", order: 2, quick: true },
      generation_handling_mode: { control: "select", label: "Group Generation Handling", order: 3, quick: true, enumLabels: { "swap" => "Swap", "join_include_muted" => "Join (include muted)", "join_exclude_muted" => "Join (exclude muted)" } },
      during_generation_user_input_policy: { control: "select", label: "User Input While Generating", order: 5, quick: true, enumLabels: { "queue" => "Queue (don't interrupt)", "restart" => "Restart (cancel + regenerate)", "reject" => "Reject (block send)" } },
      user_turn_debounce_ms: { control: "number", label: "User Turn Debounce (ms)", order: 6, quick: false },
      auto_mode_enabled: { control: "toggle", label: "Auto-mode Enabled", order: 7, quick: true },
      auto_mode_delay_ms: { control: "number", label: "Auto-mode Delay (ms)", order: 8, quick: false, visibleWhen: { ref: "auto_mode_enabled", const: true } },
      join_prefix: { control: "textarea", label: "Join Prefix", order: 10, quick: false, rows: 2, visibleWhen: { ref: "generation_handling_mode", in: ["join_include_muted", "join_exclude_muted"] } },
      join_suffix: { control: "textarea", label: "Join Suffix", order: 11, quick: false, rows: 2, visibleWhen: { ref: "generation_handling_mode", in: ["join_include_muted", "join_exclude_muted"] } },
      scenario_override: { control: "textarea", label: "Scenario Override", order: 30, quick: false, rows: 3 },
      preset: { label: "Prompt Preset", order: 35, quick: false },
      world_info: { label: "World Info", order: 40, quick: false },
      memory: { label: "Memory", order: 50, quick: false },
      rag: { label: "RAG / Knowledge Base", order: 60, quick: false },
    )

    define_storage_extensions(
      reply_order_strategy: { model: "Space", attr: "reply_order", kind: "column" },
      allow_self_responses: { model: "Space", attr: "allow_self_responses", kind: "column" },
      generation_handling_mode: { model: "Space", attr: "card_handling_mode", kind: "column", mapping: { "swap" => "swap", "join_include_muted" => "append_disabled", "join_exclude_muted" => "append" } },
      during_generation_user_input_policy: { model: "Space", attr: "during_generation_user_input_policy", kind: "column" },
      user_turn_debounce_ms: { model: "Space", attr: "user_turn_debounce_ms", kind: "column" },
      auto_mode_enabled: { model: "Space", attr: "auto_mode_enabled", kind: "column" },
      auto_mode_delay_ms: { model: "Space", attr: "auto_mode_delay_ms", kind: "column" },
      join_prefix: { model: "Space", attr: "settings", kind: "json", path: ["join_prefix"] },
      join_suffix: { model: "Space", attr: "settings", kind: "json", path: ["join_suffix"] },
      scenario_override: { model: "Space", attr: "settings", kind: "json", path: ["scenario_override"] },
    )
  end
end

ConversationSettings::Registry.register(:space_settings, ConversationSettings::SpaceSettings)
