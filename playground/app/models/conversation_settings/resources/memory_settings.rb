# frozen_string_literal: true

module ConversationSettings
  module Resources
    # Memory settings (placeholder - not yet implemented).
    #
    class MemorySettings
      include ConversationSettings::Base

      define_schema do
        title "Memory Settings"
        description "Memory injection settings (Risu HypaMemory / ST summary memory)."

        property :enabled, T::Boolean,
          default: false,
          description: "Enable memory injection into prompts."

        property :algorithm, String,
          default: "none",
          enum: ["none", "st_summary", "risu_hypa_v2", "risu_hypa_v3", "risu_hanurai"],
          description: "Memory algorithm / strategy."

        property :memory_budget_percent, Integer,
          default: 10,
          minimum: 0,
          maximum: 50,
          description: "Token budget percent reserved for injected memory content (best-effort)."

        property :summarization_prompt, String,
          default: "",
          description: "Prompt used for summarization / memory refresh."
      end

      define_ui_extensions(
        enabled: { control: "toggle", label: "Enable Memory", quick: false, order: 1, disabled: true },
        algorithm: { control: "select", label: "Algorithm", quick: false, order: 2, disabled: true },
        memory_budget_percent: { control: "slider", label: "Budget (%)", quick: false, order: 3, disabled: true, range: { min: 0, max: 50, step: 1 } },
        summarization_prompt: { control: "textarea", label: "Summarization Prompt", quick: false, order: 4, rows: 4, disabled: true },
      )

      define_storage_extensions(
        enabled: { model: "Space", attr: "settings", kind: "json", path: ["memory", "enabled"] },
        algorithm: { model: "Space", attr: "settings", kind: "json", path: ["memory", "algorithm"] },
        memory_budget_percent: { model: "Space", attr: "settings", kind: "json", path: ["memory", "budget_percent"] },
        summarization_prompt: { model: "Space", attr: "settings", kind: "json", path: ["memory", "summarization_prompt"] },
      )
    end
  end
end

ConversationSettings::Registry.register(:memory_settings, ConversationSettings::Resources::MemorySettings)
