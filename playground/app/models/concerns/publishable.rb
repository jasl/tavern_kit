# frozen_string_literal: true

# Visibility-based access control concern.
#
# Models including this concern use a `visibility` column (string enum)
# to control who can access records.
#
# Visibility values:
# - "private": Only the owner can see/use this record
# - "public": Anyone can see/use this record
#
# Some models (e.g., Conversation) may have additional visibility values
# like "shared" (visible to space participants).
#
module Publishable
  extend ActiveSupport::Concern

  VISIBILITIES = %w[private public].freeze

  class_methods do
    # Access control scope for user-owned records.
    #
    # Returns records that are either:
    # - public (visibility = "public")
    # - owned by the user (owner_column = user.id)
    #
    # @param user [User, nil] the current user
    # @param owner_column [Symbol] the column name for ownership (default: :user_id)
    # @return [ActiveRecord::Relation]
    def accessible_to(user, owner_column: :user_id)
      public_records = arel_table[:visibility].eq("public")
      return where(public_records) unless user

      owned = arel_table[owner_column].eq(user.id)
      where(public_records.or(owned))
    end

    # Access control scope for system + user-owned records.
    #
    # Returns records that are either:
    # - system records (owner_column IS NULL) AND public
    # - owned by the user (any visibility)
    #
    # @param user [User, nil] the current user
    # @param owner_column [Symbol] the column name for ownership (default: :user_id)
    # @return [ActiveRecord::Relation]
    def accessible_to_system_or_owned(user, owner_column: :user_id)
      system_public = arel_table[owner_column].eq(nil).and(arel_table[:visibility].eq("public"))
      return where(system_public) unless user

      owned = arel_table[owner_column].eq(user.id)
      where(system_public.or(owned))
    end
  end

  # Check if the record is public (visible to everyone).
  # Note: Uses direct string comparison since enum methods have suffix.
  #
  # @return [Boolean]
  def published?
    visibility == "public"
  end

  # Check if the record is private (only visible to owner).
  # Note: Uses direct string comparison since enum methods have suffix.
  #
  # @return [Boolean]
  def draft?
    visibility == "private"
  end

  # Make the record public (bypasses callbacks, works even if locked).
  #
  # @return [Boolean] true if the update succeeded
  def publish!
    update_column(:visibility, "public")
  end

  # Make the record private (bypasses callbacks, works even if locked).
  #
  # @return [Boolean] true if the update succeeded
  def unpublish!
    update_column(:visibility, "private")
  end
end
