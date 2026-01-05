# frozen_string_literal: true

module TavernKit
  # Token estimation for context budget management.
  #
  # TiktokenRuby is the default and recommended implementation for production.
  # CharDiv4 is available for testing or environments where tiktoken_ruby
  # cannot be installed.
  module TokenEstimator
    class Base
      def estimate(_text)
        raise NotImplementedError, "implement in subclass"
      end

      # Tokenize text and return array of token hashes.
      #
      # @param text [String, nil] text to tokenize
      # @return [Array<Hash>] array of { id: Integer, text: String } hashes
      def tokenize(_text)
        raise NotImplementedError, "implement in subclass"
      end
    end

    # A simple heuristic: ~4 characters per token for English-like text.
    # This is *not* accurate for production use, but useful for testing
    # or environments where tiktoken_ruby is unavailable.
    #
    # @note Do NOT use in production - use TiktokenRuby instead.
    class CharDiv4 < Base
      def estimate(text)
        return 0 if text.nil?

        s = text.to_s
        return 0 if s.empty?

        (s.length / 4.0).ceil
      end

      # Simple tokenization by splitting into 4-character chunks.
      # @note This is a rough approximation for testing only.
      def tokenize(text)
        return [] if text.nil?

        s = text.to_s
        return [] if s.empty?

        # Split into ~4 char chunks to approximate tokens
        chunks = s.scan(/.{1,4}/m)
        chunks.each_with_index.map do |chunk, idx|
          { id: idx, text: chunk }
        end
      end
    end

    # Uses OpenAI's tiktoken tokenizer via the `tiktoken_ruby` gem.
    # This is the recommended implementation for production use.
    #
    # Supports multiple encodings:
    # - cl100k_base: GPT-4, GPT-3.5-turbo, text-embedding-ada-002
    # - p50k_base: Codex models
    # - r50k_base: GPT-3 models (davinci, etc.)
    # - o200k_base: GPT-4o models
    class TiktokenRuby < Base
      attr_reader :encoding_name, :model

      def initialize(model: nil, encoding: "cl100k_base")
        @model = model
        @encoding_name = encoding

        @encoding = if model && !model.to_s.strip.empty?
          begin
            Tiktoken.encoding_for_model(model)
          rescue StandardError
            # Fall back to specified encoding if model lookup fails.
            Tiktoken.get_encoding(encoding)
          end
        else
          Tiktoken.get_encoding(encoding)
        end
      end

      def estimate(text)
        return 0 if text.nil?

        s = text.to_s
        return 0 if s.empty?

        @encoding.encode(s).length
      end

      # Tokenize text and return array of token hashes with IDs and decoded text.
      #
      # @param text [String, nil] text to tokenize
      # @return [Array<Hash>] array of { id: Integer, text: String } hashes
      def tokenize(text)
        return [] if text.nil?

        s = text.to_s
        return [] if s.empty?

        ids = @encoding.encode(s)
        ids.map { |id| { id: id, text: @encoding.decode([id]) } }
      end
    end

    class << self
      # Returns the default token estimator (TiktokenRuby).
      #
      # @param model [String, nil] Model name for tiktoken (e.g., "gpt-4", "gpt-4o")
      # @param encoding [String] Encoding name (default: "cl100k_base")
      # @return [TiktokenRuby] Token estimator instance
      # @raise [LoadError] if tiktoken_ruby gem is not installed
      def default(model: nil, encoding: "cl100k_base")
        model_s = model.to_s.strip
        model_s = nil if model_s.empty?

        encoding_s = encoding.to_s.strip
        encoding_s = "cl100k_base" if encoding_s.empty?

        @defaults_by_key ||= {}
        @defaults_by_key[[model_s, encoding_s]] ||= TiktokenRuby.new(model: model_s, encoding: encoding_s)
      end

      # Create a CharDiv4 estimator for testing purposes.
      # @note Do NOT use in production.
      def char_div4
        CharDiv4.new
      end
    end
  end
end
