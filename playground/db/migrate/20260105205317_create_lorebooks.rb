# frozen_string_literal: true

class CreateLorebooks < ActiveRecord::Migration[8.1]
  def change
    create_table :lorebooks do |t|
      t.string :name, null: false, index: true
      t.text :description
      t.integer :scan_depth, default: 2
      t.integer :token_budget
      t.boolean :recursive_scanning, default: false, null: false
      t.jsonb :settings, null: false, default: {}
      t.check_constraint "jsonb_typeof(settings) = 'object'", name: "lorebooks_settings_object"

      t.timestamps
    end
  end
end
