# frozen_string_literal: true

module Translation
  module Providers
    class LLM
      def initialize(provider:, model: nil)
        @provider = provider
        @model = model
        @client = LLMClient.new(provider: provider)
      end

      def translate!(text:, source_lang:, target_lang:, system_prompt: nil, user_prompt: nil)
        if system_prompt.blank? || user_prompt.blank?
          raise ProviderError, "LLM translation requires system_prompt and user_prompt"
        end

        messages = [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt },
        ]

        content = client.chat(messages: messages, model: model, temperature: 0)
        [content.to_s, client.last_usage]
      rescue LLMClient::Error,
             SimpleInference::Errors::HTTPError,
             SimpleInference::Errors::ConnectionError,
             SimpleInference::Errors::TimeoutError => e
        raise ProviderError, e.message
      end

      private

      attr_reader :client, :model
    end
  end
end
