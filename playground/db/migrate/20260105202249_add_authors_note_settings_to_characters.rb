class AddAuthorsNoteSettingsToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :authors_note_settings, :jsonb, default: {}, null: false
  end
end
