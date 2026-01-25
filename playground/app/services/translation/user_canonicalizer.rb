# frozen_string_literal: true

module Translation
  class UserCanonicalizer
    def initialize(conversation:, speaker:, history_scope:, settings:)
      @conversation = conversation
      @speaker = speaker
      @history_scope = history_scope
      @settings = settings
    end

    def ensure_canonical_for_prompt!
      return 0 unless settings&.translation_needed?

      internal_lang = settings.internal_lang.to_s
      source_lang = settings.source_lang.to_s.presence || "auto"
      return 0 if internal_lang.blank?

      provider = resolve_provider
      return 0 if provider.nil? || provider.disabled?

      window_ids = prompt_window_ids
      return 0 if window_ids.empty?

      candidates = Message.where(id: window_ids, role: "user")

      service = Translation::Service.new
      model_override = settings.provider&.model_override

      settings_sha256 =
        Digest::SHA256.hexdigest(
          settings_fingerprint(
            provider: provider,
            model: model_override,
            source_lang: source_lang,
            target_lang: internal_lang,
            prompt_preset: settings.prompt_preset,
            masking: settings.masking,
            chunking: settings.chunking,
          )
        )

      updated = 0

      candidates.find_each do |message|
        input_text = message.content.to_s
        next if input_text.blank?
        next if likely_internal_lang?(input_text, internal_lang: internal_lang)

        input_sha256 = Digest::SHA256.hexdigest(input_text)
        existing = message.metadata&.dig("i18n", "canonical")
        if existing.is_a?(Hash) &&
            existing["internal_lang"].to_s == internal_lang &&
            existing["input_sha256"].to_s == input_sha256 &&
            existing["settings_sha256"].to_s == settings_sha256 &&
            existing["text"].to_s.present?
          next
        end

        request =
          Translation::Service::Request.new(
            text: input_text,
            source_lang: source_lang,
            target_lang: internal_lang,
            prompt_preset: settings.prompt_preset,
            provider: provider,
            model: model_override,
            masking: settings.masking,
            chunking: settings.chunking,
            cache: settings.cache,
          )

        result = service.translate!(request)

        persist_canonical!(
          message: message,
          canonical_text: result.translated_text,
          provider: provider,
          model: request.model,
          internal_lang: internal_lang,
          source_lang: source_lang,
          input_sha256: input_sha256,
          settings_sha256: settings_sha256,
          result: result,
        )

        TokenUsageRecorder.execute(conversation: conversation, usage: result.provider_usage) if result.provider_usage.present?

        updated += 1
      rescue Translation::Error => e
        Rails.logger.warn "UserCanonicalizer failed for message #{message.id}: #{e.class}: #{e.message}"
      end

      updated
    end

    private

    attr_reader :conversation, :speaker, :history_scope, :settings

    def resolve_provider
      override_id = settings.provider&.llm_provider_id

      if override_id.present?
        return LLMProvider.enabled.find_by(id: override_id)
      end

      speaker&.effective_llm_provider || LLMProvider.get_default
    end

    def prompt_window_ids
      scope = history_scope.included_in_prompt
      scope =
        scope
          .except(:includes, :preload, :eager_load)
          .reorder(seq: :desc, id: :desc)
          .limit(PromptBuilder::DEFAULT_HISTORY_WINDOW_MESSAGES)

      scope.pluck(:id)
    end

    def persist_canonical!(message:, canonical_text:, provider:, model:, internal_lang:, source_lang:, input_sha256:, settings_sha256:, result:)
      metadata = message.metadata.is_a?(Hash) ? message.metadata.deep_stringify_keys : {}
      i18n = metadata.fetch("i18n", {})
      i18n = {} unless i18n.is_a?(Hash)

      i18n["canonical"] = {
        "text" => canonical_text.to_s,
        "provider" => "llm",
        "provider_id" => provider.id,
        "model" => model.presence || provider.model,
        "internal_lang" => internal_lang,
        "source_lang" => source_lang,
        "input_sha256" => input_sha256,
        "settings_sha256" => settings_sha256,
        "cache_hit" => result.cache_hit,
        "chunks" => result.chunks,
        "warnings" => result.warnings,
        "usage" => result.provider_usage,
        "created_at" => Time.current.iso8601,
      }

      metadata["i18n"] = i18n
      message.update!(metadata: metadata)
    end

    def settings_fingerprint(provider:, model:, source_lang:, target_lang:, prompt_preset:, masking:, chunking:)
      [
        "provider_id=#{provider&.id || 'default'}",
        "model=#{model || 'default'}",
        "sl=#{source_lang}",
        "tl=#{target_lang}",
        "preset=#{prompt_preset}",
        "masking=#{masking&.respond_to?(:to_h) ? masking.to_h : masking}",
        "chunking=#{chunking&.respond_to?(:to_h) ? chunking.to_h : chunking}",
      ].join("|")
    end

    def likely_internal_lang?(text, internal_lang:)
      return false unless internal_lang.to_s == "en"

      cjk_chars = text.to_s.scan(/[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}]/).length
      return true if cjk_chars.zero?

      total_chars = text.to_s.length
      return false if total_chars.zero?

      (cjk_chars.to_f / total_chars.to_f) < 0.05
    end
  end
end
