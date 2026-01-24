# frozen_string_literal: true

module Translation
  class Cache
    VERSION = "tx:v1"

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
      Digest::SHA256.hexdigest(
        [
          VERSION,
          "provider_id=#{request.provider&.id || 'default'}",
          "model=#{request.model || 'default'}",
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

    def masking_fingerprint(masking)
      return "" unless masking
      return masking.to_h.to_s if masking.respond_to?(:to_h)

      masking.to_s
    end
  end
end
