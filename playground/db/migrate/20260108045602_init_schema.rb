# frozen_string_literal: true

class InitSchema < ActiveRecord::Migration[8.1]
  def change
    enable_extension :pgcrypto unless extension_enabled?(:pgcrypto)

    # === Independent tables (no foreign key dependencies) ===

    create_table :users do |t|
      t.string :email
      t.string :name, null: false
      t.string :password_digest
      t.string :role, default: "member", null: false
      t.string :status, default: "active", null: false

      t.timestamps

      t.index :email, unique: true, where: "(email IS NOT NULL)"
    end

    create_table :llm_providers do |t|
      t.text :api_key
      t.string :base_url, null: false
      t.boolean :disabled, default: false, null: false
      t.string :identification, default: "openai_compatible", null: false
      t.datetime :last_tested_at
      t.string :model
      t.string :name, null: false
      t.boolean :streamable, default: true
      t.boolean :supports_logprobs, default: false, null: false

      t.timestamps

      t.index :name, unique: true
    end

    create_table :settings do |t|
      t.string :key, null: false
      t.jsonb :value

      t.timestamps

      t.index :key, unique: true
    end

    create_table :active_storage_blobs do |t|
      t.datetime :created_at, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.string :content_type
      t.string :filename, null: false
      t.string :key, null: false
      t.text :metadata
      t.string :service_name, null: false

      t.index :key, unique: true
    end

    create_table :text_contents do |t|
      t.text :content, null: false
      t.string :content_sha256, null: false
      t.integer :references_count, default: 1, null: false

      t.timestamps

      t.index :content_sha256, unique: true
    end

    # === Tables with single-level dependencies ===

    create_table :active_storage_attachments do |t|
      t.datetime :created_at, null: false
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.bigint :record_id, null: false
      t.string :record_type, null: false
      t.string :name, null: false

      t.index %i[record_type record_id name blob_id], name: :index_active_storage_attachments_uniqueness, unique: true
    end

    create_table :active_storage_variant_records do |t|
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.string :variation_digest, null: false

      t.index %i[blob_id variation_digest], unique: true
    end

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.datetime :last_active_at, null: false
      t.string :token, null: false
      t.string :user_agent

      t.timestamps

      t.index :token, unique: true
    end

    create_table :characters do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.jsonb :authors_note_settings, default: {}, null: false
      t.jsonb :data, default: {}, null: false
      t.string :file_sha256
      t.datetime :locked_at
      t.string :name, null: false
      t.string :nickname
      t.text :personality
      t.integer :spec_version
      t.string :status, default: "pending", null: false
      t.string :supported_languages, default: [], null: false, array: true
      t.string :tags, default: [], null: false, array: true
      t.string :visibility, null: false, default: "private"

      t.timestamps

      t.index :file_sha256
      t.index :name
      t.index :tags, using: :gin
      t.index :visibility

      t.check_constraint "jsonb_typeof(authors_note_settings) = 'object'::text", name: :characters_authors_note_settings_object
      t.check_constraint "jsonb_typeof(data) = 'object'::text", name: :characters_data_object
    end

    create_table :lorebooks do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.text :description
      t.datetime :locked_at
      t.string :name, null: false
      t.boolean :recursive_scanning, default: false, null: false
      t.integer :scan_depth, default: 2
      t.jsonb :settings, default: {}, null: false
      t.integer :token_budget
      t.string :visibility, null: false, default: "private"
      t.integer :entries_count, default: 0, null: false

      t.timestamps

      t.index :name
      t.index :visibility

      t.check_constraint "jsonb_typeof(settings) = 'object'::text", name: :lorebooks_settings_object
    end

    create_table :presets do |t|
      t.references :user, foreign_key: true
      t.references :llm_provider, foreign_key: { on_delete: :nullify }
      t.text :description
      t.jsonb :generation_settings, default: {}, null: false
      t.datetime :locked_at
      t.string :name, null: false
      t.jsonb :preset_settings, default: {}, null: false
      t.string :visibility, null: false, default: "private"

      t.timestamps

      t.index %i[user_id name], unique: true
      t.index :visibility

      t.check_constraint "jsonb_typeof(generation_settings) = 'object'::text", name: :presets_generation_settings_object
      t.check_constraint "jsonb_typeof(preset_settings) = 'object'::text", name: :presets_preset_settings_object
    end

    create_table :spaces do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.boolean :allow_self_responses, default: false, null: false
      t.integer :auto_mode_delay_ms, default: 5000, null: false
      t.boolean :auto_mode_enabled, default: false, null: false
      t.string :card_handling_mode, default: "swap", null: false
      t.string :during_generation_user_input_policy, default: "queue", null: false
      t.string :group_regenerate_mode, default: "single_message", null: false
      t.string :name, null: false
      t.jsonb :prompt_settings, default: {}, null: false
      t.boolean :relax_message_trim, default: false, null: false
      t.string :reply_order, default: "natural", null: false
      t.integer :settings_version, default: 0, null: false
      t.string :status, default: "active", null: false
      t.string :type, null: false
      t.integer :user_turn_debounce_ms, default: 0, null: false

      t.string :visibility, null: false, default: "private"

      t.timestamps

      t.index :visibility

      t.check_constraint "jsonb_typeof(prompt_settings) = 'object'::text", name: :spaces_prompt_settings_object
    end

    # === Tables with multi-level dependencies ===

    create_table :character_assets do |t|
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.references :character, null: false, foreign_key: true
      t.string :content_sha256
      t.string :ext
      t.string :kind, default: "icon", null: false
      t.string :name, null: false

      t.timestamps

      t.index %i[character_id name], unique: true
      t.index :content_sha256
    end

    create_table :character_lorebooks do |t|
      t.references :character, null: false, foreign_key: { on_delete: :cascade }
      t.references :lorebook, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :enabled, default: true, null: false
      t.integer :priority, default: 0, null: false
      t.jsonb :settings, default: {}, null: false
      t.string :source, default: "additional", null: false

      t.timestamps

      t.index %i[character_id lorebook_id], unique: true
      t.index %i[character_id priority]
      t.index :character_id, name: :index_character_lorebooks_one_primary_per_character, unique: true,
              where: "((source)::text = 'primary'::text)"

      t.check_constraint "jsonb_typeof(settings) = 'object'::text", name: :character_lorebooks_settings_object
    end

    create_table :character_uploads do |t|
      t.references :character, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :content_type
      t.text :error_message
      t.string :filename
      t.string :status, default: "pending", null: false

      t.timestamps
    end

    create_table :lorebook_entries do |t|
      t.references :lorebook, null: false, foreign_key: { on_delete: :cascade }
      t.string :automation_id
      t.boolean :case_sensitive
      t.string :comment
      t.boolean :constant, default: false, null: false
      t.text :content
      t.integer :cooldown
      t.integer :delay
      t.integer :delay_until_recursion
      t.integer :depth, default: 4, null: false
      t.boolean :enabled, default: true, null: false
      t.boolean :exclude_recursion, default: false, null: false
      t.string :group
      t.boolean :group_override, default: false, null: false
      t.integer :group_weight, default: 100, null: false
      t.boolean :ignore_budget, default: false, null: false
      t.integer :insertion_order, default: 100, null: false
      t.text :keys, default: [], null: false, array: true
      t.boolean :match_character_depth_prompt, default: false, null: false
      t.boolean :match_character_description, default: false, null: false
      t.boolean :match_character_personality, default: false, null: false
      t.boolean :match_creator_notes, default: false, null: false
      t.boolean :match_persona_description, default: false, null: false
      t.boolean :match_scenario, default: false, null: false
      t.boolean :match_whole_words
      t.string :outlet
      t.string :position, default: "after_char_defs", null: false
      t.integer :position_index, default: 0, null: false
      t.boolean :prevent_recursion, default: false, null: false
      t.integer :probability, default: 100, null: false
      t.string :role, default: "system", null: false
      t.integer :scan_depth
      t.text :secondary_keys, default: [], null: false, array: true
      t.boolean :selective, default: false, null: false
      t.string :selective_logic, default: "and_any", null: false
      t.integer :sticky
      t.string :triggers, default: [], null: false, array: true
      t.string :uid, null: false
      t.boolean :use_group_scoring
      t.boolean :use_probability, default: true, null: false
      t.boolean :use_regex, default: false, null: false

      t.timestamps

      t.index :enabled
      t.index %i[lorebook_id position_index]
      t.index %i[lorebook_id uid], unique: true
    end

    create_table :space_lorebooks do |t|
      t.references :lorebook, null: false, foreign_key: { on_delete: :cascade }
      t.references :space, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :enabled, default: true, null: false
      t.integer :priority, default: 0, null: false
      t.string :source, default: "global", null: false

      t.timestamps

      t.index %i[space_id lorebook_id], unique: true
      t.index %i[space_id priority]
    end

    create_table :space_memberships do |t|
      t.references :character, foreign_key: { on_delete: :nullify }
      t.references :llm_provider, foreign_key: { on_delete: :nullify }
      t.references :preset, foreign_key: true
      t.references :removed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :space, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :cached_display_name
      t.string :copilot_mode, default: "none", null: false
      t.integer :copilot_remaining_steps
      t.string :kind, default: "human", null: false
      t.string :participation, default: "active", null: false
      t.text :persona
      t.integer :position, default: 0, null: false
      t.datetime :removed_at
      t.string :removed_reason
      t.string :role, default: "member", null: false
      t.jsonb :settings, default: {}, null: false
      t.integer :settings_version, default: 0, null: false
      t.string :status, default: "active", null: false
      t.decimal :talkativeness_factor, precision: 3, scale: 2, default: "0.5", null: false
      t.datetime :unread_at

      t.timestamps

      t.index :participation
      t.index %i[space_id character_id], unique: true, where: "(character_id IS NOT NULL)"
      t.index %i[space_id user_id], unique: true, where: "(user_id IS NOT NULL)"
      t.index :status

      t.check_constraint "jsonb_typeof(settings) = 'object'::text", name: :space_memberships_settings_object
      t.check_constraint(
        "kind::text = 'character'::text AND user_id IS NULL AND " \
          "(character_id IS NOT NULL OR status::text = 'removed'::text) OR " \
          "kind::text = 'human'::text AND user_id IS NOT NULL",
        name: :space_memberships_kind_consistency
      )
    end

    # conversations has circular references (parent_conversation, root_conversation, forked_from_message)
    create_table :conversations do |t|
      t.references :space, null: false, foreign_key: true
      t.references :parent_conversation, foreign_key: { to_table: :conversations }
      t.references :root_conversation, foreign_key: { to_table: :conversations }
      t.bigint :forked_from_message_id # FK added later (circular with messages)
      t.text :authors_note
      t.integer :authors_note_depth
      t.string :authors_note_position
      t.string :authors_note_role
      t.string :kind, default: "root", null: false
      t.string :title, null: false
      t.jsonb :variables, default: {}, null: false
      t.string :visibility, default: "shared", null: false

      t.index :forked_from_message_id
      t.index :visibility

      t.string :status, null: false, default: "ready"

      t.timestamps

      t.check_constraint "jsonb_typeof(variables) = 'object'::text", name: :conversations_variables_object
    end

    create_table :conversation_lorebooks do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :lorebook, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :enabled, default: true, null: false
      t.integer :priority, default: 0, null: false

      t.timestamps

      t.index %i[conversation_id lorebook_id], name: :idx_on_conversation_id_lorebook_id_cb22900952, unique: true
      t.index %i[conversation_id priority]
    end

    create_table :conversation_runs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :conversation, null: false, type: :bigint, foreign_key: true
      t.references :speaker_space_membership, foreign_key: { to_table: :space_memberships }
      t.datetime :cancel_requested_at
      t.jsonb :debug, default: {}, null: false
      t.jsonb :error, default: {}, null: false
      t.datetime :finished_at
      t.datetime :heartbeat_at
      t.string :kind, null: false
      t.string :reason, null: false
      t.datetime :run_after
      t.datetime :started_at
      t.string :status, null: false

      t.timestamps

      t.index %i[conversation_id status]
      t.index :conversation_id, name: :index_conversation_runs_unique_queued_per_conversation, unique: true,
              where: "((status)::text = 'queued'::text)"
      t.index :conversation_id, name: :index_conversation_runs_unique_running_per_conversation, unique: true,
              where: "((status)::text = 'running'::text)"
      t.index :status

      t.check_constraint "jsonb_typeof(debug) = 'object'::text", name: :conversation_runs_debug_object
      t.check_constraint "jsonb_typeof(error) = 'object'::text", name: :conversation_runs_error_object
    end

    # messages has circular references (active_message_swipe, origin_message)
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :conversation_run, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :space_membership, null: false, foreign_key: true
      t.references :text_content, foreign_key: true
      t.bigint :active_message_swipe_id # FK added later (circular with message_swipes)
      t.bigint :origin_message_id # FK added later (self-reference)
      t.text :content
      t.boolean :excluded_from_prompt, default: false, null: false
      t.integer :message_swipes_count, default: 0, null: false
      t.jsonb :metadata, default: {}, null: false
      t.string :role, default: "user", null: false
      t.bigint :seq, null: false

      t.timestamps

      t.index :active_message_swipe_id
      t.index %i[conversation_id created_at id]
      t.index %i[conversation_id seq], unique: true
      t.index :excluded_from_prompt, where: "(excluded_from_prompt = true)"
      t.index :origin_message_id

      t.check_constraint "jsonb_typeof(metadata) = 'object'::text", name: :messages_metadata_object
    end

    create_table :message_swipes do |t|
      t.references :conversation_run, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :message, null: false, foreign_key: { on_delete: :cascade }
      t.references :text_content, foreign_key: true
      t.text :content
      t.jsonb :metadata, default: {}, null: false
      t.integer :position, default: 0, null: false

      t.timestamps

      t.index %i[message_id position], unique: true

      t.check_constraint "jsonb_typeof(metadata) = 'object'::text", name: :message_swipes_metadata_object
    end

    create_table :message_attachments do |t|
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.references :message, null: false, foreign_key: true
      t.string :kind, default: "file", null: false
      t.jsonb :metadata, default: {}, null: false
      t.string :name
      t.integer :position, default: 0, null: false

      t.timestamps

      t.index %i[message_id blob_id], unique: true
    end

    # === Deferred foreign keys for circular references ===
    add_foreign_key :conversations, :messages, column: :forked_from_message_id
    add_foreign_key :messages, :message_swipes, column: :active_message_swipe_id, on_delete: :nullify
    add_foreign_key :messages, :messages, column: :origin_message_id
  end
end
