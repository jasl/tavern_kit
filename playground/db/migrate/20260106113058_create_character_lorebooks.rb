# frozen_string_literal: true

class CreateCharacterLorebooks < ActiveRecord::Migration[8.1]
  def change
    create_table :character_lorebooks do |t|
      t.references :character, null: false, foreign_key: { on_delete: :cascade }
      t.references :lorebook, null: false, foreign_key: { on_delete: :cascade }
      t.string :source, null: false, default: "additional"
      t.integer :priority, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.jsonb :settings, null: false, default: {}
      t.check_constraint "jsonb_typeof(settings) = 'object'", name: "character_lorebooks_settings_object"

      t.timestamps

      # Unique constraint: a character can only link to a lorebook once
      t.index %i[character_id lorebook_id], unique: true
      # Partial unique index: only one primary lorebook per character
      t.index :character_id,
              unique: true,
              where: "source = 'primary'",
              name: "index_character_lorebooks_one_primary_per_character"
      # Index for priority ordering
      t.index %i[character_id priority]
    end
  end
end
