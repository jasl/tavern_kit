class CreateSpaces < ActiveRecord::Migration[8.1]
  def change
    create_table :spaces do |t|
      t.string :name, null: false
      t.string :type, null: false

      t.references :owner, null: false, foreign_key: { to_table: :users }

      t.jsonb :settings, null: false, default: {}
      t.integer :settings_version, null: false, default: 0

      t.string :status, null: false, default: "active"  # active, archived, deleting

      t.string :reply_order, null: false, default: "natural"
      t.string :card_handling_mode, null: false, default: "swap"
      t.boolean :auto_mode_enabled, null: false, default: false
      t.integer :auto_mode_delay_ms, null: false, default: 5000
      t.string :during_generation_user_input_policy, null: false, default: "queue"
      t.integer :user_turn_debounce_ms, null: false, default: 0
      t.boolean :allow_self_responses, null: false, default: false
      t.string :group_regenerate_mode, null: false, default: "single_message"
      t.boolean :relax_message_trim, null: false, default: false

      t.timestamps
    end
  end
end
