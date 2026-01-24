# frozen_string_literal: true

module ConversationSettings
  class I18nCacheSettings
    include ConversationSettings::Base

    define_schema do
      title "Cache"
      description "Caching for translation results."

      property :enabled, T::Boolean,
        default: true,
        description: "Enable caching."

      property :ttl_seconds, Integer,
        default: 604_800,
        minimum: 0,
        maximum: 31_536_000,
        description: "Cache TTL in seconds (0 = no expiry)."

      property :scope, String,
        default: "global",
        enum: %w[message conversation global],
        description: "Cache scope (MVP uses Rails.cache; scope is advisory)."
    end

    define_ui_extensions(
      enabled: { control: "toggle", label: "Enable Cache", group: "Translation", order: 30 },
      ttl_seconds: { control: "number", label: "TTL (seconds)", group: "Translation", order: 31 },
      scope: { control: "select", label: "Cache Scope", group: "Translation", order: 32 },
    )
  end
end
