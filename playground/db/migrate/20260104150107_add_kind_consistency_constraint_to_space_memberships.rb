# frozen_string_literal: true

# Adds a database-level check constraint to ensure SpaceMembership kind/column consistency.
#
# Rules enforced:
# - kind='character' => user_id IS NULL AND (character_id IS NOT NULL OR status='removed')
# - kind='human' => user_id IS NOT NULL (character_id can be present for persona)
#
# Note: Removed AI character memberships may have NULL character_id when the
# original character is deleted. The display_name_cache preserves the name.
#
# This complements the ActiveRecord validation and prevents invalid data from
# being inserted via raw SQL or database triggers.
class AddKindConsistencyConstraintToSpaceMemberships < ActiveRecord::Migration[8.1]
  def up
    add_check_constraint :space_memberships,
      <<~SQL.squish,
        (kind = 'character' AND user_id IS NULL AND (character_id IS NOT NULL OR status = 'removed'))
        OR
        (kind = 'human' AND user_id IS NOT NULL)
      SQL
      name: "space_memberships_kind_consistency"
  end

  def down
    remove_check_constraint :space_memberships, name: "space_memberships_kind_consistency"
  end
end
