# frozen_string_literal: true

class MigrateCharacterLorebooksToSoftLinks < ActiveRecord::Migration[8.2]
  def up
    # Derived columns for fast querying + usage counts (source of truth remains data.extensions.*)
    unless column_exists?(:characters, :world_name)
      add_column :characters, :world_name, :string,
                 comment: "Primary lorebook name (soft link; extracted from data.extensions.world)"
    end

    unless column_exists?(:characters, :extra_world_names)
      add_column :characters, :extra_world_names, :string, array: true, default: [], null: false,
                              comment: "Additional lorebook names (soft links; extracted from data.extensions.extra_worlds)"
    end

    add_index :characters, :world_name unless index_exists?(:characters, :world_name)
    add_index :characters, :extra_world_names, using: :gin unless index_exists?(:characters, :extra_world_names)

    if table_exists?(:character_lorebooks)
      say_with_time "Backfill character.data.extensions.world/extra_worlds from character_lorebooks" do
        # Primary (extensions.world)
        execute <<~SQL.squish
          UPDATE characters AS c
          SET data = jsonb_set(c.data, '{extensions,world}', to_jsonb(lb.name), true)
          FROM character_lorebooks cl
          INNER JOIN lorebooks lb ON lb.id = cl.lorebook_id
          WHERE cl.character_id = c.id
            AND cl.source = 'primary'
            AND cl.enabled = TRUE
            AND NULLIF(BTRIM(c.data #>> '{extensions,world}'), '') IS NULL;
        SQL

        # Additional (extensions.extra_worlds)
        execute <<~SQL.squish
          WITH additions AS (
            SELECT
              cl.character_id,
              jsonb_agg(lb.name ORDER BY cl.priority, lb.id) AS names
            FROM character_lorebooks cl
            INNER JOIN lorebooks lb ON lb.id = cl.lorebook_id
            WHERE cl.source = 'additional'
              AND cl.enabled = TRUE
            GROUP BY cl.character_id
          )
          UPDATE characters AS c
          SET data = jsonb_set(c.data, '{extensions,extra_worlds}', additions.names, true)
          FROM additions
          WHERE additions.character_id = c.id
            AND COALESCE(
              jsonb_array_length(
                CASE
                  WHEN jsonb_typeof(c.data #> '{extensions,extra_worlds}') = 'array'
                    THEN c.data #> '{extensions,extra_worlds}'
                  ELSE '[]'::jsonb
                END
              ),
              0
            ) = 0;
        SQL
      end
    end

    say_with_time "Backfill characters.world_name/extra_world_names from data.extensions" do
      execute <<~SQL.squish
        UPDATE characters
        SET world_name = NULLIF(BTRIM(data #>> '{extensions,world}'), '');
      SQL

      execute <<~SQL.squish
        UPDATE characters AS c
        SET extra_world_names = COALESCE(src.names, ARRAY[]::varchar[])
        FROM (
          SELECT id,
                 ARRAY(
                   SELECT DISTINCT BTRIM(value)
                   FROM jsonb_array_elements_text(
                     CASE
                       WHEN jsonb_typeof(data #> '{extensions,extra_worlds}') = 'array'
                         THEN data #> '{extensions,extra_worlds}'
                       ELSE '[]'::jsonb
                     END
                   ) AS value
                   WHERE BTRIM(value) <> ''
                 )::varchar[] AS names
          FROM characters
        ) AS src
        WHERE c.id = src.id;
      SQL
    end

    drop_table :character_lorebooks, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
