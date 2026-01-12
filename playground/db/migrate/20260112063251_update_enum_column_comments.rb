# frozen_string_literal: true

class UpdateEnumColumnComments < ActiveRecord::Migration[8.1]
  def up
    change_column_comment :characters, :status, "Processing status: pending, ready, failed, deleting"

    change_column_comment :conversations, :kind, "Conversation kind: root, branch, thread, checkpoint"
    change_column_comment :conversations, :status, "Conversation status: ready, pending, failed, archived"
    change_column_comment :conversations,
                          :scheduling_state,
                          "Scheduler state machine: idle, waiting_for_speaker, ai_generating, failed; legacy: human_waiting"

    change_column_comment :conversation_runs,
                          :kind,
                          "Run kind: auto_response, copilot_response, regenerate, force_talk, human_turn (legacy)"

    change_column_comment :messages, :generation_status, "AI generation status: generating, succeeded, failed"

    change_column_comment :spaces, :status, "Space status: active, archived, deleting"
    change_column_comment :spaces, :visibility, "Visibility: private, public"
  end

  def down
    change_column_comment :characters, :status, "Processing status: pending, ready, error"

    change_column_comment :conversations, :kind, "Conversation kind: root, branch"
    change_column_comment :conversations, :status, "Conversation status: ready, busy, error"
    change_column_comment :conversations,
                          :scheduling_state,
                          "Scheduler state machine: idle, round_active, waiting_for_speaker, ai_generating, human_waiting, failed"

    change_column_comment :conversation_runs,
                          :kind,
                          "Run kind: auto_response, copilot_response, regenerate, force_talk, human_turn"

    change_column_comment :messages, :generation_status, "AI generation status: generating, succeeded, failed, canceled"

    change_column_comment :spaces, :status, "Space status: active, archived, deleted"
    change_column_comment :spaces, :visibility, "Visibility: private, unlisted, public"
  end
end

