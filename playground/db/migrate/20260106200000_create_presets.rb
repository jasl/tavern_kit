# frozen_string_literal: true

class CreatePresets < ActiveRecord::Migration[8.0]
  def change
    create_table :presets do |t|
      t.string :name, null: false
      t.text :description

      # Associated LLM provider (optional - nil means no provider preference)
      t.references :llm_provider, foreign_key: true

      # Settings stored as JSONB
      t.jsonb :generation_settings, null: false, default: {}
      t.jsonb :preset_settings, null: false, default: {}

      # Ownership: nil = system preset, otherwise user-created
      t.references :user, foreign_key: true

      # Default preset flag
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end

    # Unique name per user (nil user = system presets share namespace)
    add_index :presets, [:user_id, :name], unique: true

    # Add preset_id to space_memberships to track currently selected preset
    add_reference :space_memberships, :preset, foreign_key: true
  end
end
