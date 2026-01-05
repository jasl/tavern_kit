# frozen_string_literal: true

class CreateLorebooks < ActiveRecord::Migration[8.1]
  def change
    create_table :lorebooks do |t|
      t.string :name, null: false
      t.text :description
      t.integer :scan_depth, default: 2
      t.integer :token_budget
      t.boolean :recursive_scanning, default: false, null: false
      t.jsonb :settings, default: {}, null: false

      t.timestamps
    end

    add_index :lorebooks, :name
  end
end
