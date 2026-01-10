class AddAutoModeDisableOnTypingToSpaces < ActiveRecord::Migration[8.1]
  def change
    add_column :spaces, :auto_mode_disable_on_typing, :boolean, default: true, null: false
  end
end
