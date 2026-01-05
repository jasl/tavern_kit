class AddDelayUntilRecursionToLorebookEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :lorebook_entries, :delay_until_recursion, :integer
  end
end
