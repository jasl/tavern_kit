# frozen_string_literal: true

class AddMessageVisibilityAndDropExcludedFromPrompt < ActiveRecord::Migration[8.2]
  def up
    add_column :messages,
               :visibility,
               :string,
               null: false,
               default: "normal",
               comment: "Visibility: normal, excluded, hidden"

    # Backfill from legacy excluded_from_prompt
    execute <<~SQL.squish
      UPDATE messages
      SET visibility = 'excluded'
      WHERE excluded_from_prompt = TRUE
    SQL

    # Drop legacy indexes before dropping the column (so we can safely reuse names).
    remove_index :messages, name: "index_messages_on_conversation_id_and_role_and_seq" if index_exists?(:messages, name: "index_messages_on_conversation_id_and_role_and_seq")
    remove_index :messages, name: "index_messages_on_excluded_from_prompt" if index_exists?(:messages, name: "index_messages_on_excluded_from_prompt")

    remove_column :messages, :excluded_from_prompt

    add_check_constraint :messages,
                         "visibility IN ('normal','excluded','hidden')",
                         name: "messages_visibility_check"

    # Prompt/history optimization: role queries filtered to prompt-included messages only.
    add_index :messages,
              %i[conversation_id role seq],
              name: "index_messages_on_conversation_id_and_role_and_seq",
              where: "(visibility = 'normal')",
              comment: "Optimize role-based message queries with prompt filtering"

    # Scheduler/UX helpers: ignore hidden messages for last/epoch computations.
    add_index :messages,
              %i[conversation_id role seq],
              name: "index_messages_on_conversation_id_and_role_and_seq_non_hidden",
              where: "(visibility <> 'hidden')",
              comment: "Optimize role-based message queries excluding hidden messages"
  end

  def down
    remove_index :messages, name: "index_messages_on_conversation_id_and_role_and_seq_non_hidden" if index_exists?(:messages, name: "index_messages_on_conversation_id_and_role_and_seq_non_hidden")
    remove_index :messages, name: "index_messages_on_conversation_id_and_role_and_seq" if index_exists?(:messages, name: "index_messages_on_conversation_id_and_role_and_seq")

    remove_check_constraint :messages, name: "messages_visibility_check" if check_constraint_exists?(:messages, name: "messages_visibility_check")

    add_column :messages,
               :excluded_from_prompt,
               :boolean,
               null: false,
               default: false,
               comment: "Exclude this message from LLM context"

    # Restore legacy values from visibility.
    execute <<~SQL.squish
      UPDATE messages
      SET excluded_from_prompt = TRUE
      WHERE visibility = 'excluded'
    SQL

    remove_column :messages, :visibility

    add_index :messages,
              %i[conversation_id role seq],
              name: "index_messages_on_conversation_id_and_role_and_seq",
              where: "(excluded_from_prompt = false)",
              comment: "Optimize role-based message queries with prompt filtering"

    add_index :messages,
              :excluded_from_prompt,
              name: "index_messages_on_excluded_from_prompt",
              where: "(excluded_from_prompt = true)"
  end
end
