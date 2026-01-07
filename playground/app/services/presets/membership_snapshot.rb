# frozen_string_literal: true

# Builds Preset attributes from a SpaceMembership's current settings.
#
# This is used by:
# - Preset.create_from_membership
# - Preset#update_from_membership
#
module Presets
  class MembershipSnapshot
    def self.build(membership:)
      new(membership: membership).build
    end

    def initialize(membership:)
      @membership = membership
    end

    # @return [Hash] attributes suitable for Preset.create/update
    def build
      settings = @membership.settings
      settings_hash = settings.respond_to?(:to_h) ? settings.to_h.deep_stringify_keys : (settings || {})

      generation_settings_data = extract_generation_settings(settings_hash)

      preset_settings_data =
        if settings.respond_to?(:preset)
          ps = settings.preset
          ps.respond_to?(:to_h) ? ps.to_h.deep_stringify_keys : (ps || {})
        else
          settings_hash["preset"] || {}
        end

      {
        llm_provider_id: @membership.llm_provider_id,
        generation_settings: generation_settings_data,
        preset_settings: preset_settings_data,
      }
    end

    private

    # Extract generation settings from a membership's settings.
    # Looks under the current provider's path first, falls back to first available provider.
    #
    # @param settings_hash [Hash] the settings hash (string keys)
    # @return [Hash] generation settings
    def extract_generation_settings(settings_hash)
      providers = settings_hash.dig("llm", "providers") || {}

      # Try current provider first
      current_provider = @membership.provider_identification
      if current_provider && providers.dig(current_provider, "generation").present?
        return providers.dig(current_provider, "generation").slice(
          "max_context_tokens", "max_response_tokens", "temperature",
          "top_p", "top_k", "repetition_penalty"
        )
      end

      # Fall back to first provider with generation settings
      Presets::MembershipApplier::PROVIDER_IDENTIFICATIONS.each do |provider|
        gen_settings = providers.dig(provider, "generation")
        next unless gen_settings.present?

        return gen_settings.slice(
          "max_context_tokens", "max_response_tokens", "temperature",
          "top_p", "top_k", "repetition_penalty"
        )
      end

      {}
    end
  end
end
