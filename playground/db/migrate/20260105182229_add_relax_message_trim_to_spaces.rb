class AddRelaxMessageTrimToSpaces < ActiveRecord::Migration[8.1]
  def change
    add_column :spaces, :relax_message_trim, :boolean, null: false, default: false
  end
end
