class CreateSpaceMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :space_memberships do |t|
      t.references :space, null: false, foreign_key: true
      t.string :kind, null: false, default: "human"  # human, character

      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :character, foreign_key: { on_delete: :nullify }
      t.references :llm_provider, foreign_key: true

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
