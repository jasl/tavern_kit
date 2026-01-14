# frozen_string_literal: true

# Add token usage statistics columns to conversations, spaces, and users.
#
# These columns track cumulative LLM token consumption:
# - Conversation: tokens used in this conversation
# - Space: tokens used across all conversations in this space (for future limits)
# - User: tokens used by this user as space owner (for future billing)
#
class AddTokenUsageColumns < ActiveRecord::Migration[8.1]
  def change
    change_table :conversations, bulk: true do |t|
      t.bigint :prompt_tokens_total, default: 0, null: false, comment: "Cumulative prompt tokens used"
      t.bigint :completion_tokens_total, default: 0, null: false, comment: "Cumulative completion tokens used"
    end

    change_table :spaces, bulk: true do |t|
      t.bigint :prompt_tokens_total, default: 0, null: false, comment: "Cumulative prompt tokens used (for limits)"
      t.bigint :completion_tokens_total, default: 0, null: false, comment: "Cumulative completion tokens used (for limits)"
    end

    change_table :users, bulk: true do |t|
      t.bigint :prompt_tokens_total, default: 0, null: false, comment: "Cumulative prompt tokens as space owner (for billing)"
      t.bigint :completion_tokens_total, default: 0, null: false, comment: "Cumulative completion tokens as space owner (for billing)"
    end
  end
end
