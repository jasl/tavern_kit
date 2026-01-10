class RefactorAutoModeToConversation < ActiveRecord::Migration[8.1]
  def change
    # Add auto_mode_remaining_rounds to conversations
    # null = disabled, > 0 = active with remaining rounds
    add_column :conversations, :auto_mode_remaining_rounds, :integer

    # Remove auto-mode settings from spaces (moving to conversation level)
    remove_column :spaces, :auto_mode_enabled, :boolean, default: false, null: false
    remove_column :spaces, :auto_mode_disable_on_typing, :boolean, default: true, null: false
  end
end
