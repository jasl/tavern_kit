# frozen_string_literal: true

module Translation
  class Cache
    VERSION = "tx:v2"

    def initialize(enabled:, ttl_seconds:)
      @enabled = !!enabled
      @ttl_seconds = Integer(ttl_seconds || 0) rescue 0
    end

    def read(key)
      return nil unless enabled?

      Rails.cache.read(key)
    end

    def write(key, value)
      return value unless enabled?

      options = {}
      options[:expires_in] = ttl_seconds if ttl_seconds.positive?
      Rails.cache.write(key, value, **options)
      value
    end

    def key_for(request:, masked_text:)
      provider_kind = provider_kind_for(request.provider)
      effective_model = effective_model_for(request.provider, request.model)
      provider_fingerprint = provider_fingerprint_for(request.provider, provider_kind: provider_kind, effective_model: effective_model)

      Digest::SHA256.hexdigest(
        [
          VERSION,
          "provider_kind=#{provider_kind}",
          "provider_fingerprint=#{Digest::SHA256.hexdigest(provider_fingerprint)}",
          "model=#{effective_model}",
          "sl=#{request.source_lang}",
          "tl=#{request.target_lang}",
          "preset=#{Digest::SHA256.hexdigest(request.prompt_preset.to_s)}",
          "mask=#{Digest::SHA256.hexdigest(masking_fingerprint(request.masking))}",
          "text=#{Digest::SHA256.hexdigest(masked_text.to_s)}",
        ].join(":")
      ).then { |h| "#{VERSION}:#{h}" }
    end

    private

    attr_reader :ttl_seconds

    def enabled? = @enabled

    def provider_kind_for(provider)
      return "unknown" if provider.nil?
      return "llm" if provider.is_a?(::LLMProvider)

      provider.class.name.to_s.demodulize.underscore.presence || "unknown"
    end

    def effective_model_for(provider, model_override)
      model_override.to_s.presence || provider&.respond_to?(:model) && provider.model.to_s.presence || "default"
    end

    def provider_fingerprint_for(provider, provider_kind:, effective_model:)
      parts = ["kind=#{provider_kind}", "model=#{effective_model}"]
      parts << "id=#{provider.id}" if provider&.respond_to?(:id)

      endpoint =
        if provider&.respond_to?(:base_url)
          provider.base_url.to_s
        elsif provider&.respond_to?(:endpoint)
          provider.endpoint.to_s
        else
          ""
        end

      parts << "endpoint=#{endpoint}" if endpoint.present?

      parts.join("|")
    end

    def masking_fingerprint(masking)
      return "" unless masking
      return masking.to_h.to_s if masking.respond_to?(:to_h)

      masking.to_s
    end
  end
end
