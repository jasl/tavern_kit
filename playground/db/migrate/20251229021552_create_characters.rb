class CreateCharacters < ActiveRecord::Migration[8.1]
  def change
    create_table :characters do |t|
      # Spec version
      t.integer :spec_version # 2 or 3
      # Common display/search fields (extracted from data for query performance)
      t.string :name, null: false, index: true
      t.string :nickname
      t.text :personality
      t.string :tags, array: true, null: false, index: { using: :gin }, default: []
      t.string :supported_languages, array: true, null: false, default: []  # CCv3 creator_notes_multilingual keys

      # Complete spec data (jsonb stores all valid fields, see TavernKit::Character::Data)
      t.jsonb :data, null: false, default: {}
      t.check_constraint "jsonb_typeof(data) = 'object'", name: "characters_data_object"

      # Import deduplication: original file SHA256, cleared on edit to allow re-import
      t.string :file_sha256, index: true

      t.jsonb :authors_note_settings, null: false, default: {}
      t.check_constraint "jsonb_typeof(authors_note_settings) = 'object'", name: "characters_authors_note_settings_object"

      # Status management (string enum)
      t.string :status, null: false, default: "pending"  # pending, ready, failed, deleting

      t.timestamps
    end
  end
end
