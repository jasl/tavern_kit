class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :key, null: false, index: { unique: true }
      t.jsonb :value

      t.timestamps
    end
  end
end
