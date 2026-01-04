# frozen_string_literal: true

module LLMSettings
  # Prompt preset settings (mapped into TavernKit::Preset during prompt building).
  #
  class PresetSettings
    include LLMSettings::Base

    schema_id "schema://settings/defs/preset"

    define_schema do
      title "Prompt Preset"
      description "Space-level prompt preset settings (mapped into TavernKit::Preset during prompt building)."

      # Main prompts
      property :main_prompt, String,
        default: "Write {{char}}'s next reply in a fictional chat between {{charIfNotGroup}} and {{user}}.",
        description: "Main Prompt (system)."

      property :post_history_instructions, String,
        default: "",
        description: "Post-History Instructions (PHI)."

      property :group_nudge_prompt, String,
        default: "[Write the next reply only as {{char}}.]",
        description: "Group nudge prompt (appended near history in group chats)."

      property :continue_nudge_prompt, String,
        default: "[Continue your last message without repeating its original content.]",
        description: "Continue nudge prompt (used by Continue generation type)."

      # Utility prompts
      property :new_chat_prompt, String,
        default: "[Start a new Chat]",
        description: "Optional system prompt inserted before chat history (ST: new_chat_prompt). Leave blank to disable."

      property :new_group_chat_prompt, String,
        default: "[Start a new group chat. Group members: {{group}}]",
        description: "Optional system prompt inserted before chat history in group chats (ST: new_group_chat_prompt). Leave blank to disable."

      property :new_example_chat, String,
        default: "",
        description: "Optional system separator inserted before each example dialogue block (ST: new_example_chat_prompt). Leave blank to disable."

      property :replace_empty_message, String,
        default: "",
        description: "If set, replaces an empty user message with this content (ST: send_if_empty). Leave blank to keep empty messages."

      # Continue mode
      property :continue_prefill, T::Boolean,
        default: false,
        description: "If enabled, Continue uses prefill mode (append continue_postfix to last assistant message) instead of adding a nudge prompt."

      property :continue_postfix, String,
        default: " ",
        enum: ["", " ", "\\n", "\\n\\n"],
        description: "Postfix appended to the last assistant message when Continue Prefill Mode is enabled."

      # Additional prompts
      property :enhance_definitions, String,
        default: "If you have more knowledge of {{char}}, add to the character's lore and personality to enhance them but keep the Character Sheet's definitions absolute.",
        description: "Enhance Definitions prompt content (pinned entry, disabled by default in ST)."

      property :auxiliary_prompt, String,
        default: "",
        description: "Auxiliary prompt content (pinned entry, ST: auxiliaryPrompt / nsfw)."

      # Character overrides
      property :prefer_char_prompt, T::Boolean,
        default: true,
        description: "Prefer character card system prompt when present."

      property :prefer_char_instructions, T::Boolean,
        default: true,
        description: "Prefer character card post-history instructions when present."

      # Output
      property :squash_system_messages, T::Boolean,
        default: false,
        description: "If enabled, squash multiple system messages into one when exporting messages."

      # Trimming
      property :examples_behavior, String,
        default: "gradually_push_out",
        enum: ["gradually_push_out", "always_keep", "disabled"],
        description: "How example dialogue blocks behave during trimming."

      property :message_token_overhead, Integer,
        default: 4,
        minimum: 0,
        maximum: 100,
        description: "Per-message token overhead used for rough trimming estimation."

      # Author's Note
      property :authors_note, String,
        default: "",
        description: "Author's Note content."

      property :authors_note_frequency, Integer,
        default: 1,
        minimum: 0,
        maximum: 100,
        description: "0 = never, 1 = always, N = every Nth message."

      property :authors_note_position, String,
        default: "in_chat",
        enum: ["in_chat", "in_prompt", "before_prompt"],
        description: "Where to insert the Author's Note."

      property :authors_note_depth, Integer,
        default: 4,
        minimum: 0,
        maximum: 1000,
        description: "Depth for in-chat insertion (ST-like semantics)."

      property :authors_note_role, String,
        default: "system",
        enum: ["system", "user", "assistant"],
        description: "Role used when inserting the Author's Note."

      # Formats
      property :wi_format, String,
        default: "{0}",
        description: "World Info formatting template."

      property :scenario_format, String,
        default: "{{scenario}}",
        description: "Scenario formatting template."

      property :personality_format, String,
        default: "{{personality}}",
        description: "Personality formatting template."
    end

    define_ui_extensions(
      main_prompt: { control: "textarea", label: "Main Prompt", group: "Prompts", order: 1, quick: true, rows: 4 },
      post_history_instructions: { control: "textarea", label: "Post-History Instructions", group: "Prompts", order: 2, quick: false, rows: 4 },
      group_nudge_prompt: { control: "textarea", label: "Group Nudge Prompt", group: "Prompts", order: 3, quick: false, rows: 2 },
      continue_nudge_prompt: { control: "textarea", label: "Continue Nudge Prompt", group: "Prompts", order: 4, quick: false, rows: 2 },
      new_chat_prompt: { control: "textarea", label: "New Chat Prompt", group: "Utility Prompts", order: 5, quick: false, rows: 2 },
      new_group_chat_prompt: { control: "textarea", label: "New Group Chat Prompt", group: "Utility Prompts", order: 6, quick: false, rows: 2 },
      new_example_chat: { control: "text", label: "New Example Chat Separator", group: "Utility Prompts", order: 7, quick: false },
      replace_empty_message: { control: "text", label: "Replace Empty User Message", group: "Utility Prompts", order: 8, quick: false },
      continue_prefill: { control: "toggle", label: "Continue Prefill Mode", group: "Continue", order: 9, quick: false },
      continue_postfix: { control: "select", label: "Continue Postfix", group: "Continue", order: 10, quick: false, enumLabels: { "" => "(empty)", " " => "Space", "\\n" => "Newline", "\\n\\n" => "Double Newline" } },
      enhance_definitions: { control: "textarea", label: "Enhance Definitions", group: "Prompts", order: 12, quick: false, rows: 3 },
      auxiliary_prompt: { control: "textarea", label: "Auxiliary Prompt", group: "Prompts", order: 13, quick: false, rows: 2 },
      prefer_char_prompt: { control: "toggle", label: "Prefer Character System Prompt", group: "Character Overrides", order: 10, quick: false },
      prefer_char_instructions: { control: "toggle", label: "Prefer Character PHI", group: "Character Overrides", order: 11, quick: false },
      squash_system_messages: { control: "toggle", label: "Squash System Messages", group: "Output", order: 20, quick: false },
      examples_behavior: { control: "select", label: "Examples Behavior", group: "Trimming", order: 30, quick: false },
      message_token_overhead: { control: "number", label: "Message Token Overhead", group: "Trimming", order: 31, quick: false },
      authors_note: { control: "textarea", label: "Author's Note", group: "Author's Note", order: 40, quick: false, rows: 3 },
      authors_note_frequency: { control: "number", label: "Frequency", group: "Author's Note", order: 41, quick: false },
      authors_note_position: { control: "select", label: "Position", group: "Author's Note", order: 42, quick: false },
      authors_note_depth: { control: "number", label: "Depth", group: "Author's Note", order: 43, quick: false },
      authors_note_role: { control: "select", label: "Role", group: "Author's Note", order: 44, quick: false },
      wi_format: { control: "text", label: "World Info Format", group: "Formats", order: 50, quick: false },
      scenario_format: { control: "text", label: "Scenario Format", group: "Formats", order: 51, quick: false },
      personality_format: { control: "text", label: "Personality Format", group: "Formats", order: 52, quick: false },
    )

    define_storage_extensions(
      main_prompt: { model: "Space", attr: "settings", kind: "json", path: ["preset", "main_prompt"] },
      post_history_instructions: { model: "Space", attr: "settings", kind: "json", path: ["preset", "post_history_instructions"] },
      group_nudge_prompt: { model: "Space", attr: "settings", kind: "json", path: ["preset", "group_nudge_prompt"] },
      continue_nudge_prompt: { model: "Space", attr: "settings", kind: "json", path: ["preset", "continue_nudge_prompt"] },
      new_chat_prompt: { model: "Space", attr: "settings", kind: "json", path: ["preset", "new_chat_prompt"] },
      new_group_chat_prompt: { model: "Space", attr: "settings", kind: "json", path: ["preset", "new_group_chat_prompt"] },
      new_example_chat: { model: "Space", attr: "settings", kind: "json", path: ["preset", "new_example_chat"] },
      replace_empty_message: { model: "Space", attr: "settings", kind: "json", path: ["preset", "replace_empty_message"] },
      continue_prefill: { model: "Space", attr: "settings", kind: "json", path: ["preset", "continue_prefill"] },
      continue_postfix: { model: "Space", attr: "settings", kind: "json", path: ["preset", "continue_postfix"] },
      enhance_definitions: { model: "Space", attr: "settings", kind: "json", path: ["preset", "enhance_definitions"] },
      auxiliary_prompt: { model: "Space", attr: "settings", kind: "json", path: ["preset", "auxiliary_prompt"] },
      prefer_char_prompt: { model: "Space", attr: "settings", kind: "json", path: ["preset", "prefer_char_prompt"] },
      prefer_char_instructions: { model: "Space", attr: "settings", kind: "json", path: ["preset", "prefer_char_instructions"] },
      squash_system_messages: { model: "Space", attr: "settings", kind: "json", path: ["preset", "squash_system_messages"] },
      examples_behavior: { model: "Space", attr: "settings", kind: "json", path: ["preset", "examples_behavior"] },
      message_token_overhead: { model: "Space", attr: "settings", kind: "json", path: ["preset", "message_token_overhead"] },
      authors_note: { model: "Space", attr: "settings", kind: "json", path: ["preset", "authors_note"] },
      authors_note_frequency: { model: "Space", attr: "settings", kind: "json", path: ["preset", "authors_note_frequency"] },
      authors_note_position: { model: "Space", attr: "settings", kind: "json", path: ["preset", "authors_note_position"] },
      authors_note_depth: { model: "Space", attr: "settings", kind: "json", path: ["preset", "authors_note_depth"] },
      authors_note_role: { model: "Space", attr: "settings", kind: "json", path: ["preset", "authors_note_role"] },
      wi_format: { model: "Space", attr: "settings", kind: "json", path: ["preset", "wi_format"] },
      scenario_format: { model: "Space", attr: "settings", kind: "json", path: ["preset", "scenario_format"] },
      personality_format: { model: "Space", attr: "settings", kind: "json", path: ["preset", "personality_format"] },
    )
  end
end

LLMSettings::Registry.register(:preset_settings, LLMSettings::PresetSettings)
