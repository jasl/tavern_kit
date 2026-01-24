# frozen_string_literal: true

class AddNameOverrideToSpaceMemberships < ActiveRecord::Migration[8.2]
  def change
    add_column :space_memberships, :name_override, :string, comment: "Optional per-space display name override"
  end
end
