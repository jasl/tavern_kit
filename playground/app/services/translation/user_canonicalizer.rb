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
      provider_kind = settings.provider&.kind.to_s.presence || "llm"

      settings_sha256 =
        Digest::SHA256.hexdigest(
          settings_fingerprint(
            provider_kind: provider_kind,
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
        run = nil

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
            provider_kind: provider_kind,
            provider: provider,
            model: model_override,
            masking: settings.masking,
            chunking: settings.chunking,
            cache: settings.cache,
            glossary: settings.glossary,
            ntl: settings.ntl,
            prompt_overrides: settings.translator_prompts,
          )

        run =
          TranslationRun.create!(
            conversation: conversation,
            message: message,
            kind: "user_canonicalization",
            status: "running",
            source_lang: source_lang,
            internal_lang: internal_lang,
            target_lang: internal_lang,
            debug: { "enqueued_by" => "user_canonicalizer" }
          )
        run.running!
        emit_event!(run: run, message: message, event_name: "translation_run.running")

        result = service.translate!(request)

        persist_canonical!(
          message: message,
          canonical_text: result.translated_text,
          provider_kind: provider_kind,
          provider: provider,
          model: request.model,
          internal_lang: internal_lang,
          source_lang: source_lang,
          input_sha256: input_sha256,
          settings_sha256: settings_sha256,
          result: result,
        )

        TokenUsageRecorder.execute(conversation: conversation, usage: result.provider_usage) if result.provider_usage.present?

        run.update!(
          debug: run.debug.merge(
            "provider_kind" => provider_kind,
            "provider_id" => provider.respond_to?(:id) ? provider.id : nil,
            "provider_endpoint" => provider.respond_to?(:base_url) ? provider.base_url.to_s : provider.respond_to?(:endpoint) ? provider.endpoint.to_s : nil,
            "model" => request.model.presence || (provider.respond_to?(:model) ? provider.model : nil),
            "input_sha256" => input_sha256,
            "settings_sha256" => settings_sha256,
            "cache_hit" => result.cache_hit,
            "chunks" => result.chunks,
            "repairs" => result.repairs,
            "extractor" => result.extractor,
            "warnings" => result.warnings,
            "usage" => result.provider_usage,
          )
        )
        run.succeeded!
        emit_event!(run: run, message: message, event_name: "translation_run.succeeded")

        updated += 1
      rescue Translation::Error => e
        Rails.logger.warn "UserCanonicalizer failed for message #{message.id}: #{e.class}: #{e.message}"

        if run&.active?
          run.failed!(error: { "code" => "translation_failed", "message" => e.message })
          emit_event!(run: run, message: message, event_name: "translation_run.failed")
        end
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

    def persist_canonical!(message:, canonical_text:, provider_kind:, provider:, model:, internal_lang:, source_lang:, input_sha256:, settings_sha256:, result:)
      metadata = message.metadata.is_a?(Hash) ? message.metadata.deep_stringify_keys : {}
      i18n = metadata.fetch("i18n", {})
      i18n = {} unless i18n.is_a?(Hash)

      i18n["canonical"] = {
        "text" => canonical_text.to_s,
        "provider" => provider_kind,
        "provider_id" => provider.respond_to?(:id) ? provider.id : nil,
        "model" => model.presence || (provider.respond_to?(:model) ? provider.model : nil),
        "internal_lang" => internal_lang,
        "source_lang" => source_lang,
        "input_sha256" => input_sha256,
        "settings_sha256" => settings_sha256,
        "cache_hit" => result.cache_hit,
        "chunks" => result.chunks,
        "repairs" => result.repairs,
        "extractor" => result.extractor,
        "warnings" => result.warnings,
        "usage" => result.provider_usage,
        "created_at" => Time.current.iso8601,
      }

      metadata["i18n"] = i18n
      message.update!(metadata: metadata)
    end

    def settings_fingerprint(provider_kind:, provider:, model:, source_lang:, target_lang:, prompt_preset:, masking:, chunking:)
      effective_model = model.to_s.presence || provider&.model.to_s.presence || "default"
      prompt_digest =
        Translation::PromptPresets.digest(
          Translation::PromptPresets.resolve(key: prompt_preset, overrides: settings.translator_prompts)
        )

      [
        "provider_kind=#{provider_kind}",
        "provider_id=#{provider&.id || 'default'}",
        "provider_endpoint=#{provider&.base_url.to_s.presence || 'default'}",
        "model=#{effective_model}",
        "sl=#{source_lang}",
        "tl=#{target_lang}",
        "preset=#{prompt_preset}",
        "prompt_digest=#{prompt_digest}",
        "masking=#{masking&.respond_to?(:to_h) ? masking.to_h : masking}",
        "chunking=#{chunking&.respond_to?(:to_h) ? chunking.to_h : chunking}",
        "glossary=#{settings.glossary&.respond_to?(:to_h) ? settings.glossary.to_h : settings.glossary}",
        "ntl=#{settings.ntl&.respond_to?(:to_h) ? settings.ntl.to_h : settings.ntl}",
        "prompt_overrides=#{settings.translator_prompts&.respond_to?(:to_h) ? settings.translator_prompts.to_h : settings.translator_prompts}",
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

    def emit_event!(run:, message:, event_name:)
      ConversationEvents::Emitter.emit(
        event_name: event_name,
        conversation: conversation,
        space: conversation.space,
        message_id: message.id,
        reason: run.error&.dig("code"),
        payload: {
          translation_run_id: run.id,
          status: run.status,
          kind: run.kind,
          message_swipe_id: run.message_swipe_id,
          source_lang: run.source_lang,
          internal_lang: run.internal_lang,
          target_lang: run.target_lang,
          started_at: run.started_at&.iso8601,
          finished_at: run.finished_at&.iso8601,
          debug: run.debug,
          error: run.error,
        }
      )
    end
  end
end
