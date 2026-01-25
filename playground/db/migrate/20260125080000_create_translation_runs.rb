# frozen_string_literal: true

class CreateTranslationRuns < ActiveRecord::Migration[8.2]
  def change
    create_table :translation_runs, id: :uuid, default: -> { "gen_random_uuid()" }, comment: "Translation tasks (message/swipe)", force: :cascade do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, comment: "Conversation context"
      t.references :message, null: false, foreign_key: { on_delete: :cascade }, comment: "Message being translated"
      t.references :message_swipe, null: true, foreign_key: { on_delete: :cascade }, comment: "Swipe being translated (if any)"

      t.string :kind, null: false, default: "message_translation", comment: "message_translation (MVP); reserved for future kinds"
      t.string :status, null: false, default: "queued", comment: "queued, running, succeeded, failed, canceled"

      t.string :source_lang, comment: "Source language hint (auto/en/...)"
      t.string :internal_lang, null: false, default: "en", comment: "Internal canonical language"
      t.string :target_lang, null: false, comment: "Display language (translation target)"

      t.jsonb :debug, null: false, default: {}, comment: "Debug metadata (provider/model/usage/warnings/digests)"
      t.jsonb :error, null: false, default: {}, comment: "Failure payload (code/message)"

      t.datetime :cancel_requested_at, comment: "Cancel requested at (for queued/running runs)"
      t.datetime :started_at, comment: "Job started at"
      t.datetime :finished_at, comment: "Job finished at"

      t.timestamps
    end

    add_index :translation_runs, %i[conversation_id created_at], name: "index_translation_runs_on_conversation_id_and_created_at"
    add_index :translation_runs, %i[message_id message_swipe_id target_lang status], name: "index_translation_runs_on_target_and_lang_and_status"
  end
end
