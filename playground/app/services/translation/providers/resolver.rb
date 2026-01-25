# frozen_string_literal: true

module Translation
  module Providers
    class Resolver
      def self.resolve_for(request)
        resolve(kind: request.provider_kind, provider: request.provider, model: request.model)
      end

      def self.resolve(kind:, provider:, model: nil)
        kind = kind.to_s.presence || "llm"

        case kind
        when "llm"
          unless provider.is_a?(::LLMProvider)
            raise ProviderError, "LLM translation requires an LLMProvider"
          end

          Providers::LLM.new(provider: provider, model: model)
        else
          raise ProviderError, "Unsupported translation provider kind: #{kind}"
        end
      end
    end
  end
end
