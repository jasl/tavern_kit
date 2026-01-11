# frozen_string_literal: true

class AddGroupQueueRevisionToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :group_queue_revision, :bigint, null: false, default: 0
  end
end
