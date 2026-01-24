# frozen_string_literal: true

class MessageTranslationJob < ApplicationJob
  queue_as :llm

  discard_on ActiveRecord::RecordNotFound

  def perform(message_id, swipe_id: nil)
    message = Message.find(message_id)
    conversation = message.conversation
    space = conversation.space
    settings = space.prompt_settings&.i18n

    target_lang = settings&.target_lang.to_s
    internal_lang = settings&.internal_lang.to_s
    target_record = resolve_target_record(message: message, swipe_id: swipe_id)

    unless message.assistant_message? && settings&.translation_needed?
      Translation::Metadata.clear_pending!(target_record, target_lang: target_lang) if target_lang.present?
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
      return
    end

    unless Translation::Metadata.pending?(target_record, target_lang: target_lang)
      # Translation was canceled/cleared after enqueue.
      return
    end

    input_text = target_record.content.to_s
    if input_text.blank?
      Translation::Metadata.clear_pending!(target_record, target_lang: target_lang)
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
      return
    end

    provider = resolve_provider(message: message, settings: settings)
    if provider.nil? || provider.disabled?
      persist_error!(target_record: target_record, target_lang: target_lang, code: "provider_missing", error_message: "No enabled LLM provider available")
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
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
      return
    end

    result = Translation::Service.new.translate!(request)

    return unless Translation::Metadata.pending?(target_record, target_lang: target_lang)

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

    ensure_routes_loaded_for_rendering!
    message.broadcast_update
  rescue Translation::Error => e
    if defined?(target_record) && Translation::Metadata.pending?(target_record, target_lang: target_lang)
      persist_error!(target_record: target_record, target_lang: target_lang, code: "translation_failed", error_message: e.message)
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
    end
  rescue StandardError => e
    Rails.logger.warn "MessageTranslationJob failed: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    if defined?(target_record) && Translation::Metadata.pending?(target_record, target_lang: target_lang)
      persist_error!(target_record: target_record, target_lang: target_lang, code: "unexpected_error", error_message: e.message)
      ensure_routes_loaded_for_rendering!
      message.broadcast_update
    end
  end

  private

  def resolve_target_record(message:, swipe_id:)
    if swipe_id
      message.message_swipes.find(swipe_id)
    else
      message.active_message_swipe || message
    end
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
    [
      "provider_id=#{request.provider&.id || 'default'}",
      "model=#{request.model || 'default'}",
      "sl=#{request.source_lang}",
      "tl=#{request.target_lang}",
      "preset=#{request.prompt_preset}",
      "masking=#{request.masking&.respond_to?(:to_h) ? request.masking.to_h : request.masking}",
      "chunking=#{request.chunking&.respond_to?(:to_h) ? request.chunking.to_h : request.chunking}",
    ].join("|")
  end
end
