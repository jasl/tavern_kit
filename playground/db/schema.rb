# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_09_150545) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "idx_on_blob_id_variation_digest_f36bede0d9", unique: true
    t.index ["blob_id"], name: "index_active_storage_variant_records_on_blob_id"
  end

  create_table "character_assets", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.bigint "character_id", null: false
    t.string "content_sha256"
    t.datetime "created_at", null: false
    t.string "ext"
    t.string "kind", default: "icon", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["blob_id"], name: "index_character_assets_on_blob_id"
    t.index ["character_id", "name"], name: "index_character_assets_on_character_id_and_name", unique: true
    t.index ["character_id"], name: "index_character_assets_on_character_id"
    t.index ["content_sha256"], name: "index_character_assets_on_content_sha256"
  end

  create_table "character_lorebooks", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.bigint "lorebook_id", null: false
    t.integer "priority", default: 0, null: false
    t.jsonb "settings", default: {}, null: false
    t.string "source", default: "additional", null: false
    t.datetime "updated_at", null: false
    t.index ["character_id", "lorebook_id"], name: "index_character_lorebooks_on_character_id_and_lorebook_id", unique: true
    t.index ["character_id", "priority"], name: "index_character_lorebooks_on_character_id_and_priority"
    t.index ["character_id"], name: "index_character_lorebooks_on_character_id"
    t.index ["character_id"], name: "index_character_lorebooks_one_primary_per_character", unique: true, where: "((source)::text = 'primary'::text)"
    t.index ["lorebook_id"], name: "index_character_lorebooks_on_lorebook_id"
    t.check_constraint "jsonb_typeof(settings) = 'object'::text", name: "character_lorebooks_settings_object"
  end

  create_table "character_uploads", force: :cascade do |t|
    t.bigint "character_id"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "filename"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["character_id"], name: "index_character_uploads_on_character_id"
    t.index ["user_id"], name: "index_character_uploads_on_user_id"
  end

  create_table "characters", force: :cascade do |t|
    t.jsonb "authors_note_settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false
    t.string "file_sha256"
    t.datetime "locked_at"
    t.string "name", null: false
    t.string "nickname"
    t.boolean "nsfw", default: false, null: false
    t.text "personality"
    t.integer "spec_version"
    t.string "status", default: "pending", null: false
    t.string "supported_languages", default: [], null: false, array: true
    t.string "tags", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.bigint "user_id"
    t.string "visibility", default: "private", null: false
    t.index ["file_sha256"], name: "index_characters_on_file_sha256"
    t.index ["name"], name: "index_characters_on_name"
    t.index ["nsfw"], name: "index_characters_on_nsfw"
    t.index ["tags"], name: "index_characters_on_tags", using: :gin
    t.index ["usage_count"], name: "index_characters_on_usage_count"
    t.index ["user_id"], name: "index_characters_on_user_id"
    t.index ["visibility"], name: "index_characters_on_visibility"
    t.check_constraint "jsonb_typeof(authors_note_settings) = 'object'::text", name: "characters_authors_note_settings_object"
    t.check_constraint "jsonb_typeof(data) = 'object'::text", name: "characters_data_object"
  end

  create_table "conversation_lorebooks", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.bigint "lorebook_id", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "lorebook_id"], name: "idx_on_conversation_id_lorebook_id_cb22900952", unique: true
    t.index ["conversation_id", "priority"], name: "index_conversation_lorebooks_on_conversation_id_and_priority"
    t.index ["conversation_id"], name: "index_conversation_lorebooks_on_conversation_id"
    t.index ["lorebook_id"], name: "index_conversation_lorebooks_on_lorebook_id"
  end

  create_table "conversation_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "cancel_requested_at"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "debug", default: {}, null: false
    t.jsonb "error", default: {}, null: false
    t.datetime "finished_at"
    t.datetime "heartbeat_at"
    t.string "kind", null: false
    t.string "reason", null: false
    t.datetime "run_after"
    t.bigint "speaker_space_membership_id"
    t.datetime "started_at"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "status"], name: "index_conversation_runs_on_conversation_id_and_status"
    t.index ["conversation_id"], name: "index_conversation_runs_on_conversation_id"
    t.index ["conversation_id"], name: "index_conversation_runs_unique_queued_per_conversation", unique: true, where: "((status)::text = 'queued'::text)"
    t.index ["conversation_id"], name: "index_conversation_runs_unique_running_per_conversation", unique: true, where: "((status)::text = 'running'::text)"
    t.index ["speaker_space_membership_id"], name: "index_conversation_runs_on_speaker_space_membership_id"
    t.index ["status"], name: "index_conversation_runs_on_status"
    t.check_constraint "jsonb_typeof(debug) = 'object'::text", name: "conversation_runs_debug_object"
    t.check_constraint "jsonb_typeof(error) = 'object'::text", name: "conversation_runs_error_object"
  end

  create_table "conversations", force: :cascade do |t|
    t.text "authors_note"
    t.integer "authors_note_depth"
    t.string "authors_note_position"
    t.string "authors_note_role"
    t.datetime "created_at", null: false
    t.bigint "forked_from_message_id"
    t.string "kind", default: "root", null: false
    t.bigint "parent_conversation_id"
    t.bigint "root_conversation_id"
    t.bigint "space_id", null: false
    t.string "status", default: "ready", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.jsonb "variables", default: {}, null: false
    t.string "visibility", default: "shared", null: false
    t.index ["forked_from_message_id"], name: "index_conversations_on_forked_from_message_id"
    t.index ["parent_conversation_id"], name: "index_conversations_on_parent_conversation_id"
    t.index ["root_conversation_id"], name: "index_conversations_on_root_conversation_id"
    t.index ["space_id"], name: "index_conversations_on_space_id"
    t.index ["visibility"], name: "index_conversations_on_visibility"
    t.check_constraint "jsonb_typeof(variables) = 'object'::text", name: "conversations_variables_object"
  end

  create_table "llm_providers", force: :cascade do |t|
    t.text "api_key"
    t.string "base_url", null: false
    t.datetime "created_at", null: false
    t.boolean "disabled", default: false, null: false
    t.string "identification", default: "openai_compatible", null: false
    t.datetime "last_tested_at"
    t.string "model"
    t.string "name", null: false
    t.boolean "streamable", default: true
    t.boolean "supports_logprobs", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_llm_providers_on_name", unique: true
  end

  create_table "lorebook_entries", force: :cascade do |t|
    t.string "automation_id"
    t.boolean "case_sensitive"
    t.string "comment"
    t.boolean "constant", default: false, null: false
    t.text "content"
    t.integer "cooldown"
    t.datetime "created_at", null: false
    t.integer "delay"
    t.integer "delay_until_recursion"
    t.integer "depth", default: 4, null: false
    t.boolean "enabled", default: true, null: false
    t.boolean "exclude_recursion", default: false, null: false
    t.string "group"
    t.boolean "group_override", default: false, null: false
    t.integer "group_weight", default: 100, null: false
    t.boolean "ignore_budget", default: false, null: false
    t.integer "insertion_order", default: 100, null: false
    t.text "keys", default: [], null: false, array: true
    t.bigint "lorebook_id", null: false
    t.boolean "match_character_depth_prompt", default: false, null: false
    t.boolean "match_character_description", default: false, null: false
    t.boolean "match_character_personality", default: false, null: false
    t.boolean "match_creator_notes", default: false, null: false
    t.boolean "match_persona_description", default: false, null: false
    t.boolean "match_scenario", default: false, null: false
    t.boolean "match_whole_words"
    t.string "outlet"
    t.string "position", default: "after_char_defs", null: false
    t.integer "position_index", default: 0, null: false
    t.boolean "prevent_recursion", default: false, null: false
    t.integer "probability", default: 100, null: false
    t.string "role", default: "system", null: false
    t.integer "scan_depth"
    t.text "secondary_keys", default: [], null: false, array: true
    t.boolean "selective", default: false, null: false
    t.string "selective_logic", default: "and_any", null: false
    t.integer "sticky"
    t.string "triggers", default: [], null: false, array: true
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.boolean "use_group_scoring"
    t.boolean "use_probability", default: true, null: false
    t.boolean "use_regex", default: false, null: false
    t.index ["enabled"], name: "index_lorebook_entries_on_enabled"
    t.index ["lorebook_id", "position_index"], name: "index_lorebook_entries_on_lorebook_id_and_position_index"
    t.index ["lorebook_id", "uid"], name: "index_lorebook_entries_on_lorebook_id_and_uid", unique: true
    t.index ["lorebook_id"], name: "index_lorebook_entries_on_lorebook_id"
  end

  create_table "lorebooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "entries_count", default: 0, null: false
    t.datetime "locked_at"
    t.string "name", null: false
    t.boolean "recursive_scanning", default: false, null: false
    t.integer "scan_depth", default: 2
    t.jsonb "settings", default: {}, null: false
    t.integer "token_budget"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "visibility", default: "private", null: false
    t.index ["name"], name: "index_lorebooks_on_name"
    t.index ["user_id"], name: "index_lorebooks_on_user_id"
    t.index ["visibility"], name: "index_lorebooks_on_visibility"
    t.check_constraint "jsonb_typeof(settings) = 'object'::text", name: "lorebooks_settings_object"
  end

  create_table "message_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", default: "file", null: false
    t.bigint "message_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "name"
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["blob_id"], name: "index_message_attachments_on_blob_id"
    t.index ["message_id", "blob_id"], name: "index_message_attachments_on_message_id_and_blob_id", unique: true
    t.index ["message_id"], name: "index_message_attachments_on_message_id"
  end

  create_table "message_swipes", force: :cascade do |t|
    t.text "content"
    t.uuid "conversation_run_id"
    t.datetime "created_at", null: false
    t.bigint "message_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "position", default: 0, null: false
    t.bigint "text_content_id"
    t.datetime "updated_at", null: false
    t.index ["conversation_run_id"], name: "index_message_swipes_on_conversation_run_id"
    t.index ["message_id", "position"], name: "index_message_swipes_on_message_id_and_position", unique: true
    t.index ["message_id"], name: "index_message_swipes_on_message_id"
    t.index ["text_content_id"], name: "index_message_swipes_on_text_content_id"
    t.check_constraint "jsonb_typeof(metadata) = 'object'::text", name: "message_swipes_metadata_object"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "active_message_swipe_id"
    t.text "content"
    t.bigint "conversation_id", null: false
    t.uuid "conversation_run_id"
    t.datetime "created_at", null: false
    t.boolean "excluded_from_prompt", default: false, null: false
    t.integer "message_swipes_count", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "origin_message_id"
    t.string "role", default: "user", null: false
    t.bigint "seq", null: false
    t.bigint "space_membership_id", null: false
    t.bigint "text_content_id"
    t.datetime "updated_at", null: false
    t.index ["active_message_swipe_id"], name: "index_messages_on_active_message_swipe_id"
    t.index ["conversation_id", "created_at", "id"], name: "index_messages_on_conversation_id_and_created_at_and_id"
    t.index ["conversation_id", "seq"], name: "index_messages_on_conversation_id_and_seq", unique: true
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["conversation_run_id"], name: "index_messages_on_conversation_run_id"
    t.index ["excluded_from_prompt"], name: "index_messages_on_excluded_from_prompt", where: "(excluded_from_prompt = true)"
    t.index ["origin_message_id"], name: "index_messages_on_origin_message_id"
    t.index ["space_membership_id"], name: "index_messages_on_space_membership_id"
    t.index ["text_content_id"], name: "index_messages_on_text_content_id"
    t.check_constraint "jsonb_typeof(metadata) = 'object'::text", name: "messages_metadata_object"
  end

  create_table "presets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "generation_settings", default: {}, null: false
    t.bigint "llm_provider_id"
    t.datetime "locked_at"
    t.string "name", null: false
    t.jsonb "preset_settings", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "visibility", default: "private", null: false
    t.index ["llm_provider_id"], name: "index_presets_on_llm_provider_id"
    t.index ["user_id", "name"], name: "index_presets_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_presets_on_user_id"
    t.index ["visibility"], name: "index_presets_on_visibility"
    t.check_constraint "jsonb_typeof(generation_settings) = 'object'::text", name: "presets_generation_settings_object"
    t.check_constraint "jsonb_typeof(preset_settings) = 'object'::text", name: "presets_preset_settings_object"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "last_active_at", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.jsonb "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "space_lorebooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.bigint "lorebook_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "source", default: "global", null: false
    t.bigint "space_id", null: false
    t.datetime "updated_at", null: false
    t.index ["lorebook_id"], name: "index_space_lorebooks_on_lorebook_id"
    t.index ["space_id", "lorebook_id"], name: "index_space_lorebooks_on_space_id_and_lorebook_id", unique: true
    t.index ["space_id", "priority"], name: "index_space_lorebooks_on_space_id_and_priority"
    t.index ["space_id"], name: "index_space_lorebooks_on_space_id"
  end

  create_table "space_memberships", force: :cascade do |t|
    t.string "cached_display_name"
    t.bigint "character_id"
    t.string "copilot_mode", default: "none", null: false
    t.integer "copilot_remaining_steps"
    t.datetime "created_at", null: false
    t.string "kind", default: "human", null: false
    t.bigint "llm_provider_id"
    t.string "participation", default: "active", null: false
    t.text "persona"
    t.integer "position", default: 0, null: false
    t.bigint "preset_id"
    t.datetime "removed_at"
    t.bigint "removed_by_id"
    t.string "removed_reason"
    t.string "role", default: "member", null: false
    t.jsonb "settings", default: {}, null: false
    t.integer "settings_version", default: 0, null: false
    t.bigint "space_id", null: false
    t.string "status", default: "active", null: false
    t.decimal "talkativeness_factor", precision: 3, scale: 2, default: "0.5", null: false
    t.datetime "unread_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["character_id"], name: "index_space_memberships_on_character_id"
    t.index ["llm_provider_id"], name: "index_space_memberships_on_llm_provider_id"
    t.index ["participation"], name: "index_space_memberships_on_participation"
    t.index ["preset_id"], name: "index_space_memberships_on_preset_id"
    t.index ["removed_by_id"], name: "index_space_memberships_on_removed_by_id"
    t.index ["space_id", "character_id"], name: "index_space_memberships_on_space_id_and_character_id", unique: true, where: "(character_id IS NOT NULL)"
    t.index ["space_id", "user_id"], name: "index_space_memberships_on_space_id_and_user_id", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["space_id"], name: "index_space_memberships_on_space_id"
    t.index ["status"], name: "index_space_memberships_on_status"
    t.index ["user_id"], name: "index_space_memberships_on_user_id"
    t.check_constraint "jsonb_typeof(settings) = 'object'::text", name: "space_memberships_settings_object"
    t.check_constraint "kind::text = 'character'::text AND user_id IS NULL AND (character_id IS NOT NULL OR status::text = 'removed'::text) OR kind::text = 'human'::text AND user_id IS NOT NULL", name: "space_memberships_kind_consistency"
  end

  create_table "spaces", force: :cascade do |t|
    t.boolean "allow_self_responses", default: false, null: false
    t.integer "auto_mode_delay_ms", default: 5000, null: false
    t.boolean "auto_mode_enabled", default: false, null: false
    t.string "card_handling_mode", default: "swap", null: false
    t.datetime "created_at", null: false
    t.string "during_generation_user_input_policy", default: "queue", null: false
    t.string "group_regenerate_mode", default: "single_message", null: false
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.jsonb "prompt_settings", default: {}, null: false
    t.boolean "relax_message_trim", default: false, null: false
    t.string "reply_order", default: "natural", null: false
    t.integer "settings_version", default: 0, null: false
    t.string "status", default: "active", null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.integer "user_turn_debounce_ms", default: 0, null: false
    t.string "visibility", default: "private", null: false
    t.index ["owner_id"], name: "index_spaces_on_owner_id"
    t.index ["visibility"], name: "index_spaces_on_visibility"
    t.check_constraint "jsonb_typeof(prompt_settings) = 'object'::text", name: "spaces_prompt_settings_object"
  end

  create_table "text_contents", force: :cascade do |t|
    t.text "content", null: false
    t.string "content_sha256", null: false
    t.datetime "created_at", null: false
    t.integer "references_count", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["content_sha256"], name: "index_text_contents_on_content_sha256", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name", null: false
    t.string "password_digest"
    t.string "role", default: "member", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true, where: "(email IS NOT NULL)"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "character_assets", "active_storage_blobs", column: "blob_id"
  add_foreign_key "character_assets", "characters"
  add_foreign_key "character_lorebooks", "characters", on_delete: :cascade
  add_foreign_key "character_lorebooks", "lorebooks", on_delete: :cascade
  add_foreign_key "character_uploads", "characters"
  add_foreign_key "character_uploads", "users"
  add_foreign_key "characters", "users", on_delete: :nullify
  add_foreign_key "conversation_lorebooks", "conversations", on_delete: :cascade
  add_foreign_key "conversation_lorebooks", "lorebooks", on_delete: :cascade
  add_foreign_key "conversation_runs", "conversations"
  add_foreign_key "conversation_runs", "space_memberships", column: "speaker_space_membership_id"
  add_foreign_key "conversations", "conversations", column: "parent_conversation_id"
  add_foreign_key "conversations", "conversations", column: "root_conversation_id"
  add_foreign_key "conversations", "messages", column: "forked_from_message_id"
  add_foreign_key "conversations", "spaces"
  add_foreign_key "lorebook_entries", "lorebooks", on_delete: :cascade
  add_foreign_key "lorebooks", "users", on_delete: :nullify
  add_foreign_key "message_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "message_attachments", "messages"
  add_foreign_key "message_swipes", "conversation_runs", on_delete: :nullify
  add_foreign_key "message_swipes", "messages", on_delete: :cascade
  add_foreign_key "message_swipes", "text_contents"
  add_foreign_key "messages", "conversation_runs", on_delete: :nullify
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "message_swipes", column: "active_message_swipe_id", on_delete: :nullify
  add_foreign_key "messages", "messages", column: "origin_message_id"
  add_foreign_key "messages", "space_memberships"
  add_foreign_key "messages", "text_contents"
  add_foreign_key "presets", "llm_providers", on_delete: :nullify
  add_foreign_key "presets", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "space_lorebooks", "lorebooks", on_delete: :cascade
  add_foreign_key "space_lorebooks", "spaces", on_delete: :cascade
  add_foreign_key "space_memberships", "characters", on_delete: :nullify
  add_foreign_key "space_memberships", "llm_providers", on_delete: :nullify
  add_foreign_key "space_memberships", "presets"
  add_foreign_key "space_memberships", "spaces"
  add_foreign_key "space_memberships", "users", column: "removed_by_id", on_delete: :nullify
  add_foreign_key "space_memberships", "users", on_delete: :nullify
  add_foreign_key "spaces", "users", column: "owner_id"
end
