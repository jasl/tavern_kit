# frozen_string_literal: true

module Translation
  module Metadata
    module_function

    def pending?(record, target_lang:)
      return false if target_lang.to_s.blank?

      record.metadata&.dig("i18n", "translation_pending", target_lang.to_s) == true
    end

    def mark_pending!(record, target_lang:)
      target_lang = target_lang.to_s
      return false if target_lang.blank?

      metadata = normalize_metadata(record.metadata)
      i18n = metadata.fetch("i18n", {})
      i18n = {} unless i18n.is_a?(Hash)

      pending = i18n.fetch("translation_pending", {})
      pending = {} unless pending.is_a?(Hash)

      return false if pending[target_lang] == true

      pending = pending.merge(target_lang => true)
      i18n = i18n.merge("translation_pending" => pending)
      i18n.delete("last_error")

      record.update!(metadata: metadata.merge("i18n" => i18n))
      true
    end

    def clear_pending!(record, target_lang:)
      target_lang = target_lang.to_s
      return false if target_lang.blank?

      metadata = normalize_metadata(record.metadata)
      i18n = metadata.fetch("i18n", {})
      i18n = {} unless i18n.is_a?(Hash)

      pending = i18n.fetch("translation_pending", {})
      pending = {} unless pending.is_a?(Hash)
      return false unless pending.key?(target_lang)

      pending = pending.dup
      pending.delete(target_lang)

      i18n = i18n.merge("translation_pending" => pending)
      i18n.delete("translation_pending") if pending.empty?

      record.update!(metadata: metadata.merge("i18n" => i18n))
      true
    end

    def normalize_metadata(metadata)
      return {} unless metadata.is_a?(Hash)

      metadata.deep_stringify_keys
    end
    private_class_method :normalize_metadata
  end
end
