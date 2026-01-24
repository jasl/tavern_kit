# frozen_string_literal: true

module Translation
  module LanguageCodeMapper
    module_function

    def map(provider_kind, lang_code)
      kind = provider_kind.to_s
      code = lang_code.to_s
      return code if code.blank?

      case kind
      when "microsoft", "bing"
        map_microsoft(code)
      else
        code
      end
    end

    def map_microsoft(code)
      case code
      when "zh-CN"
        "zh-Hans"
      when "zh-TW"
        "zh-Hant"
      else
        code
      end
    end
    private_class_method :map_microsoft
  end
end
