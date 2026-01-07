# frozen_string_literal: true

module ConversationSettings
  # Root settings schema for TavernKit Playground.
  #
  # This is the entry point for the settings schema pack.
  # It composes all top-level settings schemas.
  #
  class RootSchema
    include ConversationSettings::Base

    schema_id "schema://settings/root"

    define_schema do
      title "TavernKit Playground Settings Schema (v0.6)"
      description "Root settings schema for TavernKit Playground."

      property :version, String,
        default: "0.6.0",
        # Author the pattern as a JS regex literal (JSON Schema/ECMA-262) and convert
        # it to a Ruby-safe pattern for validations.
        pattern: ConversationSettings.js_regex_literal_to_ruby_pattern("/^\\d+\\.\\d+\\.\\d+(-[0-9A-Za-z.-]+)?$/"),
        description: "Schema Version"
    end

    # Use string references for lazy loading
    define_nested_schemas(
      space: "ConversationSettings::SpaceSettings",
      participant: "ConversationSettings::ParticipantSettings",
      character: "ConversationSettings::CharacterSettings",
    )

    define_ui_extensions(
      version: { label: "Schema Version", control: "text", quick: false, order: 0 },
    )
  end
end

ConversationSettings::Registry.register(:root_schema, ConversationSettings::RootSchema)
