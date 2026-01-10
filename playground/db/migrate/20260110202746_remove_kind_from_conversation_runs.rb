# frozen_string_literal: true

# Remove the deprecated `kind` column from conversation_runs table.
#
# The `kind` column has been replaced by Rails STI with the `type` column.
# STI subclasses (AutoTurn, CopilotTurn, HumanTurn, Regenerate, ForceTalk)
# now determine the run type instead of the string `kind` column.
#
class RemoveKindFromConversationRuns < ActiveRecord::Migration[8.0]
  def change
    remove_column :conversation_runs, :kind, :string
  end
end
