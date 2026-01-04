# frozen_string_literal: true

# PermissionPolicy centralizes Space authorization checks.
#
# Space permissions are based on a user's active (non-muted) human SpaceMembership.
class PermissionPolicy
  class << self
    def can_read_space?(user, space)
      active_membership(user, space).present?
    end

    def can_write_space?(user, space)
      return false unless space&.active?

      can_read_space?(user, space)
    end

    def can_manage_space?(user, space)
      membership = active_membership(user, space)
      return false unless membership

      membership.role_owner? || membership.role_moderator? || user&.administrator?
    end

    private

    def active_membership(user, space)
      return nil unless user && space

      space.space_memberships.active.find_by(user_id: user.id, kind: "human")
    end
  end
end
