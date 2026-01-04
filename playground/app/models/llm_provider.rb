# frozen_string_literal: true

# LLM Provider configuration model.
#
# Stores provider configurations including name, base URL, and encrypted API key.
# Preset providers are seeded on first run; users can configure their API keys.
#
# @example Get the default provider
#   LLMProvider.get_default
#   # => #<LLMProvider name: "OpenAI", base_url: "https://api.openai.com/v1", ...>
#
# @example Set default provider
#   LLMProvider.set_default!(provider)
#
# @example Update API key for a provider
#   provider = LLMProvider.find_by(name: "OpenAI")
#   provider.update!(api_key: "sk-...")
#
class LLMProvider < ApplicationRecord
  # Provider identifications - maps to settings schema providers
  IDENTIFICATIONS = %w[openai openai_compatible gemini deepseek anthropic qwen xai].freeze

  encrypts :api_key

  validates :name, presence: true, uniqueness: true
  validates :identification, presence: true, inclusion: { in: IDENTIFICATIONS }
  validates :base_url, presence: true

  # Preset provider configurations (used for seeding)
  PRESETS = {
    openai: {
      name: "OpenAI",
      identification: "openai",
      streamable: true,
      base_url: "https://api.openai.com/v1",
    },
    # Development/test only (served by this Rails app at /mock_llm/v1).
    mock: {
      name: "Mock (Local)",
      identification: "openai_compatible",
      streamable: true,
      base_url: "http://localhost:3000/mock_llm/v1",
      model: "mock",
    },
    deepseek: {
      name: "DeepSeek",
      identification: "deepseek",
      streamable: true,
      base_url: "https://api.deepseek.com/v1",
    },
    groq: {
      name: "Groq",
      identification: "openai_compatible",
      streamable: true,
      base_url: "https://api.groq.com/openai/v1",
    },
    together: {
      name: "Together AI",
      identification: "openai_compatible",
      streamable: true,
      base_url: "https://api.together.xyz/v1",
    },
    ollama: {
      name: "Ollama (Local)",
      identification: "openai_compatible",
      streamable: true,
      base_url: "http://localhost:11434/v1",
    },
    volcengine: {
      name: "Volcengine (火山引擎)",
      identification: "openai_compatible",
      streamable: true,
      base_url: "https://ark.cn-beijing.volces.com/api/v3",
    },
    custom: {
      name: "Custom",
      identification: "openai_compatible",
      streamable: true,
      base_url: "http://localhost:8000/v1",
    },
  }.freeze

  class << self
    # Get the default provider.
    #
    # If no default is set (or the stored default points to a missing provider),
    # this method will pick a deterministic fallback, persist it to Settings,
    # and return it.
    #
    # @return [LLMProvider, nil] the default provider (or nil if none exist)
    def get_default
      provider_id = Setting.get("llm.default_provider_id").to_s
      if provider_id.match?(/\A\d+\z/)
        provider = find_by(id: provider_id)
        return provider if provider
      end

      # Ensure we have at least one provider so we don't return nil on a fresh DB.
      seed_presets! unless exists?

      provider = default_fallback_provider
      return unless provider

      set_default!(provider)
    end

    # Set a provider as the default.
    #
    # @param provider [LLMProvider] the provider to set as default
    # @return [LLMProvider] the provider
    def set_default!(provider)
      Setting.set("llm.default_provider_id", provider.id)
      provider
    end

    # Seed preset providers into the database.
    # Called from db/seeds.rb or on first run.
    #
    # @return [Array<LLMProvider>] created/updated providers
    def seed_presets!
      PRESETS.filter_map do |key, config|
        next if key == :mock && !(Rails.env.development? || Rails.env.test?)

        create_or_find_by!(name: config[:name]) do |provider|
          provider.identification = config[:identification]
          provider.streamable = config[:streamable]
          provider.base_url = config[:base_url]
          provider.model = config[:model] if config[:model].present?
        end
      end
    end

    # Get all providers for selection UI.
    #
    # @return [Array<Hash>] array of { id:, name:, model: } hashes
    def for_select
      all.map do |provider|
        {
          id: provider.id,
          name: provider.name,
          model: provider.model,
        }
      end
    end

    private

    # Choose a deterministic default provider when the Setting is missing/invalid.
    #
    # Prefer a built-in OpenAI provider (by identification, name, or base_url) if present.
    # Otherwise fall back to the oldest provider by ID.
    #
    # @return [LLMProvider, nil]
    def default_fallback_provider
      if Rails.env.development? || Rails.env.test?
        mock_name = PRESETS.dig(:mock, :name)
        mock_url = PRESETS.dig(:mock, :base_url)

        mock =
          find_by(name: mock_name) ||
          where("LOWER(name) = ?", mock_name.to_s.downcase).order(:id).first ||
          find_by(base_url: mock_url)

        return mock if mock
      end

      where(identification: "openai").order(:id).first ||
        find_by(name: PRESETS.dig(:openai, :name)) ||
        where("LOWER(name) = ?", "openai").order(:id).first ||
        find_by(base_url: PRESETS.dig(:openai, :base_url)) ||
        order(:id).first
    end
  end
end
