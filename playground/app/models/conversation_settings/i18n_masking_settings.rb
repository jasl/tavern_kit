# frozen_string_literal: true

module ConversationSettings
  class I18nMaskingSettings
    include ConversationSettings::Base

    define_schema do
      title "Masking"
      description "Format-safe masking rules for roleplay translation."

      property :enabled, T::Boolean,
        default: true,
        description: "Enable masking."

      property :protect_code_blocks, T::Boolean,
        default: true,
        description: "Mask fenced code blocks (```...```)."

      property :protect_inline_code, T::Boolean,
        default: true,
        description: "Mask inline code (`...`)."

      property :protect_urls, T::Boolean,
        default: true,
        description: "Mask URLs."

      property :protect_handlebars, T::Boolean,
        default: true,
        description: "Mask handlebars/macros like {{...}}."
    end

    define_ui_extensions(
      enabled: { control: "toggle", label: "Enable Masking", group: "Translation", order: 40 },
      protect_code_blocks: { control: "toggle", label: "Protect Code Blocks", group: "Translation", order: 41 },
      protect_inline_code: { control: "toggle", label: "Protect Inline Code", group: "Translation", order: 42 },
      protect_urls: { control: "toggle", label: "Protect URLs", group: "Translation", order: 43 },
      protect_handlebars: { control: "toggle", label: "Protect Handlebars", group: "Translation", order: 44 },
    )
  end
end
