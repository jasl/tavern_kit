# frozen_string_literal: true

module ConversationSettings
  class I18nChunkingSettings
    include ConversationSettings::Base

    define_schema do
      title "Chunking"
      description "Chunking strategy to respect provider limits."

      property :max_chars, Integer,
        default: 1800,
        minimum: 200,
        maximum: 20_000,
        description: "Maximum characters per chunk (MVP)."
    end

    define_ui_extensions(
      max_chars: { control: "number", label: "Max Chars", group: "Translation", order: 20 },
    )
  end
end
