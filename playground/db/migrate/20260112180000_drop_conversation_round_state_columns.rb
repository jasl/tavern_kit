# frozen_string_literal: true

class DropConversationRoundStateColumns < ActiveRecord::Migration[8.1]
  def change
    remove_index :conversations, :scheduling_state

    remove_column :conversations, :scheduling_state, :string, default: "idle", null: false
    remove_column :conversations, :current_round_id, :uuid
    remove_column :conversations, :current_speaker_id, :bigint
    remove_column :conversations, :round_position, :integer, default: 0, null: false
    remove_column :conversations, :round_queue_ids, :bigint, array: true, default: [], null: false
    remove_column :conversations, :round_spoken_ids, :bigint, array: true, default: [], null: false
  end
end
