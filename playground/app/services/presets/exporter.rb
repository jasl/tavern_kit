# frozen_string_literal: true

module Presets
  # Exports a Preset to TavernKit native JSON format.
  #
  # The exported JSON includes all preset settings and can be
  # imported back into TavernKit without loss of data.
  #
  # @example Export a preset
  #   json_data = Presets::Exporter.new.call(preset)
  #   # => '{"tavernkit_preset_version":"1.0","name":"My Preset",...}'
  #
  class Exporter
    # Current export format version
    VERSION = "1.0"

    # Export a preset to JSON string.
    #
    # @param preset [Preset] the preset to export
    # @return [String] JSON string
    def call(preset)
      build_export_hash(preset).to_json
    end

    # Export a preset to a Hash (for testing or further processing).
    #
    # @param preset [Preset] the preset to export
    # @return [Hash] export data
    def to_hash(preset)
      build_export_hash(preset)
    end

    private

    def build_export_hash(preset)
      {
        tavernkit_preset_version: VERSION,
        name: preset.name,
        description: preset.description,
        generation_settings: preset.generation_settings_as_hash,
        preset_settings: preset.preset_settings_as_hash,
        exported_at: Time.current.iso8601,
      }.compact
    end
  end
end
