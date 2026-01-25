# frozen_string_literal: true

class MessageTranslationJob < ApplicationJob
  queue_as :llm

  discard_on ActiveRecord::RecordNotFound

  def perform(translation_run_id)
    run = TranslationRun.find(translation_run_id)
    message = run.message
    conversation = run.conversation
    space = conversation.space
    settings = space.prompt_settings&.i18n

    target_lang = run.target_lang.to_s
    internal_lang = run.internal_lang.to_s
    target_record = run.target_record

    if run.canceled?
      Translation::Metadata.clear_pending!(target_record, target_lang: target_lang) if target_lang.present?
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
      return
    end

    if run.cancel_requested_at.present?
      Translation::Metadata.clear_pending!(target_record, target_lang: target_lang) if target_lang.present?
      run.canceled!(error: run.error.presence || { "code" => "canceled", "message" => "Canceled" })
      emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.canceled")
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
      return
    end

    run.running!
    emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.running")

    unless message.assistant_message? && settings&.translation_needed?
      Translation::Metadata.clear_pending!(target_record, target_lang: target_lang) if target_lang.present?
      run.canceled!(error: { "code" => "disabled", "message" => "Translation disabled" })
      emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.canceled")
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
      return
    end

    unless Translation::Metadata.pending?(target_record, target_lang: target_lang)
      # Translation was canceled/cleared after enqueue.
      run.canceled!(error: { "code" => "cleared", "message" => "Translation cleared" })
      emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.canceled")
      return
    end

    input_text = target_record.content.to_s
    if input_text.blank?
      Translation::Metadata.clear_pending!(target_record, target_lang: target_lang)
      run.canceled!(error: { "code" => "empty_input", "message" => "Nothing to translate" })
      emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.canceled")
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
      return
    end

    provider = resolve_provider(message: message, settings: settings)
    if provider.nil? || provider.disabled?
      persist_error!(target_record: target_record, target_lang: target_lang, code: "provider_missing", error_message: "No enabled LLM provider available")
      run.failed!(error: { "code" => "provider_missing", "message" => "No enabled LLM provider available" })
      emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.failed")
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
      return
    end

    request =
      Translation::Service::Request.new(
        text: input_text,
        source_lang: internal_lang,
        target_lang: target_lang,
        prompt_preset: settings.prompt_preset,
        provider: provider,
        model: settings.provider&.model_override,
        masking: settings.masking,
        chunking: settings.chunking,
        cache: settings.cache,
      )

    input_sha256 = Digest::SHA256.hexdigest(input_text)
    settings_sha256 = Digest::SHA256.hexdigest(settings_fingerprint(request))

    existing = target_record.metadata&.dig("i18n", "translations", target_lang)
    if existing.is_a?(Hash) && existing["input_sha256"] == input_sha256 && existing["settings_sha256"] == settings_sha256
      Translation::Metadata.clear_pending!(target_record, target_lang: target_lang)
      run.canceled!(error: { "code" => "noop", "message" => "Already translated" })
      emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.canceled")
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
      return
    end

    result = Translation::Service.new.translate!(request)

    unless Translation::Metadata.pending?(target_record, target_lang: target_lang)
      # Translation was cleared while we were running (e.g., Clear translations clicked).
      run.canceled!(error: { "code" => "cleared", "message" => "Translation cleared" })
      emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.canceled")
      return
    end

    persist_translation!(
      target_record: target_record,
      target_lang: target_lang,
      internal_lang: internal_lang,
      provider: provider,
      model: request.model,
      result: result,
      input_sha256: input_sha256,
      settings_sha256: settings_sha256,
    )

    run.update!(
      debug: run.debug.merge(
        "provider_kind" => "llm",
        "provider_id" => provider.id,
        "provider_endpoint" => provider.base_url.to_s,
        "model" => request.model.presence || provider.model,
        "input_sha256" => input_sha256,
        "settings_sha256" => settings_sha256,
        "cache_hit" => result.cache_hit,
        "chunks" => result.chunks,
        "warnings" => result.warnings,
        "usage" => result.provider_usage,
      )
    )

    TokenUsageRecorder.execute(conversation: conversation, usage: result.provider_usage) if result.provider_usage.present?

    run.succeeded!
    emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.succeeded")

    ensure_routes_loaded_for_rendering!
    message.broadcast_update
  rescue Translation::Error => e
    if defined?(run) && defined?(target_record) && Translation::Metadata.pending?(target_record, target_lang: target_lang)
      persist_error!(target_record: target_record, target_lang: target_lang, code: "translation_failed", error_message: e.message)
      run.failed!(error: { "code" => "translation_failed", "message" => e.message })
      emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.failed")
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
    elsif defined?(run) && run.active?
      run.failed!(error: { "code" => "translation_failed", "message" => e.message })
      emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.failed")
    end
  rescue StandardError => e
    Rails.logger.warn "MessageTranslationJob failed: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    if defined?(run) && defined?(target_record) && Translation::Metadata.pending?(target_record, target_lang: target_lang)
      persist_error!(target_record: target_record, target_lang: target_lang, code: "unexpected_error", error_message: e.message)
      run.failed!(error: { "code" => "unexpected_error", "message" => e.message })
      emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.failed")
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
    elsif defined?(run) && run.active?
      run.failed!(error: { "code" => "unexpected_error", "message" => e.message })
      emit_event!(run: run, conversation: conversation, space: space, message: message, event_name: "translation_run.failed")
    end
  end

  private

  def emit_event!(run:, conversation:, space:, message:, event_name:)
    ConversationEvents::Emitter.emit(
      event_name: event_name,
      conversation: conversation,
      space: space,
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

  def resolve_provider(message:, settings:)
    override_id = settings.provider&.llm_provider_id

    provider =
      if override_id.present?
        LLMProvider.enabled.find_by(id: override_id)
      else
        message.space_membership&.effective_llm_provider
      end

    provider || LLMProvider.get_default
  end

  def persist_translation!(target_record:, target_lang:, internal_lang:, provider:, model:, result:, input_sha256:, settings_sha256:)
    metadata = target_record.metadata.is_a?(Hash) ? target_record.metadata.deep_stringify_keys : {}
    i18n = metadata.fetch("i18n", {})
    i18n = {} unless i18n.is_a?(Hash)
    translations = i18n.fetch("translations", {})
    translations = {} unless translations.is_a?(Hash)

    translations[target_lang] = {
      "text" => result.translated_text,
      "provider" => "llm",
      "provider_id" => provider.id,
      "model" => model.presence || provider.model,
      "internal_lang" => internal_lang,
      "target_lang" => target_lang,
      "input_sha256" => input_sha256,
      "settings_sha256" => settings_sha256,
      "cache_hit" => result.cache_hit,
      "chunks" => result.chunks,
      "warnings" => result.warnings,
      "usage" => result.provider_usage,
      "created_at" => Time.current.iso8601,
    }

    i18n["translations"] = translations
    i18n.delete("last_error")
    if (pending = i18n["translation_pending"]).is_a?(Hash)
      pending = pending.dup
      pending.delete(target_lang)
      if pending.empty?
        i18n.delete("translation_pending")
      else
        i18n["translation_pending"] = pending
      end
    end

    metadata["i18n"] = i18n
    target_record.update!(metadata: metadata)
  end

  def persist_error!(target_record:, target_lang:, code:, error_message:)
    metadata = target_record.metadata.is_a?(Hash) ? target_record.metadata.deep_stringify_keys : {}
    i18n = metadata.fetch("i18n", {})
    i18n = {} unless i18n.is_a?(Hash)

    i18n["last_error"] = {
      "code" => code,
      "message" => error_message,
      "target_lang" => target_lang,
      "created_at" => Time.current.iso8601,
    }

    if (pending = i18n["translation_pending"]).is_a?(Hash)
      pending = pending.dup
      pending.delete(target_lang)
      if pending.empty?
        i18n.delete("translation_pending")
      else
        i18n["translation_pending"] = pending
      end
    end

    metadata["i18n"] = i18n
    target_record.update!(metadata: metadata)
  rescue StandardError => e
    Rails.logger.warn "Failed to persist translation error metadata: #{e.class}: #{e.message}"
  end

  def settings_fingerprint(request)
    effective_model = request.model.to_s.presence || request.provider&.model.to_s.presence || "default"

    [
      "provider_kind=llm",
      "provider_id=#{request.provider&.id || 'default'}",
      "provider_endpoint=#{request.provider&.base_url.to_s.presence || 'default'}",
      "model=#{effective_model}",
      "sl=#{request.source_lang}",
      "tl=#{request.target_lang}",
      "preset=#{request.prompt_preset}",
      "masking=#{request.masking&.respond_to?(:to_h) ? request.masking.to_h : request.masking}",
      "chunking=#{request.chunking&.respond_to?(:to_h) ? request.chunking.to_h : request.chunking}",
    ].join("|")
  end
end
