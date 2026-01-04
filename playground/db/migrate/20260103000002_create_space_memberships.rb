class CreateSpaceMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :space_memberships do |t|
      t.references :space, null: false, foreign_key: true
      t.string :kind, null: false, default: "human"  # human, character

      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :character, foreign_key: { on_delete: :nullify }
      t.references :llm_provider, foreign_key: true

      # Adds a database-level check constraint to ensure SpaceMembership kind/column consistency.
      #
      # Rules enforced:
      # - kind='character' => user_id IS NULL AND (character_id IS NOT NULL OR status='removed')
      # - kind='human' => user_id IS NOT NULL (character_id can be present for persona)
      #
      # Note: Removed AI character memberships may have NULL character_id when the
      # original character is deleted. The cached_display_name preserves the name.
      #
      # This complements the ActiveRecord validation and prevents invalid data from
      # being inserted via raw SQL or database triggers.
      t.check_constraint <<~SQL.squish,
        (kind = 'character' AND user_id IS NULL AND (character_id IS NOT NULL OR status = 'removed'))
        OR
        (kind = 'human' AND user_id IS NOT NULL)
      SQL
         name: "space_memberships_kind_consistency"
      t.string :cached_display_name

      t.string :status, null: false, index: true, default: "active"
      t.string :participation, null: false, index: true, default: "active"

      t.string :role, null: false, default: "member" # owner, member, moderator
      t.integer :position, null: false, default: 0

      t.text :persona
      t.jsonb :settings, null: false, default: {}
      t.integer :settings_version, null: false, default: 0

      t.string :copilot_mode, null: false, default: "none"
      t.integer :copilot_remaining_steps

      t.datetime :removed_at
      t.references :removed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :removed_reason

      t.datetime :unread_at
      t.timestamps

      t.index %i[space_id user_id], unique: true, where: "user_id IS NOT NULL"
      t.index %i[space_id character_id], unique: true, where: "character_id IS NOT NULL"
    end
  end
end
