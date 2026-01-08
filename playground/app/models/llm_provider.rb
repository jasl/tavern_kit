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

  scope :enabled, -> { where(disabled: false) }

  validates :name, presence: true, uniqueness: true
  validates :identification, presence: true, inclusion: { in: IDENTIFICATIONS }
  validates :base_url, presence: true

  # Preset provider configurations (used for seeding)
  PRESETS = {
    # Development/test only (served by this Rails app at /mock_llm/v1).
    mock: {
      name: "Mock (Local)",
      identification: "openai_compatible",
      streamable: true,
      supports_logprobs: false,
      base_url: "http://localhost:3000/mock_llm/v1",
      model: "mock",
    },
    openai: {
      name: "OpenAI",
      identification: "openai",
      streamable: true,
      supports_logprobs: true,
      base_url: "https://api.openai.com/v1",
    },
    deepseek: {
      name: "DeepSeek",
      identification: "deepseek",
      streamable: true,
      supports_logprobs: true,
      base_url: "https://api.deepseek.com/v1",
    },
    groq: {
      name: "Groq",
      identification: "openai_compatible",
      streamable: true,
      supports_logprobs: false,
      base_url: "https://api.groq.com/openai/v1",
    },
    together: {
      name: "Together AI",
      identification: "openai_compatible",
      streamable: true,
      supports_logprobs: false,
      base_url: "https://api.together.xyz/v1",
    },
    ollama: {
      name: "Ollama (Local)",
      identification: "openai_compatible",
      streamable: true,
      supports_logprobs: false,
      base_url: "http://localhost:11434/v1",
    },
    volcengine: {
      name: "Volcengine (火山引擎)",
      identification: "openai_compatible",
      streamable: true,
      supports_logprobs: false,
      base_url: "https://ark.cn-beijing.volces.com/api/v3",
    },
    custom: {
      name: "Custom",
      identification: "openai_compatible",
      streamable: true,
      supports_logprobs: false,
      base_url: "http://localhost:8000/v1",
    },
  }.freeze

  class << self
    # Get the default provider.
    #
    # Returns the configured default provider (if set and enabled).
    #
    # If no default is set (or the stored default points to a missing/disabled provider),
    # falls back to the first enabled provider by ID.
    #
    # If no enabled providers exist, returns nil.
    #
    # This method does not seed presets or auto-persist fallbacks.
    #
    # @return [LLMProvider, nil] the default provider (or nil if none exist)
    def get_default
      provider_id = Setting.get("llm.default_provider_id").to_s
      if provider_id.match?(/\A\d+\z/)
        provider = enabled.find_by(id: provider_id)
        return provider if provider
      end

      enabled.order(:id).first
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

        find_or_create_by!(name: config[:name]) do |provider|
          provider.identification = config[:identification]
          provider.streamable = config[:streamable]
          provider.supports_logprobs = config[:supports_logprobs] || false
          provider.base_url = config[:base_url]
          provider.model = config[:model] if config[:model].present?
          provider.disabled = true if key != :mock
        end
      end
    end

    # Get all providers for selection UI.
    #
    # @return [Array<Hash>] array of { id:, name:, model: } hashes
    def for_select
      enabled.order(:id).map do |provider|
        {
          id: provider.id,
          name: provider.name,
          model: provider.model,
        }
      end
    end

    private
  end

  def enabled?
    !disabled?
  end
end
