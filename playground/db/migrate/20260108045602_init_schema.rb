# frozen_string_literal: true

class InitSchema < ActiveRecord::Migration[8.1]
  def change
    enable_extension :pgcrypto unless extension_enabled?(:pgcrypto)

    # === Independent tables (no foreign key dependencies) ===

    # invite_codes and users have circular references (created_by, invited_by_code)
    # Create tables first without FKs, add FKs later
    create_table :invite_codes, comment: "Invitation codes for user registration" do |t|
      t.string :code, null: false, comment: "Unique invitation code string"
      t.string :note, comment: "Admin note about this invite code"
      t.integer :uses_count, default: 0, null: false, comment: "Number of times this code has been used"
      t.integer :max_uses, comment: "Maximum allowed uses (null = unlimited)"
      t.datetime :expires_at, comment: "Expiration timestamp (null = never expires)"
      t.bigint :created_by_id, comment: "FK to users - admin who created this code"

      t.timestamps

      t.index :code, unique: true
      t.index :created_by_id
    end

    create_table :users, comment: "User accounts for the system" do |t|
      t.string :email, comment: "User email address (optional, unique when present)"
      t.string :name, null: false, comment: "Display name for the user"
      t.string :password_digest, comment: "BCrypt password hash"
      t.string :role, default: "member", null: false, comment: "User role: admin, member"
      t.string :status, default: "active", null: false, comment: "Account status: active, suspended, deleted"
      t.bigint :invited_by_code_id, comment: "FK to invite_codes - code used for registration"
      t.integer :conversations_count, default: 0, null: false, comment: "Counter cache for user conversations"
      t.integer :messages_count, default: 0, null: false, comment: "Counter cache for user messages"
      t.integer :characters_count, default: 0, null: false, comment: "Counter cache for user-owned characters"
      t.integer :lorebooks_count, default: 0, null: false, comment: "Counter cache for user-owned lorebooks"

      t.timestamps

      t.index :email, unique: true, where: "(email IS NOT NULL)"
      t.index :invited_by_code_id
    end

    create_table :llm_providers, comment: "LLM API provider configurations" do |t|
      t.text :api_key, comment: "API key for authentication (encrypted)"
      t.string :base_url, null: false, comment: "Base URL for API requests"
      t.boolean :disabled, default: false, null: false, comment: "Whether this provider is disabled"
      t.string :identification, default: "openai_compatible", null: false,
               comment: "Provider type: openai_compatible, anthropic, google, etc."
      t.datetime :last_tested_at, comment: "Last successful connection test timestamp"
      t.string :model, comment: "Default model identifier for this provider"
      t.string :name, null: false, comment: "Human-readable provider name"
      t.boolean :streamable, default: true, comment: "Whether streaming responses are supported"
      t.boolean :supports_logprobs, default: false, null: false, comment: "Whether logprobs are supported"

      t.timestamps

      t.index :name, unique: true
    end

    create_table :settings, comment: "Global application settings (key-value store)" do |t|
      t.string :key, null: false, comment: "Setting key identifier"
      t.jsonb :value, comment: "Setting value as JSON"

      t.timestamps

      t.index :key, unique: true
    end

    create_table :active_storage_blobs, comment: "ActiveStorage blob metadata" do |t|
      t.datetime :created_at, null: false
      t.bigint :byte_size, null: false, comment: "File size in bytes"
      t.string :checksum, comment: "MD5 checksum for integrity verification"
      t.string :content_type, comment: "MIME type of the file"
      t.string :filename, null: false, comment: "Original filename"
      t.string :key, null: false, comment: "Unique storage key"
      t.text :metadata, comment: "Additional file metadata as JSON"
      t.string :service_name, null: false, comment: "Storage service identifier"

      t.index :key, unique: true
    end

    create_table :text_contents, comment: "Content-addressable text storage for COW (Copy-on-Write)" do |t|
      t.text :content, null: false, comment: "The actual text content"
      t.string :content_sha256, null: false, comment: "SHA256 hash of content for deduplication"
      t.integer :references_count, default: 1, null: false, comment: "Number of messages referencing this content"

      t.timestamps

      t.index :content_sha256, unique: true
    end

    # === Tables with single-level dependencies ===

    create_table :active_storage_attachments, comment: "ActiveStorage attachment join table" do |t|
      t.datetime :created_at, null: false
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.bigint :record_id, null: false, comment: "Polymorphic owner record ID"
      t.string :record_type, null: false, comment: "Polymorphic owner model name"
      t.string :name, null: false, comment: "Attachment name (e.g., avatar, document)"

      t.index %i[record_type record_id name blob_id], name: :index_active_storage_attachments_uniqueness, unique: true
    end

    create_table :active_storage_variant_records, comment: "ActiveStorage variant tracking" do |t|
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.string :variation_digest, null: false, comment: "Digest of the variant transformations"

      t.index %i[blob_id variation_digest], unique: true
    end

    create_table :sessions, comment: "User login sessions" do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address, comment: "Client IP address at login"
      t.datetime :last_active_at, null: false, comment: "Last activity timestamp"
      t.string :token, null: false, comment: "Session token for authentication"
      t.string :user_agent, comment: "Client user agent string"

      t.timestamps

      t.index :token, unique: true
    end

    create_table :characters, comment: "AI character definitions (Character Card spec)" do |t|
      t.references :user, foreign_key: { on_delete: :nullify }, comment: "Owner user (null if orphaned)"
      t.jsonb :authors_note_settings, default: {}, null: false,
              comment: "Default author's note settings for this character"
      t.jsonb :data, default: {}, null: false,
              comment: "Full Character Card data (CCv2/CCv3 spec fields)"
      t.string :file_sha256, comment: "SHA256 of the original character card file"
      t.datetime :locked_at, comment: "Lock timestamp for system/built-in characters"
      t.string :name, null: false, comment: "Character display name"
      t.string :nickname, comment: "Alternative short name"
      t.boolean :nsfw, default: false, null: false, comment: "Whether character is NSFW"
      t.text :personality, comment: "Character personality summary (extracted from data)"
      t.integer :spec_version, comment: "Character Card spec version: 2 or 3"
      t.string :status, default: "pending", null: false,
               comment: "Processing status: pending, ready, error"
      t.string :supported_languages, default: [], null: false, array: true,
               comment: "Languages the character supports"
      t.string :tags, default: [], null: false, array: true, comment: "Searchable tags"
      t.integer :messages_count, default: 0, null: false, comment: "Counter cache for messages"
      t.string :visibility, null: false, default: "private",
               comment: "Visibility: private, unlisted, public"

      t.timestamps

      t.index :file_sha256
      t.index :name
      t.index :nsfw
      t.index :tags, using: :gin
      t.index :messages_count
      t.index :visibility

      t.check_constraint "jsonb_typeof(authors_note_settings) = 'object'::text",
                         name: :characters_authors_note_settings_object
      t.check_constraint "jsonb_typeof(data) = 'object'::text", name: :characters_data_object
    end

    create_table :lorebooks, comment: "World Info / Lorebook collections" do |t|
      t.references :user, foreign_key: { on_delete: :nullify }, comment: "Owner user"
      t.text :description, comment: "Human-readable description"
      t.datetime :locked_at, comment: "Lock timestamp for system lorebooks"
      t.string :name, null: false, comment: "Lorebook display name"
      t.boolean :recursive_scanning, default: false, null: false,
                comment: "Enable recursive entry scanning (ST-compatible)"
      t.integer :scan_depth, default: 2, comment: "Default scan depth for entries"
      t.jsonb :settings, default: {}, null: false, comment: "Additional lorebook-level settings"
      t.integer :token_budget, comment: "Max tokens for this lorebook's entries"
      t.string :visibility, null: false, default: "private",
               comment: "Visibility: private, unlisted, public"
      t.integer :entries_count, default: 0, null: false, comment: "Counter cache for entries"

      t.timestamps

      t.index :name
      t.index :visibility

      t.check_constraint "jsonb_typeof(settings) = 'object'::text", name: :lorebooks_settings_object
    end

    create_table :presets, comment: "LLM generation presets (sampling parameters)" do |t|
      t.references :user, foreign_key: true, comment: "Owner user"
      t.references :llm_provider, foreign_key: { on_delete: :nullify },
                   comment: "Default LLM provider for this preset"
      t.text :description, comment: "Human-readable description"
      t.jsonb :generation_settings, default: {}, null: false,
              comment: "LLM generation parameters (temperature, top_p, etc.)"
      t.datetime :locked_at, comment: "Lock timestamp for system presets"
      t.string :name, null: false, comment: "Preset display name"
      t.jsonb :preset_settings, default: {}, null: false,
              comment: "Non-generation settings (context size, etc.)"
      t.string :visibility, null: false, default: "private",
               comment: "Visibility: private, unlisted, public"

      t.timestamps

      t.index %i[user_id name], unique: true
      t.index :visibility

      t.check_constraint "jsonb_typeof(generation_settings) = 'object'::text",
                         name: :presets_generation_settings_object
      t.check_constraint "jsonb_typeof(preset_settings) = 'object'::text",
                         name: :presets_preset_settings_object
    end

    create_table :spaces, comment: "Chat spaces (STI: Spaces::Playground, Spaces::Discussion)" do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }, comment: "Space owner"
      t.boolean :allow_self_responses, default: false, null: false,
                comment: "Group chat: allow same character to respond consecutively (ST group_chat_self_responses)"
      t.integer :auto_mode_delay_ms, default: 5000, null: false,
                comment: "Delay between AI responses in auto mode (milliseconds)"
      t.string :card_handling_mode, default: "swap", null: false,
               comment: "How to handle new characters: swap, append, append_disabled"
      t.string :during_generation_user_input_policy, default: "reject", null: false,
               comment: "Policy when user sends message during AI generation: reject (lock input), restart (interrupt), queue (allow)"
      t.string :group_regenerate_mode, default: "single_message", null: false,
               comment: "Group regenerate behavior: single_message (swipe one), last_turn (redo all AI responses)"
      t.string :name, null: false, comment: "Space display name"
      t.jsonb :prompt_settings, default: {}, null: false,
              comment: "Prompt building settings (system prompt, context template, etc.)"
      t.boolean :relax_message_trim, default: false, null: false,
                comment: "Group chat: allow AI to generate dialogue for other characters"
      t.string :reply_order, default: "natural", null: false,
               comment: "Group reply order: natural (mention-based), list (position), pooled (random talkative), manual"
      t.integer :settings_version, default: 0, null: false,
                comment: "Optimistic locking version for settings"
      t.string :status, default: "active", null: false,
               comment: "Space status: active, archived, deleted"
      t.string :type, null: false, comment: "STI type: Spaces::Playground, Spaces::Discussion"
      t.integer :user_turn_debounce_ms, default: 0, null: false,
                comment: "Debounce time for merging rapid user messages (0 = no merge)"
      t.string :visibility, null: false, default: "private",
               comment: "Visibility: private, unlisted, public"

      t.timestamps

      t.index :visibility

      t.check_constraint "jsonb_typeof(prompt_settings) = 'object'::text",
                         name: :spaces_prompt_settings_object
    end

    # === Tables with multi-level dependencies ===

    create_table :character_assets, comment: "Character-associated files (icons, backgrounds)" do |t|
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.references :character, null: false, foreign_key: true
      t.string :content_sha256, comment: "SHA256 hash for deduplication"
      t.string :ext, comment: "File extension"
      t.string :kind, default: "icon", null: false, comment: "Asset type: icon, background, emotion"
      t.string :name, null: false, comment: "Asset name (unique per character)"

      t.timestamps

      t.index %i[character_id name], unique: true
      t.index :content_sha256
    end

    create_table :character_lorebooks, comment: "Join table: characters <-> lorebooks" do |t|
      t.references :character, null: false, foreign_key: { on_delete: :cascade }
      t.references :lorebook, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :enabled, default: true, null: false, comment: "Whether this lorebook is active"
      t.integer :priority, default: 0, null: false,
                comment: "Loading priority (higher = loaded first)"
      t.jsonb :settings, default: {}, null: false, comment: "Per-character lorebook overrides"
      t.string :source, default: "additional", null: false,
               comment: "Source type: primary (embedded in card), additional (user-added)"

      t.timestamps

      t.index %i[character_id lorebook_id], unique: true
      t.index %i[character_id priority]
      t.index :character_id, name: :index_character_lorebooks_one_primary_per_character, unique: true,
              where: "((source)::text = 'primary'::text)"

      t.check_constraint "jsonb_typeof(settings) = 'object'::text",
                         name: :character_lorebooks_settings_object
    end

    create_table :character_uploads, comment: "Pending character card upload queue" do |t|
      t.references :character, foreign_key: true, comment: "Created character (after processing)"
      t.references :user, null: false, foreign_key: true, comment: "Uploading user"
      t.string :content_type, comment: "MIME type of uploaded file"
      t.text :error_message, comment: "Processing error message"
      t.string :filename, comment: "Original filename"
      t.string :status, default: "pending", null: false,
               comment: "Processing status: pending, processing, completed, failed"

      t.timestamps
    end

    create_table :lorebook_entries, comment: "Individual World Info entries (ST/RisuAI compatible)" do |t|
      t.references :lorebook, null: false, foreign_key: { on_delete: :cascade }
      t.string :automation_id, comment: "ST automation script identifier"
      t.boolean :case_sensitive, comment: "Case-sensitive keyword matching"
      t.string :comment, comment: "Entry comment/label"
      t.boolean :constant, default: false, null: false,
                comment: "Always include in context (bypass keyword matching)"
      t.text :content, comment: "Entry content to inject into prompt"
      t.integer :cooldown, comment: "Minimum messages between activations"
      t.integer :delay, comment: "Messages before first activation"
      t.integer :delay_until_recursion, comment: "Delay before recursive scanning starts"
      t.integer :depth, default: 4, null: false,
                comment: "How many recent messages to scan for keywords"
      t.boolean :enabled, default: true, null: false, comment: "Whether entry is active"
      t.boolean :exclude_recursion, default: false, null: false,
                comment: "Exclude from recursive scanning"
      t.string :group, comment: "Grouping identifier for mutual exclusion"
      t.boolean :group_override, default: false, null: false,
                comment: "Override group scoring to always win"
      t.integer :group_weight, default: 100, null: false, comment: "Weight for group scoring"
      t.boolean :ignore_budget, default: false, null: false,
                comment: "Ignore token budget limits"
      t.integer :insertion_order, default: 100, null: false,
                comment: "Order within injection position"
      t.text :keys, default: [], null: false, array: true,
             comment: "Primary trigger keywords"
      t.boolean :match_character_depth_prompt, default: false, null: false,
                comment: "Also scan character depth prompt"
      t.boolean :match_character_description, default: false, null: false,
                comment: "Also scan character description"
      t.boolean :match_character_personality, default: false, null: false,
                comment: "Also scan character personality"
      t.boolean :match_creator_notes, default: false, null: false,
                comment: "Also scan creator notes"
      t.boolean :match_persona_description, default: false, null: false,
                comment: "Also scan user persona"
      t.boolean :match_scenario, default: false, null: false,
                comment: "Also scan scenario text"
      t.boolean :match_whole_words, comment: "Match whole words only"
      t.string :outlet, comment: "Named outlet for insertion"
      t.string :position, default: "after_char_defs", null: false,
               comment: "Injection position: before_char, after_char, after_char_defs, after_an, at_depth, etc."
      t.integer :position_index, default: 0, null: false,
                comment: "Index within position for ordering"
      t.boolean :prevent_recursion, default: false, null: false,
                comment: "Prevent this entry from triggering other entries"
      t.integer :probability, default: 100, null: false,
                comment: "Activation probability percentage (0-100)"
      t.string :role, default: "system", null: false,
               comment: "Message role for injection: system, user, assistant"
      t.integer :scan_depth, comment: "Override scan depth for this entry"
      t.text :secondary_keys, default: [], null: false, array: true,
             comment: "Secondary keywords (for selective logic)"
      t.boolean :selective, default: false, null: false,
                comment: "Enable secondary keyword matching"
      t.string :selective_logic, default: "and_any", null: false,
               comment: "Logic for combining keys: and_any, and_all, not_any, not_all"
      t.integer :sticky, comment: "Stick to context for N messages after trigger"
      t.string :triggers, default: [], null: false, array: true,
               comment: "CCv3 trigger macros/events"
      t.string :uid, null: false, comment: "Unique identifier within lorebook"
      t.boolean :use_group_scoring, comment: "Enable group scoring mode"
      t.boolean :use_probability, default: true, null: false,
                comment: "Enable probability-based activation"
      t.boolean :use_regex, default: false, null: false, comment: "Treat keys as regex patterns"

      t.timestamps

      t.index :enabled
      t.index %i[lorebook_id position_index]
      t.index %i[lorebook_id uid], unique: true
    end

    create_table :space_lorebooks, comment: "Join table: spaces <-> lorebooks" do |t|
      t.references :lorebook, null: false, foreign_key: { on_delete: :cascade }
      t.references :space, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :enabled, default: true, null: false, comment: "Whether lorebook is active"
      t.integer :priority, default: 0, null: false, comment: "Loading priority"
      t.string :source, default: "global", null: false,
               comment: "Source: global (space-wide), character (from character)"

      t.timestamps

      t.index %i[space_id lorebook_id], unique: true
      t.index %i[space_id priority]
    end

    create_table :space_memberships, comment: "Space participants (humans and AI characters)" do |t|
      t.references :character, foreign_key: { on_delete: :nullify },
                   comment: "Character for AI members (null for humans)"
      t.references :llm_provider, foreign_key: { on_delete: :nullify },
                   comment: "Override LLM provider for this member"
      t.references :preset, foreign_key: true, comment: "Override preset for this member"
      t.references :removed_by, foreign_key: { to_table: :users, on_delete: :nullify },
                   comment: "User who removed this member"
      t.references :space, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify },
                   comment: "User for human members (null for AI)"
      t.string :cached_display_name, comment: "Cached display name for performance"
      t.string :copilot_mode, default: "none", null: false,
               comment: "Copilot mode: none, suggestion, full (AI writes for user persona)"
      t.integer :copilot_remaining_steps,
                comment: "Remaining auto-responses in full copilot mode (null = disabled)"
      t.string :kind, default: "human", null: false, comment: "Member type: human, character"
      t.string :participation, default: "active", null: false,
               comment: "Participation status: active, muted (skipped in queue)"
      t.text :persona, comment: "User persona description for this space"
      t.integer :position, default: 0, null: false,
                comment: "Display order and list reply_order position"
      t.datetime :removed_at, comment: "Removal timestamp (soft delete)"
      t.string :removed_reason, comment: "Reason for removal"
      t.string :role, default: "member", null: false,
               comment: "Space role: owner, admin, member"
      t.jsonb :settings, default: {}, null: false, comment: "Per-member setting overrides"
      t.integer :settings_version, default: 0, null: false, comment: "Optimistic locking"
      t.string :status, default: "active", null: false,
               comment: "Status: active, removed"
      t.decimal :talkativeness_factor, precision: 3, scale: 2, default: "0.5", null: false,
                comment: "Pooled mode: probability weight for speaking (0.0-1.0)"
      t.datetime :unread_at, comment: "Timestamp when member last had unread messages"

      t.timestamps

      t.index :participation
      t.index %i[space_id character_id], unique: true, where: "(character_id IS NOT NULL)"
      t.index %i[space_id user_id], unique: true, where: "(user_id IS NOT NULL)"
      t.index :status

      t.check_constraint "jsonb_typeof(settings) = 'object'::text",
                         name: :space_memberships_settings_object
      t.check_constraint(
        "kind::text = 'character'::text AND user_id IS NULL AND " \
          "(character_id IS NOT NULL OR status::text = 'removed'::text) OR " \
          "kind::text = 'human'::text AND user_id IS NOT NULL",
        name: :space_memberships_kind_consistency
      )
    end

    # conversations has circular references (parent_conversation, root_conversation, forked_from_message)
    create_table :conversations, comment: "Chat conversation threads within a space" do |t|
      t.references :space, null: false, foreign_key: true
      t.references :parent_conversation, foreign_key: { to_table: :conversations },
                   comment: "Parent conversation for branches"
      t.references :root_conversation, foreign_key: { to_table: :conversations },
                   comment: "Root conversation of the tree"
      t.bigint :forked_from_message_id, comment: "Message where this branch forked from"
      t.text :authors_note, comment: "Author's note text for this conversation"
      t.integer :authors_note_depth, comment: "Injection depth for author's note"
      t.string :authors_note_position, comment: "Injection position for author's note"
      t.string :authors_note_role, comment: "Message role for author's note"
      t.integer :auto_mode_remaining_rounds,
                comment: "Remaining rounds in auto mode (null = disabled, >0 = active)"
      t.string :kind, default: "root", null: false,
               comment: "Conversation kind: root, branch"
      t.string :title, null: false, comment: "Conversation display title"
      t.jsonb :variables, default: {}, null: false,
              comment: "Chat variables for macro expansion (ST {{getvar}})"
      t.string :visibility, default: "shared", null: false,
               comment: "Visibility: private, shared, public"

      # === Scheduling state (TurnScheduler) ===
      t.string :status, null: false, default: "ready",
               comment: "Conversation status: ready, busy, error"
      t.string :scheduling_state, null: false, default: "idle",
               comment: "Scheduler state machine: idle, round_active, waiting_for_speaker, ai_generating, human_waiting, failed"
      t.uuid :current_round_id,
             comment: "UUID of the current ConversationRun (for state tracking)"
      t.bigint :current_speaker_id,
               comment: "FK to space_memberships - who is currently speaking"
      t.integer :round_position, default: 0, null: false,
                comment: "Current position in round_queue_ids (0-based)"
      t.bigint :round_queue_ids, array: true, default: [], null: false,
               comment: "Persisted speaker queue for current round (membership IDs in order)"
      t.bigint :round_spoken_ids, array: true, default: [], null: false,
               comment: "Members who have spoken in current round"
      t.integer :turns_count, default: 0, null: false,
                comment: "Total turns in this conversation"
      t.bigint :group_queue_revision, default: 0, null: false,
               comment: "Monotonic counter for queue updates (prevents stale broadcasts)"

      t.index :forked_from_message_id
      t.index :visibility
      t.index :scheduling_state

      t.timestamps

      t.check_constraint "jsonb_typeof(variables) = 'object'::text",
                         name: :conversations_variables_object
    end

    # Add check constraint for valid scheduling states
    execute <<~SQL
      ALTER TABLE conversations
      ADD CONSTRAINT valid_scheduling_state
      CHECK (scheduling_state IN ('idle', 'round_active', 'waiting_for_speaker', 'ai_generating', 'human_waiting', 'failed'))
    SQL

    # Add foreign key for current_speaker_id
    add_foreign_key :conversations, :space_memberships, column: :current_speaker_id, on_delete: :nullify

    create_table :conversation_lorebooks, comment: "Join table: conversations <-> lorebooks" do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.references :lorebook, null: false, foreign_key: { on_delete: :cascade }
      t.boolean :enabled, default: true, null: false, comment: "Whether lorebook is active"
      t.integer :priority, default: 0, null: false, comment: "Loading priority"

      t.timestamps

      t.index %i[conversation_id lorebook_id], name: :idx_on_conversation_id_lorebook_id_cb22900952, unique: true
      t.index %i[conversation_id priority]
    end

    create_table :conversation_runs, id: :uuid, default: -> { "gen_random_uuid()" },
                                     comment: "AI generation runtime units (state machine)" do |t|
      t.references :conversation, null: false, type: :bigint, foreign_key: true
      t.references :speaker_space_membership, foreign_key: { to_table: :space_memberships },
                   comment: "Member who is speaking for this run"
      t.datetime :cancel_requested_at,
                 comment: "Soft-cancel signal timestamp (for restart policy)"
      t.jsonb :debug, default: {}, null: false, comment: "Debug information (prompt stats, etc.)"
      t.jsonb :error, default: {}, null: false, comment: "Error details if run failed"
      t.datetime :finished_at, comment: "Completion timestamp"
      t.datetime :heartbeat_at, comment: "Last heartbeat for stale detection"
      t.string :kind, null: false,
               comment: "Run kind: auto_response, copilot_response, regenerate, force_talk, human_turn"
      t.string :reason, null: false,
               comment: "Human-readable reason (user_message, force_talk, copilot_start, etc.)"
      t.datetime :run_after, comment: "Scheduled execution time (for debounce/delay)"
      t.datetime :started_at, comment: "When run transitioned to running"
      t.string :status, null: false,
               comment: "State: queued, running, succeeded, failed, canceled, skipped"

      t.timestamps

      t.index %i[conversation_id status]
      t.index :kind
      t.index :status
      # Unique partial indexes enforce single-slot concurrency
      t.index :conversation_id, name: :index_conversation_runs_unique_queued_per_conversation, unique: true,
              where: "((status)::text = 'queued'::text)"
      t.index :conversation_id, name: :index_conversation_runs_unique_running_per_conversation, unique: true,
              where: "((status)::text = 'running'::text)"

      t.check_constraint "jsonb_typeof(debug) = 'object'::text", name: :conversation_runs_debug_object
      t.check_constraint "jsonb_typeof(error) = 'object'::text", name: :conversation_runs_error_object
    end

    # Add check constraint for valid run kinds
    execute <<~SQL
      ALTER TABLE conversation_runs
      ADD CONSTRAINT valid_run_kind
      CHECK (kind IN ('auto_response', 'copilot_response', 'regenerate', 'force_talk', 'human_turn'))
    SQL

    # messages has circular references (active_message_swipe, origin_message)
    create_table :messages, comment: "Chat messages in conversations" do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :conversation_run, type: :uuid, foreign_key: { on_delete: :nullify },
                   comment: "Run that generated this message"
      t.references :space_membership, null: false, foreign_key: true,
                   comment: "Member who sent/generated this message"
      t.references :text_content, foreign_key: true,
                   comment: "FK to text_contents for COW content storage"
      t.bigint :active_message_swipe_id, comment: "Currently active swipe variant"
      t.bigint :origin_message_id, comment: "Original message for forked/copied messages"
      t.text :content, comment: "Message text (or null if using text_content)"
      t.boolean :excluded_from_prompt, default: false, null: false,
                comment: "Exclude this message from LLM context"
      t.string :generation_status,
               comment: "AI generation status: generating, succeeded, failed, canceled"
      t.integer :message_swipes_count, default: 0, null: false,
                comment: "Counter cache for swipe variants"
      t.jsonb :metadata, default: {}, null: false,
              comment: "Additional metadata (token counts, etc.)"
      t.string :role, default: "user", null: false,
               comment: "Message role: user, assistant, system"
      t.bigint :seq, null: false,
               comment: "Sequence number within conversation (unique, gap-allowed)"

      t.timestamps

      t.index :active_message_swipe_id
      t.index %i[conversation_id created_at id]
      t.index %i[conversation_id seq], unique: true
      t.index :excluded_from_prompt, where: "(excluded_from_prompt = true)"
      t.index :generation_status
      t.index :origin_message_id

      t.check_constraint "jsonb_typeof(metadata) = 'object'::text", name: :messages_metadata_object
    end

    create_table :message_swipes, comment: "Alternative message versions (regenerate/swipe)" do |t|
      t.references :conversation_run, type: :uuid, foreign_key: { on_delete: :nullify },
                   comment: "Run that generated this swipe"
      t.references :message, null: false, foreign_key: { on_delete: :cascade }
      t.references :text_content, foreign_key: true,
                   comment: "FK to text_contents for COW storage"
      t.text :content, comment: "Swipe text (or null if using text_content)"
      t.jsonb :metadata, default: {}, null: false, comment: "Swipe metadata"
      t.integer :position, default: 0, null: false, comment: "Position in swipe list (0-based)"

      t.timestamps

      t.index %i[message_id position], unique: true

      t.check_constraint "jsonb_typeof(metadata) = 'object'::text", name: :message_swipes_metadata_object
    end

    create_table :message_attachments, comment: "Files attached to messages" do |t|
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.references :message, null: false, foreign_key: true
      t.string :kind, default: "file", null: false, comment: "Attachment type: file, image, audio"
      t.jsonb :metadata, default: {}, null: false, comment: "Attachment metadata"
      t.string :name, comment: "Display name for attachment"
      t.integer :position, default: 0, null: false, comment: "Display order"

      t.timestamps

      t.index %i[message_id blob_id], unique: true
    end

    # === Deferred foreign keys for circular references ===
    add_foreign_key :invite_codes, :users, column: :created_by_id, on_delete: :nullify
    add_foreign_key :users, :invite_codes, column: :invited_by_code_id, on_delete: :nullify
    add_foreign_key :conversations, :messages, column: :forked_from_message_id
    add_foreign_key :messages, :message_swipes, column: :active_message_swipe_id, on_delete: :nullify
    add_foreign_key :messages, :messages, column: :origin_message_id
  end
end
