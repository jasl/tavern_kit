# frozen_string_literal: true

module Characters
  # Resolve a character's linked lorebooks from soft-link names.
  #
  # Source of truth:
  # - character.data.extensions.world (String)
  # - character.data.extensions.extra_worlds (Array<String>)
  #
  # Resolution is done with ownership-aware name lookup via Lorebooks::NameResolver.
  class LorebookLinks
    Result =
      Struct.new(
        :primary_name,
        :primary_lorebook,
        :primary_duplicates,
        :additional_names,
        :additional_lorebooks_by_name,
        :additional_duplicates_by_name,
        :not_found_names,
        keyword_init: true
      )

    def initialize(character:, user:, resolver: Lorebooks::NameResolver.new)
      @character = character
      @user = user
      @resolver = resolver
    end

    def call
      primary_name = @character.data&.world_name
      additional_names = Array(@character.data&.extra_world_names)
      additional_names = normalize_names(additional_names)

      primary_lorebook = primary_name ? @resolver.resolve(user: @user, name: primary_name) : nil
      primary_duplicates = duplicates_for(name: primary_name, resolved: primary_lorebook)

      additional_by_name = {}
      additional_duplicates_by_name = {}
      not_found = []

      additional_names.each do |name|
        lorebook = @resolver.resolve(user: @user, name: name)
        if lorebook
          additional_by_name[name] = lorebook
          additional_duplicates_by_name[name] = duplicates_for(name: name, resolved: lorebook)
        else
          not_found << name
        end
      end

      Result.new(
        primary_name: primary_name,
        primary_lorebook: primary_lorebook,
        primary_duplicates: primary_duplicates,
        additional_names: additional_names,
        additional_lorebooks_by_name: additional_by_name,
        additional_duplicates_by_name: additional_duplicates_by_name,
        not_found_names: not_found
      )
    end

    private

    def duplicates_for(name:, resolved:)
      return [] unless resolved

      Lorebook
        .accessible_to_system_or_owned(@user)
        .where(name: name.to_s.strip)
        .where.not(id: resolved.id)
        .includes(:user)
        .order(updated_at: :desc, id: :desc)
        .to_a
    end

    def normalize_names(names)
      names
        .map { |n| n.to_s.strip }
        .reject(&:empty?)
        .uniq
    end
  end
end
