# frozen_string_literal: true

class RenameSpacesSettingsToPromptSettings < ActiveRecord::Migration[8.1]
  def change
    # Rename the column
    rename_column :spaces, :settings, :prompt_settings

    # Update the check constraint name to match the new column name
    remove_check_constraint :spaces, name: "spaces_settings_object"
    add_check_constraint :spaces, "jsonb_typeof(prompt_settings) = 'object'", name: "spaces_prompt_settings_object"
  end
end
