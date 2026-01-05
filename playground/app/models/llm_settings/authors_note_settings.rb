# frozen_string_literal: true

module LLMSettings
  # Author's Note settings for Character and SpaceMembership.
  #
  # This schema defines the Author's Note configuration that can be set at:
  # - Character level (default for the character)
  # - SpaceMembership level (per-space override)
  #
  # The settings form a priority chain:
  # Conversation.authors_note > SpaceMembership > Character > Space.settings.preset
  #
  class AuthorsNoteSettings
    include LLMSettings::Base

    schema_id "schema://settings/defs/authors_note"

    # Position options for character AN relative to space AN
    CHARACTER_AN_POSITIONS = %w[replace before after].freeze

    define_schema do
      title "Author's Note Settings"
      description "Character or participant-level Author's Note settings."

      # Main content
      property :authors_note, String,
        default: "",
        description: "Author's Note content."

      # Insertion settings
      property :authors_note_position, String,
        default: "in_chat",
        enum: %w[in_chat in_prompt before_prompt],
        description: "Where to insert the Author's Note."

      property :authors_note_depth, Integer,
        default: 4,
        minimum: 0,
        maximum: 1000,
        description: "Depth for in-chat insertion (0 = end of chat)."

      property :authors_note_role, String,
        default: "system",
        enum: %w[system user assistant],
        description: "Role used when inserting the Author's Note."

      # Enable/disable (like ST's useChara)
      property :use_character_authors_note, T::Boolean,
        default: false,
        description: "Enable this character's Author's Note."

      # Position relative to space AN (for combining character AN with space AN)
      property :character_authors_note_position, String,
        default: "replace",
        enum: CHARACTER_AN_POSITIONS,
        description: "How to combine with space-level AN: replace, prepend (before), or append (after)."
    end

    define_ui_extensions(
      authors_note: {
        control: "textarea",
        label: "Author's Note",
        group: "Author's Note",
        order: 1,
        quick: false,
        rows: 4,
      },
      authors_note_position: {
        control: "select",
        label: "Position",
        group: "Author's Note",
        order: 2,
        quick: false,
      },
      authors_note_depth: {
        control: "number",
        label: "Depth",
        group: "Author's Note",
        order: 3,
        quick: false,
      },
      authors_note_role: {
        control: "select",
        label: "Role",
        group: "Author's Note",
        order: 4,
        quick: false,
      },
      use_character_authors_note: {
        control: "toggle",
        label: "Enable Character Author's Note",
        group: "Author's Note",
        order: 5,
        quick: false,
      },
      character_authors_note_position: {
        control: "select",
        label: "Combine Mode",
        group: "Author's Note",
        order: 6,
        quick: false,
        enumLabels: {
          "replace" => "Replace space AN",
          "before" => "Prepend to space AN",
          "after" => "Append to space AN",
        },
      }
    )

    define_storage_extensions(
      authors_note: { model: "Character", attr: "authors_note_settings", kind: "json", path: ["authors_note"] },
      authors_note_position: { model: "Character", attr: "authors_note_settings", kind: "json", path: ["authors_note_position"] },
      authors_note_depth: { model: "Character", attr: "authors_note_settings", kind: "json", path: ["authors_note_depth"] },
      authors_note_role: { model: "Character", attr: "authors_note_settings", kind: "json", path: ["authors_note_role"] },
      use_character_authors_note: { model: "Character", attr: "authors_note_settings", kind: "json", path: ["use_character_authors_note"] },
      character_authors_note_position: { model: "Character", attr: "authors_note_settings", kind: "json", path: ["character_authors_note_position"] }
    )
  end
end

LLMSettings::Registry.register(:authors_note_settings, LLMSettings::AuthorsNoteSettings)
