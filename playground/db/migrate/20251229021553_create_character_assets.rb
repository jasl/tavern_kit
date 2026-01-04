class CreateCharacterAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :character_assets do |t|
      t.references :character, null: false, foreign_key: true
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }

      t.string :kind, null: false, default: "icon"  # icon, emotion, background, user_icon, other
      t.string :name, null: false                   # asset name from spec (unique per character)
      t.string :ext                                 # file extension
      t.string :content_sha256, index: true         # for asset reuse (storage optimization)

      t.timestamps

      t.index %i[character_id name], unique: true
    end
  end
end
