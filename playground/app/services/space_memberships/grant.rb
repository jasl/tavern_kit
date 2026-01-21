# frozen_string_literal: true

# Grants (or restores) memberships in a space for users and/or characters.
#
# This was previously implemented as an association extension on Space:
# `space.space_memberships.grant_to(...)`.
#
module SpaceMemberships
  class Grant
    def self.execute(space:, actors:, **options)
      new(space: space, actors: actors, options: options).execute
    end

    def initialize(space:, actors:, options:)
      @space = space
      @actors = Array(actors)
      @options = options
    end

    def execute
      next_position = @space.space_memberships.maximum(:position) || -1

      @actors.each do |actor|
        membership = find_or_initialize_membership(actor)

        attrs = {}

        if membership.new_record? || membership.removed_membership?
          next_position += 1
          attrs[:position] = next_position
        end

        # Restore active status and participation
        attrs[:status] = "active"
        attrs[:participation] = "active"
        attrs[:removed_at] = nil
        attrs[:removed_by] = nil
        attrs[:removed_reason] = nil

        attrs[:persona] = @options[:persona] if @options.key?(:persona)
        attrs[:auto] = @options[:auto] if @options.key?(:auto)
        attrs[:role] = @options[:role] if @options.key?(:role)

        membership.assign_attributes(attrs)
        membership.save! if membership.changed?
      end
    end

    private

    def find_or_initialize_membership(actor)
      if actor.is_a?(User)
        @space.space_memberships.find_or_initialize_by(user_id: actor.id, kind: "human")
      else
        @space.space_memberships.find_or_initialize_by(character_id: actor.id, kind: "character")
      end
    end
  end
end
