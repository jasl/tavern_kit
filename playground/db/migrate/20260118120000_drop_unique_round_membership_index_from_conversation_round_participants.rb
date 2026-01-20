# frozen_string_literal: true

class DropUniqueRoundMembershipIndexFromConversationRoundParticipants < ActiveRecord::Migration[8.2]
  def change
    remove_index :conversation_round_participants, name: "index_conversation_round_participants_on_round_and_membership", if_exists: true
  end
end
