# frozen_string_literal: true

class AddRoundQueueIdsToConversations < ActiveRecord::Migration[8.0]
  def change
    # Persist the activated speaker queue for the current round.
    # This avoids recomputing random activation (natural/pooled) mid-round.
    add_column :conversations, :round_queue_ids, :bigint, array: true, default: [], null: false
  end
end
