# frozen_string_literal: true

# Add STI type column to conversation_runs for polymorphic behavior.
#
# This enables different run types (AutoTurn, CopilotTurn, HumanTurn, etc.)
# to have different behaviors while sharing the same table.
#
class AddTypeToConversationRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :conversation_runs, :type, :string
    add_index :conversation_runs, :type

    # Migrate existing data based on kind column
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE conversation_runs
          SET type = CASE kind
            WHEN 'auto_turn' THEN 'ConversationRun::AutoTurn'
            WHEN 'user_turn' THEN 'ConversationRun::AutoTurn'
            WHEN 'regenerate' THEN 'ConversationRun::Regenerate'
            WHEN 'force_talk' THEN 'ConversationRun::ForceTalk'
            ELSE 'ConversationRun::AutoTurn'
          END
          WHERE type IS NULL
        SQL
      end
    end
  end
end
