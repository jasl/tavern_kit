# frozen_string_literal: true

module SettingsSchemas
  class Extensions
    def initialize(_extensions_dir:)
    end

    # Placeholder hook for future schema overlays.
    #
    # @param bundled_schema [Hash]
    # @return [Hash]
    def apply_extensions(bundled_schema)
      bundled_schema
    end
  end
end
