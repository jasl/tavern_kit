class AddAuthorsNoteToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :authors_note, :text
  end
end
