# frozen_string_literal: true

module PromptBuilding
  # Resolve Author's Note settings with the 4-layer priority chain.
  #
  # Priority (highest to lowest):
  # 1. Conversation.authors_note
  # 2. SpaceMembership.settings.preset.authors_note
  # 3. Character.authors_note (if enabled by membership setting)
  # 4. Space.prompt_settings.preset.authors_note
  #
  # Note: Author's Note *metadata* (position/depth/role/frequency/allow_wi_scan) is resolved from:
  # - Conversation overrides (when present)
  # - SpaceMembership.settings.preset (when present)
  # - Character-level defaults (when applicable)
  # - Space.prompt_settings.preset (fallback)
  #
  class AuthorsNoteResolver
    def initialize(conversation:, speaker:, preset_settings:)
      @conversation = conversation
      @speaker = speaker
      @preset_settings = preset_settings
    end

    # @return [Hash] overrides hash with resolved AN settings
    def call
      overrides = {}
      sm_preset_settings = speaker_preset_settings

      # Layer 1: Conversation-level (highest priority)
      if @conversation.authors_note.present?
        overrides[:authors_note] = @conversation.authors_note
        apply_conversation_authors_note_metadata(overrides, sm_preset_settings: sm_preset_settings)
        apply_allow_wi_scan(overrides, sm_preset_settings: sm_preset_settings)
        return overrides
      end

      # Layer 2 & 3: SpaceMembership and Character level
      if @speaker&.character?
        sm_an = sm_preset_settings&.authors_note.presence
        char_an = @speaker.character&.authors_note if @speaker.use_character_authors_note?

        if sm_an.present? || char_an.present?
          combined_an = combine_character_authors_note(
            space_an: @preset_settings&.authors_note.to_s.presence,
            sm_an: sm_an,
            char_an: char_an,
            position: @speaker.character_authors_note_position
          )

          if combined_an.present?
            overrides[:authors_note] = combined_an
            apply_authors_note_metadata_from_speaker(overrides, sm_preset_settings: sm_preset_settings)
            apply_allow_wi_scan(overrides, sm_preset_settings: sm_preset_settings)
            return overrides
          end
        end
      end

      # Layer 4: Space preset level (fallback)
      overrides[:authors_note] = @preset_settings.authors_note.to_s if @preset_settings&.authors_note.present?
      apply_authors_note_metadata(overrides, sm_preset_settings: sm_preset_settings)
      apply_allow_wi_scan(overrides, sm_preset_settings: sm_preset_settings)
      overrides
    end

    private

    def normalize_non_negative_integer(value)
      return nil if value.nil?

      n = Integer(value)
      n.negative? ? 0 : n
    rescue ArgumentError, TypeError
      nil
    end

    def combine_character_authors_note(space_an:, sm_an:, char_an:, position:)
      effective_char_an = sm_an.presence || char_an
      return nil if effective_char_an.blank?

      case position
      when "before"
        [effective_char_an, space_an].compact.join("\n")
      when "after"
        [space_an, effective_char_an].compact.join("\n")
      else # "replace"
        effective_char_an
      end
    end

    def apply_authors_note_metadata(overrides, sm_preset_settings:)
      source = sm_preset_settings || @preset_settings
      return unless source

      if source.authors_note_frequency
        overrides[:authors_note_frequency] = normalize_non_negative_integer(source.authors_note_frequency)
      end

      if source.authors_note_position.present?
        overrides[:authors_note_position] = ::TavernKit::Coerce.authors_note_position(source.authors_note_position)
      end

      if source.authors_note_depth
        overrides[:authors_note_depth] = normalize_non_negative_integer(source.authors_note_depth)
      end

      if source.authors_note_role.present?
        overrides[:authors_note_role] = ::TavernKit::Coerce.role(source.authors_note_role)
      end
    end

    def apply_conversation_authors_note_metadata(overrides, sm_preset_settings:)
      position = @conversation.authors_note_position.presence ||
        sm_preset_settings&.authors_note_position.presence ||
        @preset_settings&.authors_note_position
      overrides[:authors_note_position] = ::TavernKit::Coerce.authors_note_position(position) if position

      depth = @conversation.authors_note_depth ||
        sm_preset_settings&.authors_note_depth ||
        @preset_settings&.authors_note_depth
      overrides[:authors_note_depth] = normalize_non_negative_integer(depth) if depth

      role = @conversation.authors_note_role.presence ||
        sm_preset_settings&.authors_note_role.presence ||
        @preset_settings&.authors_note_role
      overrides[:authors_note_role] = ::TavernKit::Coerce.role(role) if role

      frequency = sm_preset_settings&.authors_note_frequency || @preset_settings&.authors_note_frequency
      overrides[:authors_note_frequency] = normalize_non_negative_integer(frequency) if frequency
    end

    def apply_authors_note_metadata_from_speaker(overrides, sm_preset_settings:)
      return apply_authors_note_metadata(overrides, sm_preset_settings: sm_preset_settings) unless @speaker&.character?

      char = @speaker.character

      position = sm_preset_settings&.authors_note_position.presence ||
                 char&.authors_note_position ||
                 @preset_settings&.authors_note_position
      overrides[:authors_note_position] = ::TavernKit::Coerce.authors_note_position(position) if position

      depth = sm_preset_settings&.authors_note_depth ||
              char&.authors_note_depth ||
              @preset_settings&.authors_note_depth
      overrides[:authors_note_depth] = normalize_non_negative_integer(depth) if depth

      role = sm_preset_settings&.authors_note_role.presence ||
             char&.authors_note_role ||
             @preset_settings&.authors_note_role
      overrides[:authors_note_role] = ::TavernKit::Coerce.role(role) if role

      frequency = sm_preset_settings&.authors_note_frequency || @preset_settings&.authors_note_frequency
      overrides[:authors_note_frequency] = normalize_non_negative_integer(frequency) if frequency
    end

    def apply_allow_wi_scan(overrides, sm_preset_settings:)
      source = sm_preset_settings || @preset_settings
      return unless source

      overrides[:authors_note_allow_wi_scan] = source.authors_note_allow_wi_scan == true
    end

    def speaker_preset_settings
      return nil unless @speaker

      preset = @speaker.settings&.preset
      return nil unless preset

      defaults = ::ConversationSettings::PresetSettings.new

      same_as_defaults =
        preset.authors_note.to_s == defaults.authors_note.to_s &&
          preset.authors_note_frequency.to_i == defaults.authors_note_frequency.to_i &&
          preset.authors_note_position.to_s == defaults.authors_note_position.to_s &&
          preset.authors_note_depth.to_i == defaults.authors_note_depth.to_i &&
          preset.authors_note_role.to_s == defaults.authors_note_role.to_s &&
          (preset.authors_note_allow_wi_scan == true) == (defaults.authors_note_allow_wi_scan == true)

      same_as_defaults ? nil : preset
    end
  end
end
