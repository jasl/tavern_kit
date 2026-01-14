# frozen_string_literal: true

# Add optional token limit per Space.
# nil or 0 = unlimited, > 0 = limit in total tokens (prompt + completion)
class AddTokenLimitToSpaces < ActiveRecord::Migration[8.1]
  def change
    add_column :spaces, :token_limit, :bigint, null: true, default: 0,
               comment: "Optional token limit (0 = unlimited)"
  end
end
