class AddTurnQueueStateToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :turn_queue_state, :jsonb, default: {}, null: false
  end
end
