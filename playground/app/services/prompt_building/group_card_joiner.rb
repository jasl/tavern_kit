# frozen_string_literal: true

module PromptBuilding
  class GroupCardJoiner
    def initialize(space:, speaker:, base_character_participant:, include_non_participating:, scenario_override:)
      @space = space
      @speaker = speaker
      @base_character_participant = base_character_participant
      @include_non_participating = include_non_participating
      @scenario_override = scenario_override
    end

    # @return [Hash]
    def call
      join_prefix = @space.prompt_settings&.join_prefix.to_s
      join_suffix = @space.prompt_settings&.join_suffix.to_s

      participants = @space.space_memberships.active.ai_characters.by_position.includes(:character).to_a

      if @speaker&.character? && participants.none? { |p| p.id == @speaker.id }
        participants << @speaker
      end

      unless @include_non_participating
        participants.select! { |p| p.participation_active? || (@speaker && p.id == @speaker.id) }
      end

      description = join_character_field(
        participants,
        field_name: "description",
        join_prefix: join_prefix,
        join_suffix: join_suffix
      ) { |char| char.data.description }

      scenario = join_character_field(
        participants,
        field_name: "scenario",
        join_prefix: join_prefix,
        join_suffix: join_suffix
      ) do |char|
        @scenario_override.present? ? @scenario_override.to_s : char.data.scenario
      end

      personality = join_character_field(
        participants,
        field_name: "personality",
        join_prefix: join_prefix,
        join_suffix: join_suffix
      ) { |char| char.data.personality }

      mes_example = join_character_field(
        participants,
        field_name: "mes_example",
        join_prefix: join_prefix,
        join_suffix: join_suffix
      ) { |char| char.data.mes_example }

      creator_notes = join_character_field(
        participants,
        field_name: "creator_notes",
        join_prefix: join_prefix,
        join_suffix: join_suffix
      ) { |char| char.data.creator_notes }

      depth_prompt = join_character_depth_prompt(
        participants,
        join_prefix: join_prefix,
        join_suffix: join_suffix
      )

      overrides = {
        description: description,
        scenario: scenario,
        personality: personality,
        mes_example: mes_example,
        creator_notes: creator_notes,
      }.compact

      if depth_prompt.present?
        extensions = (@base_character_participant.data.extensions || {}).deep_dup
        extensions = extensions.deep_stringify_keys
        depth_hash = extensions["depth_prompt"].is_a?(Hash) ? extensions["depth_prompt"].deep_dup : {}
        depth_hash = depth_hash.deep_stringify_keys
        depth_hash["prompt"] = depth_prompt
        depth_hash["depth"] ||= 4
        depth_hash["role"] ||= "system"
        extensions["depth_prompt"] = depth_hash
        overrides[:extensions] = extensions
      end

      overrides
    end

    private

    def join_character_depth_prompt(participants, join_prefix:, join_suffix:)
      join_character_field(
        participants,
        field_name: "depth_prompt",
        join_prefix: join_prefix,
        join_suffix: join_suffix
      ) do |char|
        extensions = char.data.extensions
        next nil unless extensions.is_a?(Hash)

        depth_hash = extensions["depth_prompt"] || extensions[:depth_prompt]
        next nil unless depth_hash.is_a?(Hash)

        depth_hash["prompt"] || depth_hash[:prompt]
      end
    end

    def join_character_field(participants, field_name:, join_prefix:, join_suffix:)
      segments =
        participants.filter_map do |participant_record|
                participant = ParticipantAdapter.to_participant(participant_record)
          next unless participant.is_a?(::TavernKit::Character)

          char_name = participant.name.to_s.presence || participant_record.display_name.to_s
          raw = yield(participant)
          next if raw.to_s.strip.empty?

          prefix = apply_join_template(join_prefix, character_name: char_name, field_name: field_name)
          suffix = apply_join_template(join_suffix, character_name: char_name, field_name: field_name)
          body = raw.to_s.gsub(/\{\{char\}\}/i, char_name)

          +"#{prefix}#{body}#{suffix}"
        end

      return nil if segments.empty?

      segments.join("\n")
    end

    def apply_join_template(template, character_name:, field_name:)
      template
        .to_s
        .gsub(/\{\{char\}\}/i, character_name.to_s)
        .gsub(/<fieldname>(?=>)/i, "#{field_name}>")
        .gsub(/<fieldname>/i, field_name.to_s)
    end
  end
end
