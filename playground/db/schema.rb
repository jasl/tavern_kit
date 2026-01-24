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

ActiveRecord::Schema[8.2].define(version: 2026_01_25_070000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "active_storage_attachments", comment: "ActiveStorage attachment join table", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false, comment: "Attachment name (e.g., avatar, document)"
    t.bigint "record_id", null: false, comment: "Polymorphic owner record ID"
    t.string "record_type", null: false, comment: "Polymorphic owner model name"
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", comment: "ActiveStorage blob metadata", force: :cascade do |t|
    t.bigint "byte_size", null: false, comment: "File size in bytes"
    t.string "checksum", comment: "MD5 checksum for integrity verification"
    t.string "content_type", comment: "MIME type of the file"
    t.datetime "created_at", null: false
    t.string "filename", null: false, comment: "Original filename"
    t.string "key", null: false, comment: "Unique storage key"
    t.text "metadata", comment: "Additional file metadata as JSON"
    t.string "service_name", null: false, comment: "Storage service identifier"
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", comment: "ActiveStorage variant tracking", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false, comment: "Digest of the variant transformations"
    t.index ["blob_id", "variation_digest"], name: "idx_on_blob_id_variation_digest_f36bede0d9", unique: true
    t.index ["blob_id"], name: "index_active_storage_variant_records_on_blob_id"
  end

  create_table "character_assets", comment: "Character-associated files (icons, backgrounds)", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.bigint "character_id", null: false
    t.string "content_sha256", comment: "SHA256 hash for deduplication"
    t.datetime "created_at", null: false
    t.string "ext", comment: "File extension"
    t.string "kind", default: "icon", null: false, comment: "Asset type: icon, background, emotion"
    t.string "name", null: false, comment: "Asset name (unique per character)"
    t.datetime "updated_at", null: false
    t.index ["blob_id"], name: "index_character_assets_on_blob_id"
    t.index ["character_id", "name"], name: "index_character_assets_on_character_id_and_name", unique: true
    t.index ["character_id"], name: "index_character_assets_on_character_id"
    t.index ["content_sha256"], name: "index_character_assets_on_content_sha256"
  end

  create_table "character_uploads", comment: "Pending character card upload queue", force: :cascade do |t|
    t.bigint "character_id", comment: "Created character (after processing)"
    t.string "content_type", comment: "MIME type of uploaded file"
    t.datetime "created_at", null: false
    t.text "error_message", comment: "Processing error message"
    t.string "filename", comment: "Original filename"
    t.string "status", default: "pending", null: false, comment: "Processing status: pending, processing, completed, failed"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false, comment: "Uploading user"
    t.index ["character_id"], name: "index_character_uploads_on_character_id"
    t.index ["user_id"], name: "index_character_uploads_on_user_id"
  end

  create_table "characters", comment: "AI character definitions (Character Card spec)", force: :cascade do |t|
    t.jsonb "authors_note_settings", default: {}, null: false, comment: "Default author's note settings for this character"
    t.datetime "created_at", null: false
    t.jsonb "data", default: {}, null: false, comment: "Full Character Card data (CCv2/CCv3 spec fields)"
    t.string "extra_world_names", default: [], null: false, comment: "Additional lorebook names (soft links; extracted from data.extensions.extra_worlds)", array: true
    t.string "file_sha256", comment: "SHA256 of the original character card file"
    t.datetime "locked_at", comment: "Lock timestamp for system/built-in characters"
    t.integer "messages_count", default: 0, null: false, comment: "Counter cache for messages"
    t.string "name", null: false, comment: "Character display name"
    t.string "nickname", comment: "Alternative short name"
    t.boolean "nsfw", default: false, null: false, comment: "Whether character is NSFW"
    t.text "personality", comment: "Character personality summary (extracted from data)"
    t.integer "spec_version", comment: "Character Card spec version: 2 or 3"
    t.string "status", default: "pending", null: false, comment: "Processing status: pending, ready, failed, deleting"
    t.string "supported_languages", default: [], null: false, comment: "Languages the character supports", array: true
    t.string "tags", default: [], null: false, comment: "Searchable tags", array: true
    t.datetime "updated_at", null: false
    t.bigint "user_id", comment: "Owner user (null if orphaned)"
    t.string "visibility", default: "private", null: false, comment: "Visibility: private, unlisted, public"
    t.string "world_name", comment: "Primary lorebook name (soft link; extracted from data.extensions.world)"
    t.index ["extra_world_names"], name: "index_characters_on_extra_world_names", using: :gin
    t.index ["file_sha256"], name: "index_characters_on_file_sha256"
    t.index ["messages_count"], name: "index_characters_on_messages_count"
    t.index ["name"], name: "index_characters_on_name"
    t.index ["nsfw"], name: "index_characters_on_nsfw"
    t.index ["tags"], name: "index_characters_on_tags", using: :gin
    t.index ["user_id"], name: "index_characters_on_user_id"
    t.index ["visibility"], name: "index_characters_on_visibility"
    t.index ["world_name"], name: "index_characters_on_world_name"
    t.check_constraint "jsonb_typeof(authors_note_settings) = 'object'::text", name: "characters_authors_note_settings_object"
    t.check_constraint "jsonb_typeof(data) = 'object'::text", name: "characters_data_object"
  end

  create_table "conversation_events", comment: "Append-only domain events for conversations (scheduler/run observability)", force: :cascade do |t|
    t.bigint "conversation_id", null: false, comment: "Conversation this event belongs to"
    t.uuid "conversation_round_id", comment: "TurnScheduler round (nullable; round may be cleaned)"
    t.uuid "conversation_run_id", comment: "ConversationRun (nullable; run may be cleaned)"
    t.datetime "created_at", null: false
    t.string "event_name", null: false, comment: "Event name (e.g. turn_scheduler.round_paused, conversation_run.failed)"
    t.bigint "message_id", comment: "Message created/affected by this event (nullable)"
    t.datetime "occurred_at", null: false, comment: "Event timestamp"
    t.jsonb "payload", default: {}, null: false, comment: "Structured event payload (JSON object)"
    t.string "reason", comment: "Stable reason identifier (optional)"
    t.bigint "space_id", null: false, comment: "Space for convenient filtering"
    t.bigint "speaker_space_membership_id", comment: "Speaker membership (nullable)"
    t.bigint "trigger_message_id", comment: "Trigger message (nullable)"
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "occurred_at"], name: "index_conversation_events_on_conversation_id_and_occurred_at", order: { occurred_at: :desc }, comment: "Fast event stream for a conversation"
    t.index ["conversation_round_id", "occurred_at"], name: "index_conversation_events_on_round_id_and_occurred_at", order: { occurred_at: :desc }, comment: "Fast event stream for a round"
    t.index ["conversation_run_id", "occurred_at"], name: "index_conversation_events_on_run_id_and_occurred_at", order: { occurred_at: :desc }, comment: "Fast event stream for a run"
    t.index ["event_name", "occurred_at"], name: "index_conversation_events_on_event_name_and_occurred_at", order: { occurred_at: :desc }, comment: "Search recent events by name"
    t.index ["occurred_at"], name: "index_conversation_events_on_occurred_at", comment: "Cleanup / retention scans"
    t.index ["space_id", "occurred_at"], name: "index_conversation_events_on_space_id_and_occurred_at", order: { occurred_at: :desc }, comment: "Fast event stream for a space"
    t.check_constraint "jsonb_typeof(payload) = 'object'::text", name: "conversation_events_payload_object"
  end

  create_table "conversation_lorebooks", comment: "Join table: conversations <-> lorebooks", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false, comment: "Whether lorebook is active"
    t.bigint "lorebook_id", null: false
    t.integer "priority", default: 0, null: false, comment: "Loading priority"
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "lorebook_id"], name: "idx_on_conversation_id_lorebook_id_cb22900952", unique: true
    t.index ["conversation_id", "priority"], name: "index_conversation_lorebooks_on_conversation_id_and_priority"
    t.index ["conversation_id"], name: "index_conversation_lorebooks_on_conversation_id"
    t.index ["lorebook_id"], name: "index_conversation_lorebooks_on_lorebook_id"
  end

  create_table "conversation_round_participants", comment: "Ordered participant queue entries for a round", force: :cascade do |t|
    t.uuid "conversation_round_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", null: false, comment: "0-based position in the round queue"
    t.string "skip_reason"
    t.datetime "skipped_at"
    t.bigint "space_membership_id", null: false
    t.datetime "spoken_at"
    t.string "status", default: "pending", null: false, comment: "State: pending, spoken, skipped"
    t.datetime "updated_at", null: false
    t.index ["conversation_round_id", "position"], name: "index_conversation_round_participants_on_round_and_position", unique: true
    t.index ["conversation_round_id"], name: "index_conversation_round_participants_on_conversation_round_id"
    t.index ["space_membership_id"], name: "index_conversation_round_participants_on_space_membership_id"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'spoken'::character varying::text, 'skipped'::character varying::text])", name: "conversation_round_participants_status_check"
  end

  create_table "conversation_rounds", id: :uuid, default: -> { "gen_random_uuid()" }, comment: "TurnScheduler round runtime state", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.integer "current_position", default: 0, null: false, comment: "0-based index into participants queue"
    t.string "ended_reason", comment: "Why round ended (optional)"
    t.datetime "finished_at", comment: "When the round ended (null when active)"
    t.jsonb "metadata", default: {}, null: false, comment: "Diagnostic metadata"
    t.string "scheduling_state", comment: "Scheduling state: ai_generating, paused, failed (null when not active)"
    t.string "status", default: "active", null: false, comment: "Lifecycle: active, finished, superseded, canceled"
    t.bigint "trigger_message_id", comment: "Trigger message (optional)"
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_conversation_rounds_on_conversation_id"
    t.index ["conversation_id"], name: "index_conversation_rounds_unique_active_per_conversation", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["finished_at"], name: "index_conversation_rounds_on_finished_at"
    t.index ["status"], name: "index_conversation_rounds_on_status"
    t.index ["trigger_message_id"], name: "index_conversation_rounds_on_trigger_message_id"
    t.check_constraint "jsonb_typeof(metadata) = 'object'::text", name: "conversation_rounds_metadata_object"
    t.check_constraint "scheduling_state IS NULL OR (scheduling_state::text = ANY (ARRAY['ai_generating'::character varying::text, 'paused'::character varying::text, 'failed'::character varying::text]))", name: "conversation_rounds_scheduling_state_check"
    t.check_constraint "status::text <> 'active'::text OR scheduling_state IS NOT NULL", name: "conversation_rounds_active_requires_scheduling_state"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying::text, 'finished'::character varying::text, 'superseded'::character varying::text, 'canceled'::character varying::text])", name: "conversation_rounds_status_check"
  end

  create_table "conversation_runs", id: :uuid, default: -> { "gen_random_uuid()" }, comment: "AI generation runtime units (state machine)", force: :cascade do |t|
    t.datetime "cancel_requested_at", comment: "Soft-cancel signal timestamp (for restart policy)"
    t.bigint "conversation_id", null: false
    t.uuid "conversation_round_id", comment: "Associated TurnScheduler round (nullable; may be cleaned)"
    t.datetime "created_at", null: false
    t.jsonb "debug", default: {}, null: false, comment: "Debug information (prompt stats, etc.)"
    t.jsonb "error", default: {}, null: false, comment: "Error details if run failed"
    t.datetime "finished_at", comment: "Completion timestamp"
    t.datetime "heartbeat_at", comment: "Last heartbeat for stale detection"
    t.string "kind", null: false, comment: "Run kind: auto_response, auto_user_response, regenerate, force_talk"
    t.string "reason", null: false, comment: "Human-readable reason (user_message, force_talk, etc.)"
    t.datetime "run_after", comment: "Scheduled execution time (for debounce/delay)"
    t.bigint "speaker_space_membership_id", comment: "Member who is speaking for this run"
    t.datetime "started_at", comment: "When run transitioned to running"
    t.string "status", null: false, comment: "State: queued, running, succeeded, failed, canceled, skipped"
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "status"], name: "index_conversation_runs_on_conversation_id_and_status"
    t.index ["conversation_id"], name: "index_conversation_runs_on_conversation_id"
    t.index ["conversation_id"], name: "index_conversation_runs_unique_queued_per_conversation", unique: true, where: "((status)::text = 'queued'::text)"
    t.index ["conversation_id"], name: "index_conversation_runs_unique_running_per_conversation", unique: true, where: "((status)::text = 'running'::text)"
    t.index ["conversation_round_id"], name: "index_conversation_runs_on_conversation_round_id"
    t.index ["kind"], name: "index_conversation_runs_on_kind"
    t.index ["speaker_space_membership_id"], name: "index_conversation_runs_on_speaker_space_membership_id"
    t.index ["status"], name: "index_conversation_runs_on_status"
    t.check_constraint "jsonb_typeof(debug) = 'object'::text", name: "conversation_runs_debug_object"
    t.check_constraint "jsonb_typeof(error) = 'object'::text", name: "conversation_runs_error_object"
  end

  create_table "conversations", comment: "Chat conversation threads within a space", force: :cascade do |t|
    t.text "authors_note", comment: "Author's note text for this conversation"
    t.integer "authors_note_depth", comment: "Injection depth for author's note"
    t.string "authors_note_position", comment: "Injection position for author's note"
    t.string "authors_note_role", comment: "Message role for author's note"
    t.integer "auto_without_human_remaining_rounds", comment: "Remaining rounds in auto without human (null = disabled, >0 = active)"
    t.bigint "completion_tokens_total", default: 0, null: false, comment: "Cumulative completion tokens used"
    t.datetime "created_at", null: false
    t.bigint "forked_from_message_id", comment: "Message where this branch forked from"
    t.bigint "group_queue_revision", default: 0, null: false, comment: "Monotonic counter for queue updates (prevents stale broadcasts)"
    t.string "kind", default: "root", null: false, comment: "Conversation kind: root, branch, thread, checkpoint"
    t.bigint "parent_conversation_id", comment: "Parent conversation for branches"
    t.bigint "prompt_tokens_total", default: 0, null: false, comment: "Cumulative prompt tokens used"
    t.bigint "root_conversation_id", comment: "Root conversation of the tree"
    t.bigint "space_id", null: false
    t.string "status", default: "ready", null: false, comment: "Conversation status: ready, pending, failed, archived"
    t.string "title", null: false, comment: "Conversation display title"
    t.integer "turns_count", default: 0, null: false, comment: "Total turns in this conversation"
    t.datetime "updated_at", null: false
    t.jsonb "variables", default: {}, null: false, comment: "Chat variables for macro expansion (ST {{getvar}})"
    t.string "visibility", default: "shared", null: false, comment: "Visibility: private, shared, public"
    t.index ["forked_from_message_id"], name: "index_conversations_on_forked_from_message_id"
    t.index ["parent_conversation_id"], name: "index_conversations_on_parent_conversation_id"
    t.index ["root_conversation_id", "kind"], name: "index_conversations_on_root_conversation_id_and_kind", comment: "Optimize conversation tree queries by kind"
    t.index ["root_conversation_id"], name: "index_conversations_on_root_conversation_id"
    t.index ["space_id", "status", "updated_at"], name: "index_conversations_on_space_id_and_status_and_updated_at", order: { updated_at: :desc }, comment: "Optimize Space conversation listings with status filter"
    t.index ["space_id"], name: "index_conversations_on_space_id"
    t.index ["visibility"], name: "index_conversations_on_visibility"
    t.check_constraint "jsonb_typeof(variables) = 'object'::text", name: "conversations_variables_object"
  end

  create_table "invite_codes", comment: "Invitation codes for user registration", force: :cascade do |t|
    t.string "code", null: false, comment: "Unique invitation code string"
    t.datetime "created_at", null: false
    t.bigint "created_by_id", comment: "FK to users - admin who created this code"
    t.datetime "expires_at", comment: "Expiration timestamp (null = never expires)"
    t.integer "max_uses", comment: "Maximum allowed uses (null = unlimited)"
    t.string "note", comment: "Admin note about this invite code"
    t.datetime "updated_at", null: false
    t.integer "uses_count", default: 0, null: false, comment: "Number of times this code has been used"
    t.index ["code"], name: "index_invite_codes_on_code", unique: true
    t.index ["created_by_id"], name: "index_invite_codes_on_created_by_id"
  end

  create_table "llm_providers", comment: "LLM API provider configurations", force: :cascade do |t|
    t.text "api_key", comment: "API key for authentication (encrypted)"
    t.string "base_url", null: false, comment: "Base URL for API requests"
    t.datetime "created_at", null: false
    t.boolean "disabled", default: false, null: false, comment: "Whether this provider is disabled"
    t.string "identification", default: "openai_compatible", null: false, comment: "Provider type: openai_compatible, anthropic, google, etc."
    t.datetime "last_tested_at", comment: "Last successful connection test timestamp"
    t.string "model", comment: "Default model identifier for this provider"
    t.string "name", null: false, comment: "Human-readable provider name"
    t.boolean "streamable", default: true, comment: "Whether streaming responses are supported"
    t.boolean "supports_logprobs", default: false, null: false, comment: "Whether logprobs are supported"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_llm_providers_on_name", unique: true
  end

  create_table "lorebook_entries", comment: "Individual World Info entries (ST/RisuAI compatible)", force: :cascade do |t|
    t.string "automation_id", comment: "ST automation script identifier"
    t.boolean "case_sensitive", comment: "Case-sensitive keyword matching"
    t.string "comment", comment: "Entry comment/label"
    t.boolean "constant", default: false, null: false, comment: "Always include in context (bypass keyword matching)"
    t.text "content", comment: "Entry content to inject into prompt"
    t.integer "cooldown", comment: "Minimum messages between activations"
    t.datetime "created_at", null: false
    t.integer "delay", comment: "Messages before first activation"
    t.integer "delay_until_recursion", comment: "Delay before recursive scanning starts"
    t.integer "depth", default: 4, null: false, comment: "How many recent messages to scan for keywords"
    t.boolean "enabled", default: true, null: false, comment: "Whether entry is active"
    t.boolean "exclude_recursion", default: false, null: false, comment: "Exclude from recursive scanning"
    t.string "group", comment: "Grouping identifier for mutual exclusion"
    t.boolean "group_override", default: false, null: false, comment: "Override group scoring to always win"
    t.integer "group_weight", default: 100, null: false, comment: "Weight for group scoring"
    t.boolean "ignore_budget", default: false, null: false, comment: "Ignore token budget limits"
    t.integer "insertion_order", default: 100, null: false, comment: "Order within injection position"
    t.text "keys", default: [], null: false, comment: "Primary trigger keywords", array: true
    t.bigint "lorebook_id", null: false
    t.boolean "match_character_depth_prompt", default: false, null: false, comment: "Also scan character depth prompt"
    t.boolean "match_character_description", default: false, null: false, comment: "Also scan character description"
    t.boolean "match_character_personality", default: false, null: false, comment: "Also scan character personality"
    t.boolean "match_creator_notes", default: false, null: false, comment: "Also scan creator notes"
    t.boolean "match_persona_description", default: false, null: false, comment: "Also scan user persona"
    t.boolean "match_scenario", default: false, null: false, comment: "Also scan scenario text"
    t.boolean "match_whole_words", comment: "Match whole words only"
    t.string "outlet", comment: "Named outlet for insertion"
    t.string "position", default: "after_char_defs", null: false, comment: "Injection position: before_char, after_char, after_char_defs, after_an, at_depth, etc."
    t.integer "position_index", default: 0, null: false, comment: "Index within position for ordering"
    t.boolean "prevent_recursion", default: false, null: false, comment: "Prevent this entry from triggering other entries"
    t.integer "probability", default: 100, null: false, comment: "Activation probability percentage (0-100)"
    t.string "role", default: "system", null: false, comment: "Message role for injection: system, user, assistant"
    t.integer "scan_depth", comment: "Override scan depth for this entry"
    t.text "secondary_keys", default: [], null: false, comment: "Secondary keywords (for selective logic)", array: true
    t.boolean "selective", default: false, null: false, comment: "Enable secondary keyword matching"
    t.string "selective_logic", default: "and_any", null: false, comment: "Logic for combining keys: and_any, and_all, not_any, not_all"
    t.integer "sticky", comment: "Stick to context for N messages after trigger"
    t.string "triggers", default: [], null: false, comment: "CCv3 trigger macros/events", array: true
    t.string "uid", null: false, comment: "Unique identifier within lorebook"
    t.datetime "updated_at", null: false
    t.boolean "use_group_scoring", comment: "Enable group scoring mode"
    t.boolean "use_probability", default: true, null: false, comment: "Enable probability-based activation"
    t.boolean "use_regex", default: false, null: false, comment: "Treat keys as regex patterns"
    t.index ["enabled"], name: "index_lorebook_entries_on_enabled"
    t.index ["lorebook_id", "position_index"], name: "index_lorebook_entries_on_lorebook_id_and_position_index"
    t.index ["lorebook_id", "uid"], name: "index_lorebook_entries_on_lorebook_id_and_uid", unique: true
    t.index ["lorebook_id"], name: "index_lorebook_entries_on_lorebook_id"
  end

  create_table "lorebook_uploads", comment: "Pending lorebook import queue", force: :cascade do |t|
    t.string "content_type", comment: "MIME type of uploaded file"
    t.datetime "created_at", null: false
    t.text "error_message", comment: "Processing error message"
    t.string "filename", comment: "Original filename"
    t.bigint "lorebook_id", comment: "Created lorebook (after processing)"
    t.string "status", default: "pending", null: false, comment: "Processing status: pending, processing, completed, failed"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false, comment: "Uploading user"
    t.index ["lorebook_id"], name: "index_lorebook_uploads_on_lorebook_id"
    t.index ["user_id"], name: "index_lorebook_uploads_on_user_id"
  end

  create_table "lorebooks", comment: "World Info / Lorebook collections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", comment: "Human-readable description"
    t.integer "entries_count", default: 0, null: false, comment: "Counter cache for entries"
    t.string "file_sha256", comment: "SHA256 of the original lorebook JSON file"
    t.datetime "locked_at", comment: "Lock timestamp for system lorebooks"
    t.string "name", null: false, comment: "Lorebook display name"
    t.boolean "recursive_scanning", default: false, null: false, comment: "Enable recursive entry scanning (ST-compatible)"
    t.integer "scan_depth", default: 2, comment: "Default scan depth for entries"
    t.jsonb "settings", default: {}, null: false, comment: "Additional lorebook-level settings"
    t.string "status", default: "ready", null: false, comment: "Import status: pending, ready, failed"
    t.integer "token_budget", comment: "Max tokens for this lorebook's entries"
    t.datetime "updated_at", null: false
    t.bigint "user_id", comment: "Owner user"
    t.string "visibility", default: "private", null: false, comment: "Visibility: private, unlisted, public"
    t.index ["file_sha256"], name: "index_lorebooks_on_file_sha256"
    t.index ["name"], name: "index_lorebooks_on_name"
    t.index ["status"], name: "index_lorebooks_on_status"
    t.index ["user_id"], name: "index_lorebooks_on_user_id"
    t.index ["visibility"], name: "index_lorebooks_on_visibility"
    t.check_constraint "jsonb_typeof(settings) = 'object'::text", name: "lorebooks_settings_object"
  end

  create_table "message_attachments", comment: "Files attached to messages", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", default: "file", null: false, comment: "Attachment type: file, image, audio"
    t.bigint "message_id", null: false
    t.jsonb "metadata", default: {}, null: false, comment: "Attachment metadata"
    t.string "name", comment: "Display name for attachment"
    t.integer "position", default: 0, null: false, comment: "Display order"
    t.datetime "updated_at", null: false
    t.index ["blob_id"], name: "index_message_attachments_on_blob_id"
    t.index ["message_id", "blob_id"], name: "index_message_attachments_on_message_id_and_blob_id", unique: true
    t.index ["message_id"], name: "index_message_attachments_on_message_id"
  end

  create_table "message_swipes", comment: "Alternative message versions (regenerate/swipe)", force: :cascade do |t|
    t.text "content", comment: "Swipe text (or null if using text_content)"
    t.uuid "conversation_run_id", comment: "Run that generated this swipe"
    t.datetime "created_at", null: false
    t.bigint "message_id", null: false
    t.jsonb "metadata", default: {}, null: false, comment: "Swipe metadata"
    t.integer "position", default: 0, null: false, comment: "Position in swipe list (0-based)"
    t.bigint "text_content_id", comment: "FK to text_contents for COW storage"
    t.datetime "updated_at", null: false
    t.index ["conversation_run_id"], name: "index_message_swipes_on_conversation_run_id"
    t.index ["message_id", "position"], name: "index_message_swipes_on_message_id_and_position", unique: true
    t.index ["message_id"], name: "index_message_swipes_on_message_id"
    t.index ["text_content_id"], name: "index_message_swipes_on_text_content_id"
    t.check_constraint "jsonb_typeof(metadata) = 'object'::text", name: "message_swipes_metadata_object"
  end

  create_table "messages", comment: "Chat messages in conversations", force: :cascade do |t|
    t.bigint "active_message_swipe_id", comment: "Currently active swipe variant"
    t.text "content", comment: "Message text (or null if using text_content)"
    t.bigint "conversation_id", null: false
    t.uuid "conversation_run_id", comment: "Run that generated this message"
    t.datetime "created_at", null: false
    t.string "generation_status", comment: "AI generation status: generating, succeeded, failed"
    t.integer "message_swipes_count", default: 0, null: false, comment: "Counter cache for swipe variants"
    t.jsonb "metadata", default: {}, null: false, comment: "Additional metadata (token counts, etc.)"
    t.bigint "origin_message_id", comment: "Original message for forked/copied messages"
    t.string "role", default: "user", null: false, comment: "Message role: user, assistant, system"
    t.bigint "seq", null: false, comment: "Sequence number within conversation (unique, gap-allowed)"
    t.bigint "space_membership_id", null: false, comment: "Member who sent/generated this message"
    t.bigint "text_content_id", comment: "FK to text_contents for COW content storage"
    t.datetime "updated_at", null: false
    t.string "visibility", default: "normal", null: false, comment: "Visibility: normal, excluded, hidden"
    t.index ["active_message_swipe_id"], name: "index_messages_on_active_message_swipe_id"
    t.index ["conversation_id", "created_at", "id"], name: "index_messages_on_conversation_id_and_created_at_and_id"
    t.index ["conversation_id", "role", "seq"], name: "index_messages_on_conversation_id_and_role_and_seq", where: "((visibility)::text = 'normal'::text)", comment: "Optimize role-based message queries with prompt filtering"
    t.index ["conversation_id", "role", "seq"], name: "index_messages_on_conversation_id_and_role_and_seq_non_hidden", where: "((visibility)::text <> 'hidden'::text)", comment: "Optimize role-based message queries excluding hidden messages"
    t.index ["conversation_id", "seq"], name: "index_messages_on_conversation_id_and_seq", unique: true
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["conversation_run_id"], name: "index_messages_on_conversation_run_id"
    t.index ["generation_status"], name: "index_messages_on_generation_status"
    t.index ["origin_message_id"], name: "index_messages_on_origin_message_id"
    t.index ["space_membership_id"], name: "index_messages_on_space_membership_id"
    t.index ["text_content_id"], name: "index_messages_on_text_content_id"
    t.check_constraint "jsonb_typeof(metadata) = 'object'::text", name: "messages_metadata_object"
    t.check_constraint "visibility::text = ANY (ARRAY['normal'::character varying::text, 'excluded'::character varying::text, 'hidden'::character varying::text])", name: "messages_visibility_check"
  end

  create_table "presets", comment: "LLM generation presets (sampling parameters)", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", comment: "Human-readable description"
    t.jsonb "generation_settings", default: {}, null: false, comment: "LLM generation parameters (temperature, top_p, etc.)"
    t.bigint "llm_provider_id", comment: "Default LLM provider for this preset"
    t.datetime "locked_at", comment: "Lock timestamp for system presets"
    t.string "name", null: false, comment: "Preset display name"
    t.jsonb "preset_settings", default: {}, null: false, comment: "Non-generation settings (context size, etc.)"
    t.datetime "updated_at", null: false
    t.bigint "user_id", comment: "Owner user"
    t.string "visibility", default: "private", null: false, comment: "Visibility: private, unlisted, public"
    t.index ["llm_provider_id"], name: "index_presets_on_llm_provider_id"
    t.index ["user_id", "name"], name: "index_presets_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_presets_on_user_id"
    t.index ["visibility"], name: "index_presets_on_visibility"
    t.check_constraint "jsonb_typeof(generation_settings) = 'object'::text", name: "presets_generation_settings_object"
    t.check_constraint "jsonb_typeof(preset_settings) = 'object'::text", name: "presets_preset_settings_object"
  end

  create_table "sessions", comment: "User login sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address", comment: "Client IP address at login"
    t.datetime "last_active_at", null: false, comment: "Last activity timestamp"
    t.string "token", null: false, comment: "Session token for authentication"
    t.datetime "updated_at", null: false
    t.string "user_agent", comment: "Client user agent string"
    t.bigint "user_id", null: false
    t.index ["token"], name: "index_sessions_on_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", comment: "Global application settings (key-value store)", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false, comment: "Setting key identifier"
    t.datetime "updated_at", null: false
    t.jsonb "value", comment: "Setting value as JSON"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "space_lorebooks", comment: "Join table: spaces <-> lorebooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false, comment: "Whether lorebook is active"
    t.bigint "lorebook_id", null: false
    t.integer "priority", default: 0, null: false, comment: "Loading priority"
    t.string "source", default: "global", null: false, comment: "Source: global (space-wide), character (from character)"
    t.bigint "space_id", null: false
    t.datetime "updated_at", null: false
    t.index ["lorebook_id"], name: "index_space_lorebooks_on_lorebook_id"
    t.index ["space_id", "lorebook_id"], name: "index_space_lorebooks_on_space_id_and_lorebook_id", unique: true
    t.index ["space_id", "priority"], name: "index_space_lorebooks_on_space_id_and_priority"
    t.index ["space_id"], name: "index_space_lorebooks_on_space_id"
  end

  create_table "space_memberships", comment: "Space participants (humans and AI characters)", force: :cascade do |t|
    t.string "auto", default: "none", null: false, comment: "Auto: none, auto (AI writes for user persona)"
    t.integer "auto_remaining_steps", comment: "Remaining auto steps (null = disabled)"
    t.string "cached_display_name", comment: "Cached display name for performance"
    t.bigint "character_id", comment: "Character for AI members (null for humans)"
    t.datetime "created_at", null: false
    t.string "kind", default: "human", null: false, comment: "Member type: human, character"
    t.bigint "llm_provider_id", comment: "Override LLM provider for this member"
    t.string "name_override", comment: "Optional per-space display name override"
    t.string "participation", default: "active", null: false, comment: "Participation status: active, muted (skipped in queue)"
    t.text "persona", comment: "User persona description for this space"
    t.integer "position", default: 0, null: false, comment: "Display order and list reply_order position"
    t.bigint "preset_id", comment: "Override preset for this member"
    t.datetime "removed_at", comment: "Removal timestamp (soft delete)"
    t.bigint "removed_by_id", comment: "User who removed this member"
    t.string "removed_reason", comment: "Reason for removal"
    t.string "role", default: "member", null: false, comment: "Space role: owner, admin, member"
    t.jsonb "settings", default: {}, null: false, comment: "Per-member setting overrides"
    t.integer "settings_version", default: 0, null: false, comment: "Optimistic locking"
    t.bigint "space_id", null: false
    t.string "status", default: "active", null: false, comment: "Status: active, removed"
    t.decimal "talkativeness_factor", precision: 3, scale: 2, comment: "Pooled mode: probability weight for speaking (0.0-1.0)"
    t.datetime "unread_at", comment: "Timestamp when member last had unread messages"
    t.datetime "updated_at", null: false
    t.bigint "user_id", comment: "User for human members (null for AI)"
    t.index ["character_id"], name: "index_space_memberships_on_character_id"
    t.index ["llm_provider_id"], name: "index_space_memberships_on_llm_provider_id"
    t.index ["participation"], name: "index_space_memberships_on_participation"
    t.index ["preset_id"], name: "index_space_memberships_on_preset_id"
    t.index ["removed_by_id"], name: "index_space_memberships_on_removed_by_id"
    t.index ["space_id", "character_id"], name: "index_space_memberships_on_space_id_and_character_id", unique: true, where: "(character_id IS NOT NULL)"
    t.index ["space_id", "kind", "auto", "auto_remaining_steps"], name: "idx_on_space_id_kind_auto_auto_remaining_steps_9802662e01", where: "(((status)::text = 'active'::text) AND ((participation)::text = 'active'::text))", comment: "Optimize AI-respondable membership queries"
    t.index ["space_id", "user_id"], name: "index_space_memberships_on_space_id_and_user_id", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["space_id"], name: "index_space_memberships_on_space_id"
    t.index ["status"], name: "index_space_memberships_on_status"
    t.index ["user_id"], name: "index_space_memberships_on_user_id"
    t.check_constraint "jsonb_typeof(settings) = 'object'::text", name: "space_memberships_settings_object"
    t.check_constraint "kind::text = 'character'::text AND user_id IS NULL AND (character_id IS NOT NULL OR status::text = 'removed'::text) OR kind::text = 'human'::text AND user_id IS NOT NULL", name: "space_memberships_kind_consistency"
  end

  create_table "spaces", comment: "Chat spaces (STI: Spaces::Playground, Spaces::Discussion)", force: :cascade do |t|
    t.boolean "allow_self_responses", default: false, null: false, comment: "Group chat: allow same character to respond consecutively (ST group_chat_self_responses)"
    t.integer "auto_without_human_delay_ms", default: 5000, null: false, comment: "Delay between AI responses in auto without human (milliseconds)"
    t.string "card_handling_mode", default: "swap", null: false, comment: "How to handle new characters: swap, append, append_disabled"
    t.bigint "completion_tokens_total", default: 0, null: false, comment: "Cumulative completion tokens used (for limits)"
    t.datetime "created_at", null: false
    t.string "during_generation_user_input_policy", default: "reject", null: false, comment: "Policy when user sends message during AI generation: reject (lock input), restart (interrupt), queue (allow)"
    t.string "group_regenerate_mode", default: "single_message", null: false, comment: "Group regenerate behavior: single_message (swipe one), last_turn (redo all AI responses)"
    t.string "name", null: false, comment: "Space display name"
    t.bigint "owner_id", null: false, comment: "Space owner"
    t.jsonb "prompt_settings", default: {}, null: false, comment: "Prompt building settings (system prompt, context template, etc.)"
    t.bigint "prompt_tokens_total", default: 0, null: false, comment: "Cumulative prompt tokens used (for limits)"
    t.boolean "relax_message_trim", default: false, null: false, comment: "Group chat: allow AI to generate dialogue for other characters"
    t.string "reply_order", default: "natural", null: false, comment: "Group reply order: natural (mention-based), list (position), pooled (random talkative), manual"
    t.integer "settings_version", default: 0, null: false, comment: "Optimistic locking version for settings"
    t.string "status", default: "active", null: false, comment: "Space status: active, archived, deleting"
    t.bigint "token_limit", default: 0, comment: "Optional token limit (0 = unlimited)"
    t.string "type", null: false, comment: "STI type: Spaces::Playground, Spaces::Discussion"
    t.datetime "updated_at", null: false
    t.integer "user_turn_debounce_ms", default: 0, null: false, comment: "Debounce time for merging rapid user messages (0 = no merge)"
    t.string "visibility", default: "private", null: false, comment: "Visibility: private, public"
    t.index ["owner_id"], name: "index_spaces_on_owner_id"
    t.index ["visibility"], name: "index_spaces_on_visibility"
    t.check_constraint "jsonb_typeof(prompt_settings) = 'object'::text", name: "spaces_prompt_settings_object"
  end

  create_table "text_contents", comment: "Content-addressable text storage for COW (Copy-on-Write)", force: :cascade do |t|
    t.text "content", null: false, comment: "The actual text content"
    t.string "content_sha256", null: false, comment: "SHA256 hash of content for deduplication"
    t.datetime "created_at", null: false
    t.integer "references_count", default: 1, null: false, comment: "Number of messages referencing this content"
    t.datetime "updated_at", null: false
    t.index ["content_sha256"], name: "index_text_contents_on_content_sha256", unique: true
  end

  create_table "users", comment: "User accounts for the system", force: :cascade do |t|
    t.integer "characters_count", default: 0, null: false, comment: "Counter cache for user-owned characters"
    t.bigint "completion_tokens_total", default: 0, null: false, comment: "Cumulative completion tokens as space owner (for billing)"
    t.integer "conversations_count", default: 0, null: false, comment: "Counter cache for user conversations"
    t.datetime "created_at", null: false
    t.string "email", comment: "User email address (optional, unique when present)"
    t.bigint "invited_by_code_id", comment: "FK to invite_codes - code used for registration"
    t.integer "lorebooks_count", default: 0, null: false, comment: "Counter cache for user-owned lorebooks"
    t.integer "messages_count", default: 0, null: false, comment: "Counter cache for user messages"
    t.string "name", null: false, comment: "Display name for the user"
    t.string "password_digest", comment: "BCrypt password hash"
    t.bigint "prompt_tokens_total", default: 0, null: false, comment: "Cumulative prompt tokens as space owner (for billing)"
    t.string "role", default: "member", null: false, comment: "User role: admin, member"
    t.string "status", default: "active", null: false, comment: "Account status: active, suspended, deleted"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["invited_by_code_id"], name: "index_users_on_invited_by_code_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "character_assets", "active_storage_blobs", column: "blob_id"
  add_foreign_key "character_assets", "characters"
  add_foreign_key "character_uploads", "characters"
  add_foreign_key "character_uploads", "users"
  add_foreign_key "characters", "users", on_delete: :nullify
  add_foreign_key "conversation_lorebooks", "conversations", on_delete: :cascade
  add_foreign_key "conversation_lorebooks", "lorebooks", on_delete: :cascade
  add_foreign_key "conversation_round_participants", "conversation_rounds", on_delete: :cascade
  add_foreign_key "conversation_round_participants", "space_memberships"
  add_foreign_key "conversation_rounds", "conversations", on_delete: :cascade
  add_foreign_key "conversation_rounds", "messages", column: "trigger_message_id", on_delete: :nullify
  add_foreign_key "conversation_runs", "conversation_rounds", on_delete: :nullify
  add_foreign_key "conversation_runs", "conversations"
  add_foreign_key "conversation_runs", "space_memberships", column: "speaker_space_membership_id"
  add_foreign_key "conversations", "conversations", column: "parent_conversation_id"
  add_foreign_key "conversations", "conversations", column: "root_conversation_id"
  add_foreign_key "conversations", "messages", column: "forked_from_message_id"
  add_foreign_key "conversations", "spaces"
  add_foreign_key "invite_codes", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "lorebook_entries", "lorebooks", on_delete: :cascade
  add_foreign_key "lorebook_uploads", "lorebooks"
  add_foreign_key "lorebook_uploads", "users"
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
  add_foreign_key "space_memberships", "characters"
  add_foreign_key "space_memberships", "llm_providers", on_delete: :nullify
  add_foreign_key "space_memberships", "presets"
  add_foreign_key "space_memberships", "spaces"
  add_foreign_key "space_memberships", "users"
  add_foreign_key "space_memberships", "users", column: "removed_by_id", on_delete: :nullify
  add_foreign_key "spaces", "users", column: "owner_id"
  add_foreign_key "users", "invite_codes", column: "invited_by_code_id", on_delete: :nullify
end
