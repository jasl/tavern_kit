# frozen_string_literal: true

module PromptBuilding
  class GroupCardJoiner
    def initialize(space:, current_character_membership:, include_non_participating:, scenario_override:)
      @space = space
      @current_character_membership = current_character_membership
      @include_non_participating = include_non_participating
      @scenario_override = scenario_override
    end

    # @return [Hash]
    def call
      join_prefix = @space.prompt_settings&.join_prefix.to_s
      join_suffix = @space.prompt_settings&.join_suffix.to_s

      participants = @space.space_memberships.active.ai_characters.by_position.includes(:character).to_a

      if @current_character_membership&.character? && participants.none? { |p| p.id == @current_character_membership.id }
        participants << @current_character_membership
      end

      unless @include_non_participating
        participants.select! { |p| p.participation_active? || (@current_character_membership && p.id == @current_character_membership.id) }
      end

      description = join_character_field(
        participants,
        field_label: "Description",
        join_prefix: join_prefix,
        join_suffix: join_suffix
      ) { |char| char.data.description }

      scenario = join_character_field(
        participants,
        field_label: "Scenario",
        join_prefix: join_prefix,
        join_suffix: join_suffix
      ) do |char|
        @scenario_override.present? ? @scenario_override.to_s : char.data.scenario
      end

      personality = join_character_field(
        participants,
        field_label: "Personality",
        join_prefix: join_prefix,
        join_suffix: join_suffix
      ) { |char| char.data.personality }

      mes_example = join_character_field(
        participants,
        field_label: "Example Messages",
        join_prefix: join_prefix,
        join_suffix: join_suffix,
        replace_char_macro: false
      ) { |char| normalize_mes_example(char.data.mes_example) }

      overrides = {
        description: description,
        scenario: scenario,
        personality: personality,
        mes_example: mes_example,
      }.compact

      overrides
    end

    private

    def normalize_mes_example(value)
      v = value.to_s.strip
      return nil if v.empty?
      return v if v.start_with?("<START>")

      "<START>\n#{v}"
    end

    def join_character_field(participants, field_label:, join_prefix:, join_suffix:, replace_char_macro: true)
      segments = participants.filter_map do |participant_record|
        participant = ParticipantAdapter.to_participant(participant_record)
        next unless participant.is_a?(::TavernKit::Character)

        char_name = participant.name.to_s.presence || participant_record.display_name.to_s
        raw = yield(participant)
        next if raw.to_s.strip.empty?

        prefix = apply_join_template(join_prefix, character_name: char_name, field_label: field_label)
        suffix = apply_join_template(join_suffix, character_name: char_name, field_label: field_label)
        body = raw.to_s
        body = body.gsub(/\{\{char\}\}/i, char_name) if replace_char_macro

        +"#{prefix}#{body}#{suffix}"
      end

      return nil if segments.empty?

      segments.join("\n")
    end

    def apply_join_template(template, character_name:, field_label:)
      template
        .to_s
        .gsub(/\{\{char\}\}/i, character_name.to_s)
        .gsub(/<fieldname>/i, field_label.to_s)
    end
  end
end
