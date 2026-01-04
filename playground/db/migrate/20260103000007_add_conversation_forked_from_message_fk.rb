# frozen_string_literal: true

class AddConversationForkedFromMessageFk < ActiveRecord::Migration[8.1]
  def change
    change_table :conversations do |t|
      t.references :forked_from_message, foreign_key: { to_table: :messages }
    end
  end
end
