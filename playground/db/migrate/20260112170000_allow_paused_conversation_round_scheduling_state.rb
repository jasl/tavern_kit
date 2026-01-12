# frozen_string_literal: true

class AllowPausedConversationRoundSchedulingState < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :conversation_rounds, name: "conversation_rounds_scheduling_state_check"

    add_check_constraint :conversation_rounds,
                         "(scheduling_state IS NULL) OR ((scheduling_state)::text = ANY " \
                         "((ARRAY['ai_generating'::character varying, 'paused'::character varying, " \
                         "'failed'::character varying])::text[]))",
                         name: "conversation_rounds_scheduling_state_check"
  end
end
