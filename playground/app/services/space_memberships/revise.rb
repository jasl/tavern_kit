# frozen_string_literal: true

# Applies a "grant + revoke" change set to a space's memberships atomically.
#
# This was previously implemented as an association extension on Space:
# `space.space_memberships.revise(granted: ..., revoked: ...)`.
#
module SpaceMemberships
  class Revise
    def self.execute(space:, granted: [], revoked: [], by_user: nil, reason: nil)
      new(space: space, granted: granted, revoked: revoked, by_user: by_user, reason: reason).execute
    end

    def initialize(space:, granted:, revoked:, by_user:, reason:)
      @space = space
      @granted = Array(granted)
      @revoked = Array(revoked)
      @by_user = by_user
      @reason = reason
    end

    def execute
      @space.transaction do
        Grant.execute(space: @space, actors: @granted) if @granted.present?
        Revoke.execute(space: @space, actors: @revoked, by_user: @by_user, reason: @reason) if @revoked.present?
      end
    end

    # Backward-compat shim for older call sites.
    def call
      execute
    end

    private :call
  end
end
