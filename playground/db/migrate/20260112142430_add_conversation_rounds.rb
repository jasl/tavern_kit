# frozen_string_literal: true

class AddConversationRounds < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_rounds, id: :uuid, default: -> { "gen_random_uuid()" },
                                       comment: "TurnScheduler round runtime state" do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.string :status, null: false, default: "active",
               comment: "Lifecycle: active, finished, superseded, canceled"
      t.string :scheduling_state,
               comment: "Scheduling state: ai_generating, failed (null when not active)"
      t.integer :current_position, null: false, default: 0,
                comment: "0-based index into participants queue"
      t.string :ended_reason, comment: "Why round ended (optional)"
      t.datetime :finished_at, comment: "When the round ended (null when active)"
      t.bigint :trigger_message_id, comment: "Trigger message (optional)"
      t.jsonb :metadata, null: false, default: {}, comment: "Diagnostic metadata"

      t.timestamps

      t.index :status
      t.index :finished_at
      t.index :trigger_message_id
      t.index :conversation_id,
              unique: true,
              where: "((status)::text = 'active'::text)",
              name: "index_conversation_rounds_unique_active_per_conversation"

      t.check_constraint "jsonb_typeof(metadata) = 'object'::text",
                         name: "conversation_rounds_metadata_object"
      t.check_constraint "((status)::text = ANY ((ARRAY['active'::character varying, 'finished'::character varying, " \
                         "'superseded'::character varying, 'canceled'::character varying])::text[]))",
                         name: "conversation_rounds_status_check"
      t.check_constraint "(scheduling_state IS NULL) OR ((scheduling_state)::text = ANY " \
                         "((ARRAY['ai_generating'::character varying, 'failed'::character varying])::text[]))",
                         name: "conversation_rounds_scheduling_state_check"
      t.check_constraint "((status)::text <> 'active'::text) OR (scheduling_state IS NOT NULL)",
                         name: "conversation_rounds_active_requires_scheduling_state"
    end

    add_foreign_key :conversation_rounds, :messages, column: :trigger_message_id, on_delete: :nullify

    create_table :conversation_round_participants, comment: "Ordered participant queue entries for a round" do |t|
      t.references :conversation_round, null: false, type: :uuid,
                   foreign_key: { on_delete: :cascade }
      t.references :space_membership, null: false, foreign_key: true
      t.integer :position, null: false, comment: "0-based position in the round queue"
      t.string :status, null: false, default: "pending", comment: "State: pending, spoken, skipped"
      t.datetime :spoken_at
      t.datetime :skipped_at
      t.string :skip_reason

      t.timestamps

      t.index %i[conversation_round_id position],
              unique: true,
              name: "index_conversation_round_participants_on_round_and_position"
      t.index %i[conversation_round_id space_membership_id],
              unique: true,
              name: "index_conversation_round_participants_on_round_and_membership"

      t.check_constraint "((status)::text = ANY ((ARRAY['pending'::character varying, 'spoken'::character varying, " \
                         "'skipped'::character varying])::text[]))",
                         name: "conversation_round_participants_status_check"
    end

    add_column :conversation_runs, :conversation_round_id, :uuid,
               comment: "Associated TurnScheduler round (nullable; may be cleaned)"
    add_index :conversation_runs, :conversation_round_id
    add_foreign_key :conversation_runs, :conversation_rounds, column: :conversation_round_id, on_delete: :nullify
  end
end
