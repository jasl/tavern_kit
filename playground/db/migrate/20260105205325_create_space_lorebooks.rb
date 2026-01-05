# frozen_string_literal: true

class CreateSpaceLorebooks < ActiveRecord::Migration[8.1]
  def change
    create_table :space_lorebooks do |t|
      t.references :space, null: false, foreign_key: { on_delete: :cascade }
      t.references :lorebook, null: false, foreign_key: { on_delete: :cascade }
      t.string :source, default: "global", null: false
      t.integer :priority, default: 0, null: false
      t.boolean :enabled, default: true, null: false

      t.timestamps

      t.index %i[space_id lorebook_id], unique: true
      t.index %i[space_id priority]
    end
  end
end
