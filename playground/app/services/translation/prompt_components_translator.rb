# frozen_string_literal: true

module Translation
  class PromptComponentsTranslator
    def initialize(conversation:, speaker:, settings:)
      @conversation = conversation
      @space = conversation.space
      @speaker = speaker
      @settings = settings
    end

    def translate_preset(preset)
      return preset unless settings&.native_prompt_components_translation_needed?
      return preset unless settings.native_prompt_components&.preset?

      fields = {
        main_prompt: preset.main_prompt.to_s,
        post_history_instructions: preset.post_history_instructions.to_s,
        authors_note: preset.authors_note.to_s,
      }.compact_blank

      translated = translate_fields(component: "preset", fields: fields)
      return preset if translated.empty?

      preset.with(**translated)
    end

    def translate_character(character)
      return character unless settings&.native_prompt_components_translation_needed?
      return character unless settings.native_prompt_components&.character?
      return character unless character.is_a?(::TavernKit::Character)

      data = character.data

      fields = {
        description: data.description.to_s,
        personality: data.personality.to_s,
        scenario: data.scenario.to_s,
        mes_example: data.mes_example.to_s,
        system_prompt: data.system_prompt.to_s,
        post_history_instructions: data.post_history_instructions.to_s,
        creator_notes: data.creator_notes.to_s,
      }.compact_blank

      translated = translate_fields(component: "character", fields: fields)
      return character if translated.empty?

      overridden_data = data.with(**translated)

      ::TavernKit::Character.new(
        data: overridden_data,
        source_version: character.source_version,
        raw: character.raw
      )
    end

    private

    attr_reader :conversation, :space, :speaker, :settings

    def translate_fields(component:, fields:)
      return {} if fields.blank?

      internal_lang = settings.internal_lang.to_s
      target_lang = settings.target_lang.to_s
      return {} if internal_lang.blank? || target_lang.blank? || internal_lang == target_lang

      provider = resolve_provider
      return {} if provider.nil? || provider.disabled?

      provider_kind = settings.provider&.kind.to_s.presence || "llm"
      model_override = settings.provider&.model_override
      source_lang = internal_lang

      run =
        TranslationRun.create!(
          conversation: conversation,
          message: nil,
          kind: "prompt_component_translation",
          status: "running",
          source_lang: source_lang,
          internal_lang: internal_lang,
          target_lang: target_lang,
          debug: {
            "component" => component,
            "fields" => fields.keys.map(&:to_s),
          }
        )

      run.running!
      emit_event!(run: run, event_name: "translation_run.running")

      service = Translation::Service.new
      translated = {}
      all_cache_hit = true
      total_usage = nil
      total_repairs = 0
      total_chunks = 0
      extractor_counts = Hash.new(0)
      warnings = []

      fields.each do |field_name, text|
        request =
          Translation::Service::Request.new(
            text: text,
            source_lang: source_lang,
            target_lang: target_lang,
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

        result = service.translate!(request)

        translated[field_name] = result.translated_text
        all_cache_hit &&= result.cache_hit == true
        total_usage = merge_usage(total_usage, result.provider_usage)
        total_repairs += result.repairs.to_i
        total_chunks += result.chunks.to_i
        if result.extractor.is_a?(Hash)
          result.extractor.each { |k, v| extractor_counts[k] += v.to_i }
        end
        warnings.concat(result.warnings) if result.warnings.present?
      end

      TokenUsageRecorder.execute(conversation: conversation, usage: total_usage) if total_usage.present?

      run.update!(
        debug: run.debug.merge(
          "provider_kind" => provider_kind,
          "provider_id" => provider.respond_to?(:id) ? provider.id : nil,
          "provider_endpoint" => provider.respond_to?(:base_url) ? provider.base_url.to_s : provider.respond_to?(:endpoint) ? provider.endpoint.to_s : nil,
          "model" => model_override.to_s.presence || (provider.respond_to?(:model) ? provider.model : nil),
          "cache_hit" => all_cache_hit,
          "chunks" => total_chunks,
          "repairs" => total_repairs,
          "extractor" => extractor_counts,
          "warnings" => warnings,
          "usage" => total_usage,
        )
      )

      run.succeeded!
      emit_event!(run: run, event_name: "translation_run.succeeded")

      translated
    rescue Translation::Error => e
      Rails.logger.warn "[PromptComponentsTranslator] failed (#{component}): #{e.class}: #{e.message}"

      if defined?(run) && run&.active?
        run.failed!(error: { "code" => "translation_failed", "message" => e.message })
        emit_event!(run: run, event_name: "translation_run.failed")
      end

      {}
    rescue StandardError => e
      Rails.logger.warn "[PromptComponentsTranslator] failed (#{component}): #{e.class}: #{e.message}"

      if defined?(run) && run&.active?
        run.failed!(error: { "code" => "unexpected_error", "message" => e.message })
        emit_event!(run: run, event_name: "translation_run.failed")
      end

      {}
    end

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

    def resolve_provider
      override_id = settings.provider&.llm_provider_id

      provider =
        if override_id.present?
          LLMProvider.enabled.find_by(id: override_id)
        else
          speaker&.effective_llm_provider
        end

      provider || LLMProvider.get_default
    end

    def emit_event!(run:, event_name:)
      ConversationEvents::Emitter.emit(
        event_name: event_name,
        conversation: conversation,
        space: space,
        message_id: run.message_id,
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
