# frozen_string_literal: true

module ConversationSettings
  # Prompt preset settings (mapped into TavernKit::Preset during prompt building).
  #
  class PresetSettings
    include ConversationSettings::Base

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
        default: "[Example Chat]",
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

      property :authors_note_allow_wi_scan, T::Boolean,
        default: false,
        description: "When enabled, World Info entries can trigger from content in Author's Note."

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

    # UI Extensions with tab assignments (matching settings/_form.html.erb structure):
    # - "prompts" tab: Main prompts, utility prompts, additional prompts, and options
    # - "authors_note" tab: Author's Note settings
    # - "more" tab: Advanced settings, formats
    define_ui_extensions(
      # === Prompts tab ===
      # Main Prompts group (same as settings form)
      main_prompt: { control: "textarea", label: "Main Prompt", group: "Main Prompts", order: 1, tab: "prompts", rows: 4 },
      post_history_instructions: { control: "textarea", label: "Post-History Instructions", group: "Main Prompts", order: 2, tab: "prompts", rows: 4 },
      auxiliary_prompt: { control: "textarea", label: "Auxiliary Prompt", group: "Main Prompts", order: 3, tab: "prompts", rows: 2 },
      # Utility Prompts group (same as settings form)
      group_nudge_prompt: { control: "textarea", label: "Group Nudge Prompt", group: "Utility Prompts", order: 10, tab: "prompts", rows: 2 },
      continue_nudge_prompt: { control: "textarea", label: "Continue Nudge Prompt", group: "Utility Prompts", order: 11, tab: "prompts", rows: 2 },
      new_chat_prompt: { control: "textarea", label: "New Chat Prompt", group: "Utility Prompts", order: 12, tab: "prompts", rows: 2 },
      new_group_chat_prompt: { control: "textarea", label: "New Group Chat Prompt", group: "Utility Prompts", order: 13, tab: "prompts", rows: 2 },
      # Additional Prompts group
      enhance_definitions: { control: "textarea", label: "Enhance Definitions", group: "Additional Prompts", order: 20, tab: "prompts", rows: 3 },
      new_example_chat: { control: "text", label: "New Example Chat Separator", group: "Additional Prompts", order: 21, tab: "prompts" },
      # Options group - all toggles together (same as settings form, in Prompts tab)
      prefer_char_prompt: { control: "toggle", label: "Prefer Character System Prompt", group: "Options", order: 30, tab: "prompts" },
      prefer_char_instructions: { control: "toggle", label: "Prefer Character PHI", group: "Options", order: 31, tab: "prompts" },
      squash_system_messages: { control: "toggle", label: "Squash System Messages", group: "Options", order: 32, tab: "prompts" },
      continue_prefill: { control: "toggle", label: "Continue Prefill Mode", group: "Options", order: 33, tab: "prompts" },

      # === Author's Note tab ===
      authors_note: { control: "textarea", label: "Content", group: "Author's Note", order: 1, tab: "authors_note", rows: 4 },
      authors_note_frequency: { control: "number", label: "Frequency", group: "Author's Note", order: 2, tab: "authors_note" },
      authors_note_depth: { control: "number", label: "Depth", group: "Author's Note", order: 3, tab: "authors_note" },
      authors_note_position: { control: "select", label: "Position", group: "Author's Note", order: 4, tab: "authors_note" },
      authors_note_role: { control: "select", label: "Role", group: "Author's Note", order: 5, tab: "authors_note" },
      authors_note_allow_wi_scan: { control: "toggle", label: "Allow WI Scan", group: "Author's Note", order: 6, tab: "authors_note" },

      # === More tab ===
      # Advanced Settings group (same as settings form's Advanced Settings collapse)
      examples_behavior: { control: "select", label: "Examples Behavior", group: "Advanced Settings", order: 1, tab: "more" },
      message_token_overhead: { control: "number", label: "Message Token Overhead", group: "Advanced Settings", order: 2, tab: "more" },
      continue_postfix: { control: "select", label: "Continue Postfix", group: "Advanced Settings", order: 3, tab: "more", enumLabels: { "" => "(empty)", " " => "Space", "\\n" => "Newline", "\\n\\n" => "Double Newline" } },
      replace_empty_message: { control: "text", label: "Replace Empty Message", group: "Advanced Settings", order: 4, tab: "more" },
      # Formats group
      wi_format: { control: "text", label: "World Info Format", group: "Formats", order: 10, tab: "more" },
      scenario_format: { control: "text", label: "Scenario Format", group: "Formats", order: 11, tab: "more" },
      personality_format: { control: "text", label: "Personality Format", group: "Formats", order: 12, tab: "more" },
    )
  end
end

ConversationSettings::Registry.register(:preset_settings, ConversationSettings::PresetSettings)
