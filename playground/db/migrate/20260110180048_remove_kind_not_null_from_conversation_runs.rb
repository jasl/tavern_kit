# frozen_string_literal: true

# Remove NOT NULL constraint from kind column since we're now using STI with type column.
# The kind column is deprecated and will be removed in a future migration.
class RemoveKindNotNullFromConversationRuns < ActiveRecord::Migration[8.1]
  def change
    change_column_null :conversation_runs, :kind, true
  end
end
