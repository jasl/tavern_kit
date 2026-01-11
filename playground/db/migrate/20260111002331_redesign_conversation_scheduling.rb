# frozen_string_literal: true

# Redesign conversation scheduling for clarity, correctness, and reduced complexity.
#
# This migration:
# 1. Replaces the jsonb `turn_queue_state` blob with explicit columns
# 2. Adds explicit `scheduling_state` state machine column
# 3. Replaces STI `type` column in conversation_runs with `kind` enum
#
# The new design has several advantages:
# - Explicit state columns are easier to query and debug
# - PostgreSQL array for `round_spoken_ids` has better type safety than jsonb
# - Enum `kind` is simpler than STI class hierarchies
# - State machine is explicit rather than implicit
#
class RedesignConversationScheduling < ActiveRecord::Migration[8.0]
  def up
    # ============================================================================
    # 1. Conversations table changes
    # ============================================================================

    # Add new explicit scheduling columns
    add_column :conversations, :scheduling_state, :string, default: "idle", null: false
    add_column :conversations, :current_round_id, :uuid
    add_column :conversations, :current_speaker_id, :bigint
    add_column :conversations, :round_position, :integer, default: 0, null: false
    add_column :conversations, :round_spoken_ids, :bigint, array: true, default: [], null: false

    # Add index for querying by state
    add_index :conversations, :scheduling_state

    # Add foreign key for current_speaker_id
    add_foreign_key :conversations, :space_memberships, column: :current_speaker_id, on_delete: :nullify

    # Remove old jsonb blob
    remove_column :conversations, :turn_queue_state, :jsonb

    # ============================================================================
    # 2. ConversationRuns table changes - Replace STI with kind enum
    # ============================================================================

    # Add new `kind` column
    add_column :conversation_runs, :kind, :string

    # Migrate existing STI type values to kind values
    execute <<~SQL
      UPDATE conversation_runs
      SET kind = CASE type
        WHEN 'ConversationRun::AutoTurn' THEN 'auto_response'
        WHEN 'ConversationRun::CopilotTurn' THEN 'copilot_response'
        WHEN 'ConversationRun::Regenerate' THEN 'regenerate'
        WHEN 'ConversationRun::ForceTalk' THEN 'force_talk'
        WHEN 'ConversationRun::HumanTurn' THEN 'human_turn'
        ELSE 'auto_response'
      END
    SQL

    # Make kind non-nullable after migration
    change_column_null :conversation_runs, :kind, false

    # Add index for kind
    add_index :conversation_runs, :kind

    # Remove old STI type column
    remove_column :conversation_runs, :type, :string

    # ============================================================================
    # 3. Add check constraint for valid scheduling states
    # ============================================================================

    execute <<~SQL
      ALTER TABLE conversations
      ADD CONSTRAINT valid_scheduling_state
      CHECK (scheduling_state IN ('idle', 'round_active', 'waiting_for_speaker', 'ai_generating', 'human_waiting', 'failed'))
    SQL

    # ============================================================================
    # 4. Add check constraint for valid run kinds
    # ============================================================================

    execute <<~SQL
      ALTER TABLE conversation_runs
      ADD CONSTRAINT valid_run_kind
      CHECK (kind IN ('auto_response', 'copilot_response', 'regenerate', 'force_talk', 'human_turn'))
    SQL
  end

  def down
    # ============================================================================
    # 1. Remove check constraints
    # ============================================================================

    execute <<~SQL
      ALTER TABLE conversations DROP CONSTRAINT IF EXISTS valid_scheduling_state
    SQL

    execute <<~SQL
      ALTER TABLE conversation_runs DROP CONSTRAINT IF EXISTS valid_run_kind
    SQL

    # ============================================================================
    # 2. Restore conversation_runs STI type column
    # ============================================================================

    add_column :conversation_runs, :type, :string

    # Migrate kind values back to STI type values
    execute <<~SQL
      UPDATE conversation_runs
      SET type = CASE kind
        WHEN 'auto_response' THEN 'ConversationRun::AutoTurn'
        WHEN 'copilot_response' THEN 'ConversationRun::CopilotTurn'
        WHEN 'regenerate' THEN 'ConversationRun::Regenerate'
        WHEN 'force_talk' THEN 'ConversationRun::ForceTalk'
        WHEN 'human_turn' THEN 'ConversationRun::HumanTurn'
        ELSE 'ConversationRun::AutoTurn'
      END
    SQL

    remove_index :conversation_runs, :kind
    remove_column :conversation_runs, :kind

    # ============================================================================
    # 3. Restore conversations table
    # ============================================================================

    # Re-add jsonb blob
    add_column :conversations, :turn_queue_state, :jsonb

    # Remove foreign key first
    remove_foreign_key :conversations, column: :current_speaker_id

    # Remove new columns
    remove_index :conversations, :scheduling_state
    remove_column :conversations, :scheduling_state
    remove_column :conversations, :current_round_id
    remove_column :conversations, :current_speaker_id
    remove_column :conversations, :round_position
    remove_column :conversations, :round_spoken_ids
  end
end
