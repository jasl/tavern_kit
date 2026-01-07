# frozen_string_literal: true

module ConversationSettings
  # Character card fields that influence prompt building (stored in Character#data).
  #
  class CharacterSettings
    include ConversationSettings::Base

    schema_id "schema://settings/defs/character"
    schema_tab name: "Character", icon: "user", order: 4

    define_schema do
      title "Character Settings"
      description "Character card fields that influence prompt building (stored in Character#data)."
      additional_properties true

      # Basics
      property :name, String,
        default: "",
        description: "Character name"

      # Profile
      property :description, String,
        default: "",
        description: "Character description"

      property :personality, String,
        default: "",
        description: "Personality text"

      property :scenario, String,
        default: "",
        description: "Scenario/context"

      # Conversation
      property :first_mes, String,
        default: "",
        description: "Greeting shown as the first message"

      property :alternate_greetings, T::Array[String],
        max_items: 16,
        description: "Alternative greetings (used when greeting_index > 0)"

      property :mes_example, String,
        default: "",
        description: "Example dialogue (ST: mes_example)"

      # Prompts
      property :system_prompt, String,
        default: "",
        description: "Optional system prompt override"

      property :post_history_instructions, String,
        default: "",
        description: "Optional post-history instructions override"

      property :depth_prompt, String,
        default: "",
        description: "Optional depth prompt (macro: {{charDepthPrompt}})"

      # Notes
      property :creator_notes, String,
        default: "",
        description: "Free-form notes (macro: {{creatorNotes}})"
    end

    define_ui_extensions(
      name: { control: "text", label: "Name", group: "Basics", order: 1, quick: true },
      description: { control: "textarea", label: "Description", group: "Profile", order: 10, quick: false, rows: 4 },
      personality: { control: "textarea", label: "Personality", group: "Profile", order: 11, quick: false, rows: 4 },
      scenario: { control: "textarea", label: "Scenario", group: "Profile", order: 12, quick: false, rows: 3 },
      first_mes: { control: "textarea", label: "First Message", group: "Conversation", order: 20, quick: true, rows: 5 },
      alternate_greetings: { control: "tags", label: "Alternate Greetings", group: "Conversation", order: 21, quick: false },
      mes_example: { control: "textarea", label: "Example Dialogue", group: "Conversation", order: 22, quick: false, rows: 6 },
      system_prompt: { control: "textarea", label: "System Prompt", group: "Prompts", order: 30, quick: false, rows: 6 },
      post_history_instructions: { control: "textarea", label: "Post-History Instructions", group: "Prompts", order: 31, quick: false, rows: 4 },
      depth_prompt: { control: "textarea", label: "Depth Prompt", group: "Prompts", order: 32, quick: false, rows: 4 },
      creator_notes: { control: "textarea", label: "Creator Notes", group: "Notes", order: 40, quick: false, rows: 4 },
    )
  end
end

ConversationSettings::Registry.register(:character_settings, ConversationSettings::CharacterSettings)
