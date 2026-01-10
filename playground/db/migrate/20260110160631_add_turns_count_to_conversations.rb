class AddTurnsCountToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :turns_count, :integer, default: 0, null: false
  end
end
