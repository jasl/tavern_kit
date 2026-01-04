class CreateMessageSwipes < ActiveRecord::Migration[8.1]
  def change
    create_table :message_swipes do |t|
      t.references :message, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false, default: 0
      t.text :content
      t.jsonb :metadata, null: false, default: {}
      t.references :conversation_run, type: :uuid, foreign_key: { on_delete: :nullify }

      t.timestamps

      t.index %i[message_id position], unique: true
    end

    change_table :messages do |t|
      t.references :active_message_swipe, foreign_key: { to_table: :message_swipes, on_delete: :nullify }
      t.integer :message_swipes_count, null: false, default: 0
    end
  end
end
