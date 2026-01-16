# frozen_string_literal: true

# Presenter for the shared Character profile page partial.
#
# Encapsulates:
# - "public" vs "settings" mode behavior
# - editability rules
# - path helpers
#
# Keeps the ERB partial focused on structure/styling.
class CharacterProfilePresenter
  include Rails.application.routes.url_helpers

  attr_reader :character

  def initialize(character:, mode:)
    @character = character
    @mode = mode.to_sym
  end

  def settings_mode?
    @mode == :settings
  end

  def global?
    character.user_id.nil?
  end

  def owner?
    character.user_id == Current.user&.id
  end

  def can_edit?
    return !character.locked? if settings_mode?

    owner? && !character.locked?
  end

  def index_path
    settings_mode? ? settings_characters_path : characters_path
  end

  def edit_path
    settings_mode? ? edit_settings_character_path(character) : edit_character_path(character)
  end

  def locked_hint
    I18n.t(
      "characters.show.locked_hint",
      default: settings_mode? ? "Locked characters cannot be edited or deleted. Unlock to make changes." : "Locked characters cannot be edited or deleted."
    )
  end
end
