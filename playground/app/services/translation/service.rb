# frozen_string_literal: true

module Translation
  class Service
    Request =
      Data.define(
        :text,
        :source_lang,
        :target_lang,
        :prompt_preset,
        :provider,
        :model,
        :masking,
        :chunking,
        :cache,
      )

    Result =
      Data.define(
        :translated_text,
        :cache_hit,
        :chunks,
        :provider_usage,
        :warnings,
      )

    def translate!(request)
      source_text = request.text.to_s
      return Result.new(translated_text: "", cache_hit: true, chunks: 0, provider_usage: nil, warnings: []) if source_text.empty?

      masker = Masker.new(masking: request.masking)
      masked = masker.mask(source_text)

      chunker = Chunker.new(max_chars: request.chunking&.max_chars)
      masked_chunks = chunker.chunk(masked.text)

      cache = Cache.new(enabled: request.cache&.enabled, ttl_seconds: request.cache&.ttl_seconds)
      provider = Providers::LLM.new(provider: request.provider, model: request.model)

      warnings = []
      translated_chunks = []
      cache_hit = true
      provider_usage = nil

      masked_chunks.each do |chunk|
        chunk_tokens = masked.tokens.select { |token| chunk.include?(token) }
        key = cache.key_for(request: request, masked_text: chunk)

        cached = cache.read(key)
        if cached
          translated_chunk = cached
        else
          cache_hit = false
          translated_chunk, usage = translate_chunk(provider: provider, request: request, chunk: chunk, tokens: chunk_tokens)
          provider_usage = usage if usage
          cache.write(key, translated_chunk)
        end

        masker.validate_tokens!(translated_chunk, tokens: chunk_tokens)
        translated_chunks << translated_chunk
      rescue ExtractionError, MaskMismatchError => e
        cache_hit = false
        warnings << e.message

        translated_chunk, usage = translate_chunk(provider: provider, request: request, chunk: chunk, tokens: chunk_tokens, repair: true)
        provider_usage = usage if usage
        masker.validate_tokens!(translated_chunk, tokens: chunk_tokens)
        translated_chunks << translated_chunk
      end

      translated_masked = translated_chunks.join
      masker.validate_tokens!(translated_masked, tokens: masked.tokens)
      translated = masker.unmask(translated_masked, replacements: masked.replacements)

      Result.new(
        translated_text: translated,
        cache_hit: cache_hit,
        chunks: masked_chunks.length,
        provider_usage: provider_usage,
        warnings: warnings,
      )
    end

    private

    def translate_chunk(provider:, request:, chunk:, tokens:, repair: false)
      preset_key = repair ? "repair_roleplay_v1" : request.prompt_preset
      preset = PromptPresets.fetch(preset_key)

      user_prompt =
        PromptPresets.user_prompt(
          key: preset.key,
          text: chunk,
          source_lang: request.source_lang,
          target_lang: request.target_lang,
        )

      raw, usage = provider.translate!(system_prompt: preset.system_prompt, user_prompt: user_prompt)
      extracted = Extractor.extract!(raw)

      Masker.new(masking: nil).validate_tokens!(extracted, tokens: tokens)
      [extracted, usage]
    end
  end
end
