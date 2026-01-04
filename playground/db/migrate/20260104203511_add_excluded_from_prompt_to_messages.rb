class AddExcludedFromPromptToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :excluded_from_prompt, :boolean, default: false, null: false
    add_index :messages, :excluded_from_prompt, where: "excluded_from_prompt = true",
              name: "index_messages_on_excluded_from_prompt_true"
  end
end
