# frozen_string_literal: true

class AddVariablesToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :variables, :jsonb, default: {}, null: false
  end
end
