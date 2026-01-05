# frozen_string_literal: true

# Add talkativeness_factor to space_memberships for natural order speaker selection.
# This field controls the probability weight for a character being selected to speak
# in group chats, matching SillyTavern's talkativeness behavior.
#
# Range: 0.0 (never speaks unless mentioned) to 1.0 (always activated)
# Default: 0.5 (50% chance of being activated per roll)
class AddTalkativenessFactorToSpaceMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :space_memberships, :talkativeness_factor, :decimal,
               precision: 3, scale: 2, default: 0.5, null: false
  end
end
