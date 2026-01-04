# frozen_string_literal: true

module LLMSettings
  # Root settings schema for TavernKit Playground.
  #
  # This is the entry point for the settings schema pack.
  # It composes all top-level settings schemas.
  #
  class RootSchema
    include LLMSettings::Base

    schema_id "schema://settings/root"

    define_schema do
      title "TavernKit Playground Settings Schema (v0.6)"
      description "Root settings schema for TavernKit Playground."

      property :version, String,
        default: "0.6.0",
        pattern: "\\A\\d+\\.\\d+\\.\\d+(-[0-9A-Za-z.-]+)?\\z",
        description: "Schema Version"
    end

    # Use string references for lazy loading
    define_nested_schemas(
      space: "LLMSettings::SpaceSettings",
      participant: "LLMSettings::ParticipantSettings",
      character: "LLMSettings::CharacterSettings",
    )

    define_ui_extensions(
      version: { label: "Schema Version", control: "text", quick: false, order: 0 },
    )
  end
end

LLMSettings::Registry.register(:root_schema, LLMSettings::RootSchema)
