# frozen_string_literal: true

class MakeSpaceMembershipTalkativenessFactorNullable < ActiveRecord::Migration[8.2]
  def change
    change_column_default :space_memberships, :talkativeness_factor, from: "0.5", to: nil
    change_column_null :space_memberships, :talkativeness_factor, true
  end
end
