class AddAuthorsNoteSettingsToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :authors_note_position, :string
    add_column :conversations, :authors_note_depth, :integer
    add_column :conversations, :authors_note_role, :string
  end
end
