# frozen_string_literal: true

class ChangeSpacesUserInputPolicyDefaultToReject < ActiveRecord::Migration[8.0]
  def up
    change_column_default :spaces, :during_generation_user_input_policy, from: "queue", to: "reject"
  end

  def down
    change_column_default :spaces, :during_generation_user_input_policy, from: "reject", to: "queue"
  end
end
