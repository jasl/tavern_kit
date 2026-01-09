# frozen_string_literal: true

class AddUsageCountAndNsfwToCharacters < ActiveRecord::Migration[8.1]
  def up
    # Add usage_count column with default 0
    add_column :characters, :usage_count, :integer, default: 0, null: false

    # Add nsfw boolean column with default false
    add_column :characters, :nsfw, :boolean, default: false, null: false

    # Add index for efficient sorting by usage_count
    add_index :characters, :usage_count

    # Add index for efficient NSFW filtering
    add_index :characters, :nsfw

    # Backfill usage_count from SpaceMembership counts
    execute <<~SQL
      UPDATE characters
      SET usage_count = (
        SELECT COUNT(*)
        FROM space_memberships
        WHERE space_memberships.character_id = characters.id
      )
    SQL

    # Backfill nsfw from tags containing "NSFW" (case-insensitive)
    execute <<~SQL
      UPDATE characters
      SET nsfw = true
      WHERE EXISTS (
        SELECT 1
        FROM unnest(tags) AS tag
        WHERE UPPER(tag) = 'NSFW'
      )
    SQL
  end

  def down
    remove_index :characters, :nsfw
    remove_index :characters, :usage_count
    remove_column :characters, :nsfw
    remove_column :characters, :usage_count
  end
end
