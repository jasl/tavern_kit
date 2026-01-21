# frozen_string_literal: true

# Applies a Preset to a SpaceMembership.
#
# This operation touches multiple models (Preset + SpaceMembership + LLMProvider),
# so it belongs in the service layer.
#
module Presets
  class MembershipApplier
    # All known provider identifications from the schema.
    # Used to apply generation settings to all provider paths.
    PROVIDER_IDENTIFICATIONS = %w[
      openai anthropic gemini xai deepseek qwen openai_compatible
    ].freeze

    def self.execute(preset:, membership:, apply_provider: true)
      new(preset: preset, membership: membership, apply_provider: apply_provider).execute
    end

    def initialize(preset:, membership:, apply_provider:)
      @preset = preset
      @membership = membership
      @apply_provider = apply_provider
    end

    def execute
      call
    end

    # @return [SpaceMembership] the updated membership
    def call
      current_settings = @membership.settings
      new_settings =
        if current_settings.respond_to?(:to_h)
          current_settings.to_h.deep_stringify_keys
        else
          (current_settings || {}).deep_dup
        end

      new_settings["llm"] ||= {}
      new_settings["llm"]["providers"] ||= {}

      gen_settings_hash = @preset.generation_settings_as_hash
      preset_settings_hash = @preset.preset_settings_as_hash

      PROVIDER_IDENTIFICATIONS.each do |provider|
        new_settings["llm"]["providers"][provider] ||= {}
        new_settings["llm"]["providers"][provider]["generation"] ||= {}
        new_settings["llm"]["providers"][provider]["generation"].merge!(gen_settings_hash)
      end

      new_settings["preset"] = (new_settings["preset"] || {}).merge(preset_settings_hash)

      attrs = { settings: new_settings, preset_id: @preset.id }
      attrs[:llm_provider_id] = @preset.llm_provider_id if @apply_provider && @preset.has_valid_provider?

      @membership.update!(attrs)
      @membership
    end

    private :call
  end
end
