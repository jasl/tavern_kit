# frozen_string_literal: true

module Publishable
  extend ActiveSupport::Concern

  included do
    before_validation :set_published_at, on: :create
  end

  class_methods do
    # Access control scope:
    # - published_at < now: visible to everyone
    # - published_at IS NULL AND owner == user: visible only to owner
    #
    # "owner_column" is usually :user_id (but can be :owner_id for Space).
    def accessible_to(user, owner_column: :user_id, now: Time.current)
      published = arel_table[:published_at].lt(now)
      return where(published) unless user

      draft_owned = arel_table[:published_at].eq(nil).and(arel_table[owner_column].eq(user.id))
      where(published.or(draft_owned))
    end

    # Variant for "system records" (owner column is NULL) mixed with user-owned records.
    #
    # Access control scope:
    # - owner IS NULL AND published_at < now: visible to everyone
    # - owner == user AND (published_at < now OR published_at IS NULL): visible to owner
    def accessible_to_system_or_owned(user, owner_column: :user_id, now: Time.current)
      published = arel_table[:published_at].lt(now)
      system_published = arel_table[owner_column].eq(nil).and(published)
      return where(system_published) unless user

      owned_visible = arel_table[owner_column].eq(user.id).and(published.or(arel_table[:published_at].eq(nil)))
      where(system_published.or(owned_visible))
    end
  end

  private

  def set_published_at
    self.published_at = Time.zone.now if published_at.blank?
  end
end
