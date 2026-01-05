class CreateConversationRuns < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :conversation_runs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :conversation, null: false, foreign_key: true

      t.string :kind, null: false
      t.string :status, null: false, index: true
      t.string :reason, null: false

      t.references :speaker_space_membership, foreign_key: { to_table: :space_memberships }

      t.datetime :heartbeat_at
      t.datetime :run_after
      t.datetime :cancel_requested_at
      t.datetime :started_at
      t.datetime :finished_at

      t.jsonb :error, null: false, default: {}
      t.check_constraint "jsonb_typeof(error) = 'object'", name: "conversation_runs_error_object"
      t.jsonb :debug, null: false, default: {}
      t.check_constraint "jsonb_typeof(debug) = 'object'", name: "conversation_runs_debug_object"

      t.timestamps

      t.index :conversation_id,
              unique: true,
              where: "status = 'running'",
              name: "index_conversation_runs_unique_running_per_conversation"
      t.index :conversation_id,
              unique: true,
              where: "status = 'queued'",
              name: "index_conversation_runs_unique_queued_per_conversation"
      t.index %i[conversation_id status], name: "index_conversation_runs_on_conversation_id_and_status"
    end
  end
end
