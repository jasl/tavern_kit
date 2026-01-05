# frozen_string_literal: true

class CreateLorebookEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :lorebook_entries do |t|
      t.references :lorebook, null: false, foreign_key: { on_delete: :cascade }
      t.string :uid, null: false
      t.string :comment
      t.text :keys, array: true, default: [], null: false
      t.text :secondary_keys, array: true, default: [], null: false
      t.text :content
      t.boolean :enabled, default: true, null: false
      t.boolean :constant, default: false, null: false
      t.integer :insertion_order, default: 100, null: false
      t.string :position, default: "after_char_defs", null: false
      t.integer :depth, default: 4, null: false
      t.string :role, default: "system", null: false
      t.string :outlet
      t.boolean :selective, default: false, null: false
      t.string :selective_logic, default: "and_any", null: false
      t.integer :probability, default: 100, null: false
      t.boolean :use_probability, default: true, null: false
      t.string :group
      t.integer :group_weight, default: 100, null: false
      t.boolean :group_override, default: false, null: false
      t.boolean :use_group_scoring
      t.integer :sticky
      t.integer :cooldown
      t.integer :delay
      t.boolean :exclude_recursion, default: false, null: false
      t.boolean :prevent_recursion, default: false, null: false
      t.integer :scan_depth
      t.boolean :case_sensitive
      t.boolean :match_whole_words
      t.boolean :match_persona_description, default: false, null: false
      t.boolean :match_character_description, default: false, null: false
      t.boolean :match_character_personality, default: false, null: false
      t.boolean :match_character_depth_prompt, default: false, null: false
      t.boolean :match_scenario, default: false, null: false
      t.boolean :match_creator_notes, default: false, null: false
      t.boolean :ignore_budget, default: false, null: false
      t.string :triggers, array: true, default: [], null: false
      t.string :automation_id
      t.integer :position_index, default: 0, null: false

      t.timestamps
    end

    add_index :lorebook_entries, [:lorebook_id, :uid], unique: true
    add_index :lorebook_entries, [:lorebook_id, :position_index]
    add_index :lorebook_entries, :enabled
  end
end
