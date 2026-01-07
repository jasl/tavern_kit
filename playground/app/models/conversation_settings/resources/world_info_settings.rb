# frozen_string_literal: true

module ConversationSettings
  module Resources
    # World Info settings that influence prompt building.
    #
    class WorldInfoSettings
      include ConversationSettings::Base

      define_schema do
        title "World Info Settings"
        description "World Info / Lorebook settings that influence prompt building."

        property :depth, Integer,
          default: 2,
          minimum: 0,
          maximum: 1000,
          description: "How many past messages are scanned for World Info triggers (ST: world_info_depth)."

        property :budget_percent, Integer,
          default: 25,
          minimum: 1,
          maximum: 100,
          description: "World Info token budget as a percentage of context window (ST: world_info_budget)."

        property :budget_cap_tokens, Integer,
          default: 0,
          minimum: 0,
          maximum: 200_000,
          description: "Optional hard cap in tokens for World Info budget (0 = no cap) (ST: world_info_budget_cap)."

        property :include_names, T::Boolean,
          default: true,
          description: "Include entry names in injected text (ST: world_info_include_names)."

        property :match_whole_words, T::Boolean,
          default: true,
          description: "Match whole words only (ST: world_info_match_whole_words)."

        property :case_sensitive, T::Boolean,
          default: false,
          description: "Case-sensitive matching (ST: world_info_case_sensitive)."

        property :recursive, T::Boolean,
          default: true,
          description: "Allow recursive activation scans (ST: world_info_recursive)."

        property :max_recursion_steps, Integer,
          default: 3,
          minimum: 0,
          maximum: 10,
          description: "Maximum recursion steps (0 = disable recursion)."

        property :insertion_strategy, String,
          default: "character_lore_first",
          enum: ["sorted_evenly", "character_lore_first", "global_lore_first"],
          description: "How to order entries when inserting (ST: world_info_character_strategy)."

        property :use_group_scoring, T::Boolean,
          default: false,
          description: "Use group scoring for activations (ST: world_info_use_group_scoring)."

        property :min_activations, Integer,
          default: 0,
          minimum: 0,
          maximum: 1000,
          description: "If > 0, keep scanning until at least N entries activate (ST: world_info_min_activations)."

        property :min_activations_depth_max, Integer,
          default: 0,
          minimum: 0,
          maximum: 1000,
          description: "Max depth to scan when min activations is enabled (0 = unlimited) (ST: world_info_min_activations_depth_max)."
      end

      define_ui_extensions(
        depth: { control: "slider", label: "Scan Depth", quick: true, order: 1, range: { min: 0, max: 50, step: 1 }, madLabRange: { min: 0, max: 1000, step: 1 } },
        budget_percent: { control: "slider", label: "Budget (%)", quick: true, order: 2, range: { min: 1, max: 60, step: 1 }, madLabRange: { min: 1, max: 100, step: 1 } },
        budget_cap_tokens: { control: "number", label: "Budget Cap (tokens)", quick: false, order: 3 },
        include_names: { control: "toggle", label: "Include Names", quick: false, order: 4 },
        match_whole_words: { control: "toggle", label: "Match Whole Words", quick: false, order: 5 },
        case_sensitive: { control: "toggle", label: "Case Sensitive", quick: false, order: 6 },
        recursive: { control: "toggle", label: "Recursive Scan", quick: false, order: 7 },
        max_recursion_steps: { control: "number", label: "Max Recursion Steps", quick: false, order: 8 },
        insertion_strategy: { control: "select", label: "Insertion Strategy", quick: false, order: 9 },
        use_group_scoring: { control: "toggle", label: "Use Group Scoring", quick: false, order: 10 },
        min_activations: { control: "number", label: "Min Activations", quick: false, order: 11 },
        min_activations_depth_max: { control: "number", label: "Min Activations Depth Max", quick: false, order: 12 },
      )

      define_storage_extensions(
        depth: { model: "Space", attr: "settings", kind: "json", path: ["world_info_depth"] },
        budget_percent: { model: "Space", attr: "settings", kind: "json", path: ["world_info_budget"] },
        budget_cap_tokens: { model: "Space", attr: "settings", kind: "json", path: ["world_info_budget_cap"] },
        include_names: { model: "Space", attr: "settings", kind: "json", path: ["world_info_include_names"] },
        match_whole_words: { model: "Space", attr: "settings", kind: "json", path: ["world_info_match_whole_words"] },
        case_sensitive: { model: "Space", attr: "settings", kind: "json", path: ["world_info_case_sensitive"] },
        recursive: { model: "Space", attr: "settings", kind: "json", path: ["world_info_recursive"] },
        max_recursion_steps: { model: "Space", attr: "settings", kind: "json", path: ["world_info_max_recursion_steps"] },
        insertion_strategy: { model: "Space", attr: "settings", kind: "json", path: ["world_info_insertion_strategy"] },
        use_group_scoring: { model: "Space", attr: "settings", kind: "json", path: ["world_info_use_group_scoring"] },
        min_activations: { model: "Space", attr: "settings", kind: "json", path: ["world_info_min_activations"] },
        min_activations_depth_max: { model: "Space", attr: "settings", kind: "json", path: ["world_info_min_activations_depth_max"] },
      )
    end
  end
end

ConversationSettings::Registry.register(:world_info_settings, ConversationSettings::Resources::WorldInfoSettings)
