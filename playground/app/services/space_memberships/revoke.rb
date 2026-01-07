# frozen_string_literal: true

# Soft-removes memberships from a space for users and/or characters.
#
# This was previously implemented as an association extension on Space:
# `space.space_memberships.revoke_from(...)`.
#
module SpaceMemberships
  class Revoke
    def self.call(space:, actors:, by_user: nil, reason: nil)
      new(space: space, actors: actors, by_user: by_user, reason: reason).call
    end

    def initialize(space:, actors:, by_user:, reason:)
      @space = space
      @actors = Array(actors)
      @by_user = by_user
      @reason = reason
    end

    def call
      @actors.each do |actor|
        membership = find_membership(actor)
        membership&.remove!(by_user: @by_user, reason: @reason)
      end
    end

    private

    def find_membership(actor)
      if actor.is_a?(User)
        @space.space_memberships.find_by(user: actor)
      else
        @space.space_memberships.find_by(character: actor)
      end
    end
  end
end
