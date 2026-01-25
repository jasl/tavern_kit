# frozen_string_literal: true

module Translation
  class Service
    Request =
      Data.define(
        :text,
        :source_lang,
        :target_lang,
        :prompt_preset,
        :provider_kind,
        :provider,
        :model,
        :masking,
        :chunking,
        :cache,
        :glossary,
        :ntl,
        :prompt_overrides,
      )

    Result =
      Data.define(
        :translated_text,
        :cache_hit,
        :chunks,
        :provider_usage,
        :repairs,
        :extractor,
        :warnings,
      )

    def translate!(request)
      source_text = request.text.to_s
      if source_text.empty?
        return Result.new(
          translated_text: "",
          cache_hit: true,
          chunks: 0,
          provider_usage: nil,
          repairs: 0,
          extractor: {},
          warnings: []
        )
      end

      masker = Masker.new(masking: request.masking)
      masked = masker.mask(source_text)

      chunker = Chunker.new(max_chars: request.chunking&.max_chars)
      masked_chunks = chunker.chunk(masked.text)

      cache = Cache.new(enabled: request.cache&.enabled, ttl_seconds: request.cache&.ttl_seconds)
      provider = Providers::Resolver.resolve_for(request)

      warnings = []
      translated_chunks = []
      cache_hit = true
      provider_usage = nil
      repairs = 0
      extractor_counts = Hash.new(0)
      lexicon = Lexicon.new(glossary: request.glossary, ntl: request.ntl)
      warnings.concat(lexicon.warnings)
      primary_preset = PromptPresets.resolve(key: request.prompt_preset, overrides: request.prompt_overrides)
      primary_prompt_digest = PromptPresets.digest(primary_preset)

      masked_chunks.each do |chunk|
        lex = lexicon.build(chunk)

        chunk_tokens = masked.tokens.select { |token| chunk.include?(token) }
        key =
          cache.key_for(
            request: request,
            masked_text: chunk,
            prompt_digest: primary_prompt_digest,
            glossary_digest: lex.glossary_digest,
            ntl_digest: lex.ntl_digest,
          )

        cached = cache.read(key)
        if cached
          translated_chunk = cached
        else
          cache_hit = false
          translated_chunk, usage, strategy =
            translate_chunk(
              provider: provider,
              request: request,
              chunk: chunk,
              tokens: chunk_tokens,
              glossary_lines: lex.glossary_lines,
              ntl_lines: lex.ntl_lines,
            )
          provider_usage = merge_usage(provider_usage, usage)
          extractor_counts[strategy] += 1 if strategy.present?
          cache.write(key, translated_chunk)
        end

        masker.validate_tokens!(translated_chunk, tokens: chunk_tokens)
        translated_chunks << translated_chunk
      rescue ExtractionError, MaskMismatchError => e
        cache_hit = false
        repairs += 1
        warnings << e.message

        translated_chunk, usage, strategy =
          translate_chunk(
            provider: provider,
            request: request,
            chunk: chunk,
            tokens: chunk_tokens,
            glossary_lines: lex.glossary_lines,
            ntl_lines: lex.ntl_lines,
            repair: true,
          )
        provider_usage = merge_usage(provider_usage, usage)
        extractor_counts[strategy] += 1 if strategy.present?
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
        repairs: repairs,
        extractor: extractor_counts,
        warnings: warnings,
      )
    end

    private

    def merge_usage(total, delta)
      return total if delta.nil?

      delta_hash =
        if delta.respond_to?(:to_h)
          delta.to_h
        else
          delta
        end

      return total unless delta_hash.is_a?(Hash)

      total_hash = total.is_a?(Hash) ? total.dup : {}

      delta_hash.each do |key, value|
        next unless value.is_a?(Numeric) || value.to_s.match?(/\A\d+\z/)

        total_key = key.is_a?(String) ? key.to_sym : key
        total_hash[total_key] = total_hash[total_key].to_i + value.to_i
      end

      total_hash
    end

    def translate_chunk(provider:, request:, chunk:, tokens:, glossary_lines:, ntl_lines:, repair: false)
      preset_key = repair ? "repair_roleplay_v1" : request.prompt_preset
      preset = PromptPresets.resolve(key: preset_key, overrides: request.prompt_overrides, repair: repair)

      source_lang = Translation::LanguageCodeMapper.map(request.provider_kind, request.source_lang)
      target_lang = Translation::LanguageCodeMapper.map(request.provider_kind, request.target_lang)

      user_prompt =
        PromptPresets.user_prompt(
          template: preset.user_prompt_template,
          text: chunk,
          source_lang: source_lang,
          target_lang: target_lang,
          glossary_lines: glossary_lines,
          ntl_lines: ntl_lines,
        )

      raw, usage =
        provider.translate!(
          text: chunk,
          source_lang: source_lang,
          target_lang: target_lang,
          system_prompt: preset.system_prompt,
          user_prompt: user_prompt,
        )
      extracted, strategy = Extractor.extract_with_strategy!(raw)

      Masker.new(masking: nil).validate_tokens!(extracted, tokens: tokens)
      [extracted, usage, strategy]
    end
  end
end
