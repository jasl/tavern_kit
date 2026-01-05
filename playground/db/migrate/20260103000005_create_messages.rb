# frozen_string_literal: true

class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :space_membership, null: false, foreign_key: true
      t.references :conversation_run, type: :uuid, foreign_key: { on_delete: :nullify }

      # Clone mapping: tracks which message this was copied from during fork
      t.references :origin_message, foreign_key: { to_table: :messages }

      t.bigint :seq, null: false

      t.string :role, null: false, default: "user"
      t.text :content
      t.jsonb :metadata, null: false, default: {}
      t.check_constraint "jsonb_typeof(metadata) = 'object'", name: "messages_metadata_object"

      t.boolean :excluded_from_prompt, null: false, index: { where: "excluded_from_prompt = true" }, default: false

      t.timestamps

      t.index %i[conversation_id seq], unique: true
      t.index %i[conversation_id created_at id],
              name: "index_messages_on_conversation_id_created_at_id"
    end
  end
end
