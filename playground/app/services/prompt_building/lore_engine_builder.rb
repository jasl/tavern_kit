# frozen_string_literal: true

module PromptBuilding
  class LoreEngineBuilder
    def initialize(space:)
      @space = space
    end

    def call
      wi_settings = @space.prompt_settings&.world_info
      return nil unless wi_settings

      ::TavernKit::Lore::Engine.new(
        token_estimator: ::TavernKit::TokenEstimator.default,
        match_whole_words: wi_settings.match_whole_words != false,
        case_sensitive: wi_settings.case_sensitive == true,
        max_recursion_steps: normalize_non_negative_integer(wi_settings.max_recursion_steps) || 3
      )
    end

    private

    def normalize_non_negative_integer(value)
      return nil if value.nil?

      n = Integer(value)
      n.negative? ? 0 : n
    rescue ArgumentError, TypeError
      nil
    end
  end
end
