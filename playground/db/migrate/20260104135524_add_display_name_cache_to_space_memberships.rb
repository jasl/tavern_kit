class AddDisplayNameCacheToSpaceMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :space_memberships, :display_name_cache, :string

    # Backfill existing records
    reversible do |dir|
      dir.up do
        SpaceMembership.includes(:character, :user).find_each do |membership|
          name = membership.character&.name || membership.user&.name
          membership.update_column(:display_name_cache, name) if name.present?
        end
      end
    end
  end
end
