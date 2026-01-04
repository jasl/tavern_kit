class CreateCharacterUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :character_uploads do |t|
      t.references :user, null: false, foreign_key: true
      t.references :character, foreign_key: true  # linked after successful import

      t.string :status, default: "pending", null: false  # pending, processing, completed, failed
      t.string :filename
      t.string :content_type
      t.text :error_message

      t.timestamps
    end
  end
end
