# frozen_string_literal: true

# Creates a space with its initial conversation + memberships + greeting messages.
#
# This is intentionally Rails-app-layer code (uses AR and transactions).
#
module Spaces
  class Creator
    def self.execute(space_class:, attributes:, user:, characters:, owner_membership: nil, lorebook_ids: nil)
      new(
        space_class: space_class,
        attributes: attributes,
        user: user,
        characters: characters,
        owner_membership: owner_membership,
        lorebook_ids: lorebook_ids
      ).execute
    end

    def initialize(space_class:, attributes:, user:, characters:, owner_membership:, lorebook_ids:)
      @space_class = space_class
      @attributes = attributes
      @user = user
      @characters = Array(characters)
      @owner_membership = owner_membership
      @lorebook_ids = Array(lorebook_ids).map(&:to_i).reject(&:zero?).uniq
    end

    def execute
      call
    end

    def call
      raise ArgumentError, "At least one character is required" if @characters.blank?

      attrs = @attributes.to_h.symbolize_keys

      attrs[:owner] = @user
      attrs[:name] = default_name_for(@characters) if attrs[:name].blank?

      owner_persona = owner_persona_from(@owner_membership)
      owner_name_override = owner_name_override_from(@owner_membership)
      owner_persona_character_id = owner_persona_character_id_from(@owner_membership)

      validate_owner_persona_character!(attrs, persona_character_id: owner_persona_character_id)
      lorebooks = resolve_lorebooks!(attrs, lorebook_ids: @lorebook_ids)

      @space_class.transaction do
        @space_class.create!(attrs).tap do |space|
          conversation = space.conversations.create!(title: "Main")

          attach_lorebooks!(space, lorebooks)

          grant_owner_membership!(
            space,
            persona: owner_persona,
            name_override: owner_name_override,
            persona_character_id: owner_persona_character_id
          )

          SpaceMemberships::Grant.execute(space: space, actors: @characters)

          conversation.create_first_messages!
        end
      end
    end

    private :call

    private

    def resolve_lorebooks!(space_attrs, lorebook_ids:)
      ids = Array(lorebook_ids).map(&:to_i).reject(&:zero?).uniq
      return [] if ids.empty?

      scope = Lorebook.accessible_to(@user).where(id: ids)
      lorebooks = scope.to_a

      lorebooks_by_id = lorebooks.index_by(&:id)
      missing_ids = ids - lorebooks_by_id.keys

      return ids.filter_map { |id| lorebooks_by_id[id] } if missing_ids.empty?

      invalid_space = @space_class.new(space_attrs)
      invalid_space.errors.add(:base, "One or more lorebooks are not available")
      raise ActiveRecord::RecordInvalid, invalid_space
    end

    def attach_lorebooks!(space, lorebooks)
      Array(lorebooks).each do |lorebook|
        space.space_lorebooks.create!(lorebook: lorebook, source: "global")
      end
    end

    def owner_membership_hash(owner_membership)
      return {} if owner_membership.nil?

      h = owner_membership.respond_to?(:to_h) ? owner_membership.to_h : {}
      h = h.deep_symbolize_keys if h.respond_to?(:deep_symbolize_keys)
      h
    end

    def owner_persona_from(owner_membership)
      h = owner_membership_hash(owner_membership)
      h[:persona].to_s.strip.presence
    end

    def owner_name_override_from(owner_membership)
      h = owner_membership_hash(owner_membership)
      h[:name_override].to_s.strip.presence
    end

    def owner_persona_character_id_from(owner_membership)
      h = owner_membership_hash(owner_membership)
      raw = h[:persona_character_id] || h[:character_id]
      id = raw.to_i
      id.positive? ? id : nil
    end

    def validate_owner_persona_character!(space_attrs, persona_character_id:)
      return if persona_character_id.nil?

      if @characters.any? { |c| c.id == persona_character_id }
        invalid_space = @space_class.new(space_attrs)
        invalid_space.errors.add(:base, "Persona character cannot also be selected as an AI participant")
        raise ActiveRecord::RecordInvalid, invalid_space
      end

      # Ensure the persona character is accessible to the creating user and ready.
      available =
        Character
          .accessible_to(@user)
          .ready
          .where(id: persona_character_id)
          .exists?

      return if available

      invalid_space = @space_class.new(space_attrs)
      invalid_space.errors.add(:base, "Persona character is not available")
      raise ActiveRecord::RecordInvalid, invalid_space
    end

    def grant_owner_membership!(space, persona:, name_override:, persona_character_id:)
      grant_options = { role: "owner" }
      grant_options[:name_override] = name_override if name_override.present?
      grant_options[:persona] = persona if persona.present?

      SpaceMemberships::Grant.execute(space: space, actors: @user, **grant_options)

      return if persona_character_id.nil?

      membership = space.space_memberships.find_by!(user_id: @user.id, kind: "human")
      membership.update!(character_id: persona_character_id)
    end

    def default_name_for(characters)
      names = Array(characters).filter_map(&:name).map(&:strip).compact_blank
      return "New Space" if names.empty?
      return names.first if names.size == 1

      names.join(", ").truncate(60)
    end
  end
end
