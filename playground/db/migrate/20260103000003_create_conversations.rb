# frozen_string_literal: true

class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :space, null: false, foreign_key: true
      t.string :kind, null: false, default: "root" # root, branch, thread
      t.string :title, null: false
      t.text :authors_note

      t.jsonb :variables, null: false, default: {}
      t.check_constraint "jsonb_typeof(variables) = 'object'", name: "conversations_variables_object"

      t.string :visibility, null: false, index: true, default: "shared"

      # Tree structure fields
      t.references :parent_conversation, foreign_key: { to_table: :conversations }
      t.references :root_conversation, foreign_key: { to_table: :conversations }

      t.string :authors_note_position
      t.integer :authors_note_depth
      t.string :authors_note_role

      t.timestamps
    end
  end
end
