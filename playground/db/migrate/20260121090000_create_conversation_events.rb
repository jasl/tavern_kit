# frozen_string_literal: true

class CreateConversationEvents < ActiveRecord::Migration[8.2]
  def change
    create_table :conversation_events, comment: "Append-only domain events for conversations (scheduler/run observability)" do |t|
      t.bigint :conversation_id, null: false, comment: "Conversation this event belongs to"
      t.bigint :space_id, null: false, comment: "Space for convenient filtering"

      t.uuid :conversation_round_id, comment: "TurnScheduler round (nullable; round may be cleaned)"
      t.uuid :conversation_run_id, comment: "ConversationRun (nullable; run may be cleaned)"

      t.bigint :trigger_message_id, comment: "Trigger message (nullable)"
      t.bigint :message_id, comment: "Message created/affected by this event (nullable)"
      t.bigint :speaker_space_membership_id, comment: "Speaker membership (nullable)"

      t.string :event_name, null: false, comment: "Event name (e.g. turn_scheduler.round_paused, conversation_run.failed)"
      t.string :reason, comment: "Stable reason identifier (optional)"
      t.jsonb :payload, null: false, default: {}, comment: "Structured event payload (JSON object)"
      t.datetime :occurred_at, null: false, comment: "Event timestamp"

      t.timestamps
    end

    add_index :conversation_events,
              %i[conversation_id occurred_at],
              name: "index_conversation_events_on_conversation_id_and_occurred_at",
              order: { occurred_at: :desc },
              comment: "Fast event stream for a conversation"

    add_index :conversation_events,
              %i[space_id occurred_at],
              name: "index_conversation_events_on_space_id_and_occurred_at",
              order: { occurred_at: :desc },
              comment: "Fast event stream for a space"

    add_index :conversation_events,
              %i[conversation_round_id occurred_at],
              name: "index_conversation_events_on_round_id_and_occurred_at",
              order: { occurred_at: :desc },
              comment: "Fast event stream for a round"

    add_index :conversation_events,
              %i[conversation_run_id occurred_at],
              name: "index_conversation_events_on_run_id_and_occurred_at",
              order: { occurred_at: :desc },
              comment: "Fast event stream for a run"

    add_index :conversation_events,
              %i[event_name occurred_at],
              name: "index_conversation_events_on_event_name_and_occurred_at",
              order: { occurred_at: :desc },
              comment: "Search recent events by name"

    add_index :conversation_events,
              :occurred_at,
              name: "index_conversation_events_on_occurred_at",
              comment: "Cleanup / retention scans"

    add_check_constraint :conversation_events,
                         "jsonb_typeof(payload) = 'object'",
                         name: "conversation_events_payload_object"
  end
end
