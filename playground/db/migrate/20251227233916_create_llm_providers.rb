class CreateLLMProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_providers do |t|
      t.string :name, null: false, index: { unique: true }
      t.string :identification, null: false, default: "openai_compatible"
      t.string :base_url, null: false
      t.text :api_key
      t.string :model
      t.boolean :streamable, default: true

      t.datetime :last_tested_at

      t.timestamps
    end
  end
end
