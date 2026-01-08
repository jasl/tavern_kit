# frozen_string_literal: true

module PromptBuilding
  class CharacterParticipantBuilder
    def initialize(space:, speaker:, participant:, group_chat:, card_handling_mode_override:)
      @space = space
      @speaker = speaker
      @participant = participant
      @group_chat = group_chat
      @card_handling_mode_override = card_handling_mode_override.to_s.presence
    end

    # @return [TavernKit::Character, TavernKit::User]
    def call
      scenario_override = @space.prompt_settings&.scenario_override.presence
      return @participant unless @participant.is_a?(::TavernKit::Character)

      overrides = {}
      card_handling_mode = normalized_card_handling_mode

      if @group_chat && %w[append append_disabled].include?(card_handling_mode)
        overrides.merge!(
          ::PromptBuilding::GroupCardJoiner
            .new(
              space: @space,
              speaker: @speaker,
              include_non_participating: card_handling_mode == "append_disabled",
              scenario_override: scenario_override
            )
            .call
        )
      else
        overrides[:scenario] = scenario_override.to_s if scenario_override
      end

      if @participant.data.character_book.is_a?(Hash)
        overridden_book = ::PromptBuilding::WorldInfoBookOverrides.apply(@participant.data.character_book, space: @space)
        overrides[:character_book] = overridden_book if overridden_book
      end

      return @participant if overrides.empty?

      overridden_data = @participant.data.with(**overrides)

      ::TavernKit::Character.new(
        data: overridden_data,
        source_version: @participant.source_version,
        raw: @participant.raw
      )
    end

    private

    def normalized_card_handling_mode
      mode = @card_handling_mode_override
      return mode if mode.present?
      return "swap" unless @space.respond_to?(:card_handling_mode)

      mode = @space.card_handling_mode.to_s
      mode.presence || "swap"
    end
  end
end
