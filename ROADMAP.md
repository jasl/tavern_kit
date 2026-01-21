# TavernKit Roadmap

This document outlines the development phases for TavernKit, aligning with SillyTavern's core capabilities.

> **Goal**: Build a Ruby library that provides the same powerful prompt engineering features as SillyTavern — Prompt Manager, World Info, macros, Author's Note, etc. — with fine-grained control over context construction.

> **Philosophy**: TavernKit is a **prompt building library**, not an LLM framework. It focuses on constructing the perfect prompt and leaves LLM communication to downstream applications or dedicated libraries.

## Phase Overview

| Phase | Focus | Status |
|-------|-------|--------|
| Phase 0 | Foundation | ✅ Complete |
| Phase 1 | World Info & Character Book | ✅ Complete |
| Phase 1.5 | Prompt Manager & Context Trimming | ✅ Complete |
| Phase 1.6 | Character Card V2/V3 Schema Alignment | ✅ Complete |
| Phase 2 | Top-Level API & Developer Experience | ✅ Complete |
| Phase 3 | Advanced Prompt Control | ✅ Complete |
| Phase 4 | Extended Macros & Knowledge Integration | 🚧 Partial |
| Phase 5 | Ecosystem & Integrations | 🚧 Partial |
| Appendix | LLM Integration (Optional) | Future |

---

## Top-Level API Design

TavernKit should be easy to use out of the box. Inspired by libraries like `JWT`, `Nokogiri`, and `Faraday`.

### Current API

```ruby
# Load character (auto-detects V2/V3)
character = TavernKit::CharacterCard.load("path/to/card.png")  # or .json

# Build preset
preset = TavernKit::Preset.new(
  main_prompt: "...",
  # ... many options
)

# Build prompt
plan = TavernKit.build(
  character: character,
  user: TavernKit::User.new(name: "Alice"),
  preset: preset,
  message: "Hello!"
)

# Get messages for LLM
messages = plan.to_messages(dialect: :openai)
```

### Proposed Simplified API (Phase 2)

```ruby
# One-liner for simple cases
messages = TavernKit.build_messages(
        character: TavernKit.load_character("path/to/card.png"),
        user: "Alice",
        message: "Hello!",
)

# With options
messages = TavernKit.build_messages(
        character: TavernKit.load_character("path/to/card.png"),
        user: { name: "Alice", persona: "A friendly person" },
        message: "Hello!",
        history: [...],
        preset: { main_prompt: "...", prefer_char_prompt: true },
        lore_books: ["world.json"],
)

# Or use the DSL for complex scenarios
chat_history = TavernKit::ChatHistory.new(previous_messages)
lore = TavernKit::Lore::Book.load_file("world.json", source: :global)
plan = TavernKit.build do
  character TavernKit.load_character("path/to/card.png")
  user TavernKit::User.new(name: "Alice", persona: "...")
  preset TavernKit::Preset.new(main_prompt: "...")
  history chat_history
  lore_books [lore]
  message "Hello!"
end

messages = plan.to_messages(dialect: :openai)

# Convenience loaders at top level
card = TavernKit.load_character("path/to/card.png")
preset = TavernKit.load_preset("path/to/preset.json")
```

### Design Principles

1. **Progressive Disclosure** — Simple things simple, complex things possible
2. **Sensible Defaults** — Works out of the box with minimal configuration
3. **Chainable API** — Fluent interface for complex builds
4. **Format Agnostic Output** — `to_messages(dialect: :openai)`, `:anthropic`, `:text`

---

## Phase 0 — Foundation ✅

**Goal**: Minimal working prompt builder with Character Card V2 support.

### Completed Features

- [x] **Character Card V2 Parsing**
  - Parse JSON files with `spec: "chara_card_v2"`, `spec_version: "2.x"`
  - Support `name`, `description`, `personality`, `scenario`
  - Support `system_prompt`, `post_history_instructions` overrides
  - Preserve unknown fields in `raw` for forward compatibility
  - Ref: [Character Card V2 Spec](https://github.com/malfoyslastname/character-card-spec-v2)

- [x] **Basic Macro Expansion**
  - `{{char}}` — Character name
  - `{{user}}` — User name
  - `{{persona}}` — User persona description
  - `{{original}}` — Include preset's original prompt in overrides (one-shot; expands once then empty)
  - `{{description}}` — Character description
  - `{{scenario}}` — Character scenario
  - Case-insensitive matching
  - Pass-based evaluation order (ST-like; enables nested expansions such as `{{charPrompt}}` containing `{{char}}`)
  - Unknown macros kept as-is (configurable)
  - Ref: [ST Macros](https://docs.sillytavern.app/usage/core-concepts/macros/)

- [x] **Preset System**
  - `main_prompt` — Default system prompt (ST default: "Write {{char}}'s next reply... between {{charIfNotGroup}} and {{user}}.")
  - `post_history_instructions` — Instructions after chat history (stronger weight)
  - `prefer_char_prompt` — Use character's `system_prompt` when present
  - `prefer_char_instructions` — Use character's PHI when present
  - Ref: [ST Prompts](https://docs.sillytavern.app/usage/prompts/)

- [x] **Prompt Builder**
  - Assemble messages from Card + Preset + User + History
  - PHI placed after user message (ST behavior)
  - `{{original}}` composition for override fields (ST one-shot semantics)
  - Ref: [ST Character Design](https://docs.sillytavern.app/usage/core-concepts/characterdesign/)

- [x] **Output Formats**
  - `Prompt::Plan` with message array
  - `to_messages(dialect:)` for API consumption
  - `debug_dump` for human inspection

---

## Phase 1 — World Info & Character Book ✅

**Goal**: Implement ST's dynamic content injection system (Lorebook).

### World Info / Lorebook Engine

- [x] **Entry Structure** ✅
  - `keys` — Trigger keywords (comma-separated or array)
  - `secondary_keys` — AND logic with primary keys (selective mode)
  - `content` — Text to inject when triggered
  - `enabled` — On/off toggle
  - `constant` — Always active regardless of keywords
  - `position` — Injection position (before/after char defs, in-chat, etc.)
  - `priority` — For budget overflow decisions
  - `insertion_order` — Fine-grained ordering
  - Ref: [ST World Info](https://docs.sillytavern.app/usage/core-concepts/worldinfo/)

- [x] **Matching System** ✅
  - Scan Depth — How many recent messages to scan (0 = scan nothing, N = last N)
  - Case sensitivity option (global and per-entry)
  - Regex keys support (ST uses JS-style regex)
  - Match whole words option (global and per-entry)

- [x] **Recursive Scanning** ✅
  - Activated entries can trigger other entries
  - `Max Recursion Steps` limit (default: 3, hard max: 10)
  - Circular dependency prevention via `object_id` tracking
  - Scan buffer size limit (1MB) to prevent memory exhaustion

- [x] **Token Budget** ✅
  - Global budget for World Info
  - Priority-based selection when over budget
  - Token estimation via `TokenEstimator` (char/4 or tiktoken_ruby)

- [x] **Insertion Positions** ✅ (Full ST set)
  - `before_char_defs` — Before Character Definitions
  - `after_char_defs` — After Character Definitions
  - `before_example_messages` — Before Example Messages
  - `after_example_messages` — After Example Messages
  - `top_of_an` — Top of Author's Note
  - `bottom_of_an` — Bottom of Author's Note
  - `at_depth` — In-chat at depth N (with role support)
  - `outlet` — Named containers for `{{outlet::name}}` macro

- [x] **Character Book** ✅
  - Parse V2 `data.character_book` field
  - Automatic loading in prompt pipeline

- [x] **Outlets** ✅
  - Named containers for activated entries
  - `{{outlet::name}}` macro to insert outlet content
  - Case-sensitive outlet names
  - Content aggregation by `insertion_order`
  - Ref: [ST Macros - outlet](https://docs.sillytavern.app/usage/core-concepts/macros/)

- [x] **Example Message Parsing** ✅
  - Parse `mes_example` into real user/assistant blocks
  - `<START>` separator support
  - `{{user}}:`/`{{char}}:` prefix parsing
  - `new_example_chat` separator injection

- [x] **Optional Filter Logic** ✅
  - `selective` flag to enable secondary key filtering
  - `selective_logic` modes: AND ANY, AND ALL, NOT ANY, NOT ALL
  - Ref: [ST World Info - Optional Filter](https://docs.sillytavern.app/usage/core-concepts/worldinfo/)

- [x] **Multi-Book Merge & Insertion Strategies** ✅
  - Global + Character lorebooks merged as one evaluation
  - Source tracking (`:character` / `:global`)
  - Insertion strategies: sorted_evenly, character_lore_first, global_lore_first
  - Ref: [ST World Info - Character Lore Insertion Strategy](https://docs.sillytavern.app/usage/core-concepts/worldinfo/)

### Author's Note

- [x] **Basic Author's Note** ✅
  - Position: configurable via `Preset#authors_note`
  - `top_of_an` / `bottom_of_an` World Info injection
  - [x] Frequency: Insert every N user messages (`Preset#authors_note_frequency`) ✅
  - Ref: [ST Author's Note](https://docs.sillytavern.app/usage/core-concepts/authors-note/)

### Additional Macros ✅

- [x] `{{charPrompt}}` — Character's system_prompt field ✅
- [x] `{{charJailbreak}}` / `{{charInstruction}}` — Character's post_history_instructions field ✅
- [x] `{{mesExamples}}` — Formatted message examples ✅
- [x] `{{mesExamplesRaw}}` — Raw message examples ✅
- [x] `{{personality}}` — Character's personality field ✅
- [x] `{{newline}}` — Newline ✅
- [x] `{{trim}}` — Remove surrounding newlines ✅
- [x] `{{noop}}` — Empty string ✅
- [x] `{{reverse:...}}` — Reverse string ✅
- [x] `{{// ... }}` — Comment block removal ✅
- [x] `{{lastMessage}}` / `{{lastUserMessage}}` / `{{lastCharMessage}}` ✅
- [x] `{{lastMessageId}}` / `{{firstIncludedMessageId}}` / `{{firstDisplayedMessageId}}` ✅*
- [x] `{{idle_duration}}` ✅*
- [x] `{{banned "..."}}` — Remove macro content ✅
- [ ] `<USER>` / `<BOT>` / `<CHAR>` — Legacy aliases (intentionally not supported; use `{{user}}` / `{{char}}`)

\* Defaults can be overridden via `macro_vars` when host apps provide IDs/idle time/model.

### CLI (Verification UI)

- [x] `tavern_kit prompt --debug` — Dump final messages JSON with detailed debug info ✅
- [x] `tavern_kit validate-card` — Validate character card ✅
- [x] `tavern_kit lore test --text "..."` — Show which entries would trigger ✅

---

## Phase 1.5 — Prompt Manager & Context Trimming ✅

**Goal**: Implement ST's Prompt Manager and context budget management.

### Prompt Manager

- [x] **Prompt Entries** ✅
  - Ordered list of prompt entries (Preset#prompt_entries)
  - Pinned entries (built-in groups: main_prompt, chat_history, etc.)
  - Custom entries (user-defined content)
  - Ref: [ST Prompt Manager](https://docs.sillytavern.app/usage/prompts/prompt-manager/)

- [x] **Entry Positions** ✅
  - `:relative` — Position determined by drag-and-drop order in list
  - `:in_chat` — Injected into chat history at specified depth
  - Ref: [ST Prompt Manager - In-Chat](https://docs.sillytavern.app/usage/prompts/prompt-manager/)

- [x] **In-Chat Injection** ✅
  - Depth-based insertion into chat history (Depth 0 = after last message, Depth 1 = before last, etc.)
  - Order-based sorting within same depth
  - Role-based grouping (Assistant → User → System fixed order)
  - **Same role+depth+order merging**: Entries with same role, depth, and order are combined into single message
  - Depth clamping to history bounds

- [x] **Role Override** ✅
  - Per-entry role override for pinned groups
  - Supported for most groups except examples/history (multi-role)

- [x] **Entry Normalization (ST-Aligned)** ✅
  - `FORCE_RELATIVE`: `chat_history` and `chat_examples` always treated as relative (multi-block groups)
  - `FORCE_LAST`: `post_history_instructions` (PHI) always placed at end regardless of list position
  - Multi-block pinned groups flattened to single message when in-chat

- [x] **ST Preset JSON Loading** ✅
  - `Preset.from_st_preset_json` method for loading ST preset files
  - Supports `prompt_order` array for entry ordering and enabled state
  - Handles `injection_position`, `injection_depth`, `injection_order` fields
  - Normalizes ST identifier names to TavernKit IDs

### Token Budget & Context Trimming

- [x] **Token Estimation** ✅
  - TiktokenRuby as default (required dependency) for accurate OpenAI token counts
  - CharDiv4 available for testing environments only

- [x] **Context Window Settings** ✅
  - `context_window_tokens` — Total context size
  - `reserved_response_tokens` — Reserve for model output
  - `message_token_overhead` — Per-message overhead (default: 4)

- [x] **Trimmer (Eviction Strategy)** ✅
  - Priority: Examples → Lore → History
  - Examples trimmed block-by-block (earliest first)
  - Lore trimmed by priority (recursive/low-order first)
  - History truncated from oldest (keeps latest user message)
  - Detailed trim_report in Plan

- [x] **Examples Behavior** ✅
  - `:gradually_push_out` (alias: `:trim`) — Remove examples as needed
  - `:always_keep` — Never remove examples
  - `:disabled` — Remove all examples immediately

---

## Phase 1.6 — Character Card V2/V3 Schema Alignment ✅

**Goal**: Fix V2/V3 field positions to match official specs, add unified loader, prepare for V3-first architecture.

### Issues Fixed

- [x] **V2 Field Position Bug** ✅
  - `tags`, `creator`, `character_version`, `extensions` now correctly read from `data`
  - Added missing `creator` and `character_version` to `Data.define`
  - Ref: [Character Card V2 Spec](https://github.com/malfoyslastname/character-card-spec-v2)

- [x] **V3 Read/Write Asymmetry** ✅
  - `from_hash` and `to_h` now use consistent structure
  - `tags`, `creator`, `character_version`, `extensions` read from `data`
  - Handles "hybrid" ST exports gracefully (ST Issue #4412)

- [x] **Unified Loader** ✅
  - `CharacterCard.load_file(path)` — Auto-detect and load JSON
  - `CharacterCard.load_png(path)` — Extract from PNG/APNG
  - `CharacterCard.load_hash(hash)` — Parse hash with version detection
  - `CharacterCard.load(input)` — Smart loader (file path, hash, or JSON string)

- [x] **V2#to_h / V3#to_h** ✅
  - Spec-compliant serialization for round-trip testing
  - `extensions` preserved with all unknown keys (per spec requirement)

### Verified Alignment with Specs

| Field | V2 Spec Location | TavernKit V2 | TavernKit V3 |
|-------|------------------|--------------|--------------|
| `tags` | `data.tags` | ✅ `data` | ✅ `data` |
| `creator` | `data.creator` | ✅ `data` | ✅ `data` |
| `character_version` | `data.character_version` | ✅ `data` | ✅ `data` |
| `extensions` | `data.extensions` | ✅ `data` | ✅ `data` |

---

## Phase 2 — Top-Level API & Developer Experience ✅

**Goal**: Make TavernKit easy to use with simplified top-level API and improved developer experience.

**Status**: Complete — Top-level API (`TavernKit.build`, `TavernKit.to_messages`), PNG dual-write, greeting selection, output format adapters (8 dialects), V3-first architecture, and PromptBlock system are all implemented.

### Top-Level Module Methods

- [x] **`TavernKit.build_messages`** — One-liner prompt building ✅
- [x] **`TavernKit.load_character`** — Convenience character loader ✅
- [x] **`TavernKit.load_preset`** — Convenience preset loader ✅
- [x] **`TavernKit.build`** — DSL-based prompt building ✅

### V3-First Migration ✅

- [x] **Canonical Character Model**
  - `TavernKit::Character` as unified internal representation (V3 superset)
  - `CharacterCard.load(input)` auto-detects V2/V3 and returns `Character`
  - "Strict in, strict out" — require spec-compliant, emit spec-compliant

- [x] **Export Methods**
  - `CharacterCard.export_v2(character) → Hash`
  - `CharacterCard.export_v3(character) → Hash`
  - V3-only fields preserved in V2 extensions

- [x] **Builder Migration**
  - `TavernKit.build(character:)` accepts `Character` instance
  - Internal logic reads `character.data.*`
  - Clean V3-first architecture

### PNG Export (Dual-Write)

- [x] **Write PNG with V2+V3** ✅
  - Write `chara` tEXt chunk (V2, base64 JSON) for max compatibility
  - Write `ccv3` tEXt chunk (V3, base64 JSON) for modern clients
  - CLI flags: `--v2-only`, `--v3-only`, `--both` (default)
  - `CharacterCard.write_to_png(character, input_png:, output_png:, format:)`
  - `Png::Writer.embed_character` low-level API

### PromptBlock System

- [x] **Basic Block Structure** ✅ (Phase 1.5)
  - `role` — system/user/assistant
  - `content` — Text content (macros expanded)
  - `slot` — Block type identifier (e.g., `:main_prompt`, `:history`, `:world_info_at_depth`)

- [x] **Extended Block Structure** ✅
  - `id` — Auto-generated UUID unique identifier
  - `insertion_point` — Explicit insertion point enum (`:relative`, `:in_chat`, `:before_char_defs`, etc.)
  - `priority` — For budget eviction decisions (lower = keep longer)
  - `token_budget_group` — Grouped budget control (`:system`, `:examples`, `:lore`, `:history`, `:custom`, `:default`)
  - `enabled` — Toggle support with `Plan#enabled_blocks` filtering
  - `tags` — Array of symbols for hooks/filtering
  - `metadata` — Hash for extension data (replaces `meta`)

- [x] **PromptPlan as Block Collection** ✅
  - `Plan#blocks` — Ordered array of `Block` objects
  - Persona, description, scenario as separate blocks with distinct slots
  - Configurable ordering via `Preset#prompt_entries`

### Token Management

- [x] **Token Counting** ✅
  - `tiktoken_ruby` integration (required dependency)
  - CharDiv4 fallback for testing only

- [x] **Context Budget** ✅ (Partial — via Phase 1.5 Trimmer)
  - [x] Hard reserve: system prompt, PHI (Trimmer never evicts these)
  - [x] Soft reserve: recent chat history (`remove_old_history` keeps latest)
  - [ ] Compressible: older history → summary (requires Phase 4 Mid-term Memory)
  - [x] Droppable: low-priority World Info entries (`lore_eviction_order`)

### Message Examples

- [x] **Parse `mes_example` Field** ✅
  - `ExampleParser.parse_blocks` parses `<START>` separated dialogue
  - `{{user}}:`/`{{char}}:` prefix parsing
  - Integrated in `Builder#build_example_blocks`

- [x] **Format as Example Dialogue Blocks** ✅
  - Parsed into real user/assistant `Block` objects
  - `new_example_chat` separator injection supported

- [x] **Configurable Insertion Position** ✅
  - World Info `before_example_messages` / `after_example_messages` positions
  - Prompt Manager entry ordering

### First Message & Greetings

- [x] Parse `first_mes` field ✅ (V2/V3 data structure)
- [x] Parse `alternate_greetings` array ✅ (V2/V3 data structure)
- [x] Builder/CLI integration for greeting selection ✅
- [x] CLI flag to select greeting: `--greeting N` ✅

> **Design**: The greeting is returned as `Plan#greeting` and `Plan#greeting_index`, giving
> applications control over how to use it (prepend to history, display in UI, etc.).
> The Builder accepts `greeting: N` (0=first_mes, 1+=alternate_greetings) via constructor or fluent API.

### Output Format Adapters

- [x] **OpenAI Format** ✅ — `plan.to_messages(dialect: :openai)` (default)
- [x] **Anthropic Format** ✅ — `plan.to_messages(dialect: :anthropic)` (system message extraction, content blocks)
- [x] **Text Completion** ✅ — `plan.to_messages(dialect: :text)` for non-chat models

---

## Known Issues & ST Alignment Fixes

This section tracks discovered semantic differences with SillyTavern and their fixes.

### Fixed (Latest)

- [x] **Scan Buffer Composition** ✅
  - **Issue**: TavernKit only scanned `chat_history + current_user_message`
  - **ST Behavior**:
    - Base scan buffer comes from generation chat messages (optionally `name: message` format via `world_info_include_names`)
    - Per-entry `match_*` flags allow including character/persona fields in the scan buffer
    - Supported flags: `match_persona_description`, `match_character_description`, `match_character_personality`, `match_character_depth_prompt`, `match_scenario`, `match_creator_notes`
  - **Fix**:
    - Added 6 `match_*` flags to `Lore::Entry` with parsing from ST camelCase and snake_case formats
    - Added `scan_context:` parameter to `Lore::Engine#evaluate` for per-entry field matching
    - Added `world_info_include_names` to `Preset` for `name: message` scan buffer format
    - Added `name` attribute to `Prompt::Message` for speaker identification
    - Pipeline now builds `scan_context` and supports name-prefixed scan text
  - **Ref**: ST `public/script.js` (chatForWI/globalScanData) + `public/scripts/world-info.js` (`WorldInfoBuffer#get`, `checkWorldInfo`)

- [x] **Author's Note `frequency=0` semantic** ✅
  - **Issue**: TavernKit treated `frequency ≤ 0` as "always insert" (converted to 1)
  - **ST Behavior**: `frequency=0` means "never insert"
  - **Fix**: `Preset` now preserves `frequency=0` and clamps negative values to 0 ("never insert")
  - **Ref**: [ST Author's Note - Insertion Frequency](https://docs.sillytavern.app/usage/core-concepts/authors-note/)

- [x] **World Info `scan_depth=0` semantic** ✅
  - **Issue**: TavernKit treated `scan_depth ≤ 0` as "scan all messages"
  - **ST Behavior**: `scan_depth=0` means "only recursed entries and Author's Note are evaluated" (scan nothing from chat history)
  - **Fix**: Updated pipeline scan buffer construction to produce an empty scan buffer when depth ≤ 0
  - **Ref**: [ST World Info - Scan Depth](https://docs.sillytavern.app/usage/core-concepts/worldinfo/)

- [x] **World Info Whole-Word Matching & Per-Entry Scan Depth** ✅
  - **Issue**: Whole-word matching used Ruby `\\b` boundaries and scan depth was treated as a book-level setting only.
  - **ST Behavior**:
    - Whole-word matching uses non-word boundaries (JS `\\W`), allowing punctuation boundaries like `cat!`.
    - Entries can override scan depth individually via `entry.scanDepth` / `extensions.scan_depth`.
  - **Fix**:
    - Updated `Lore::Engine#key_matches?` to use ST-like non-word boundaries.
    - Added `Lore::Entry#scan_depth` parsing and per-entry depth selection in `Lore::Engine`.

- [x] **Prompt Manager In-Chat Ordering (Role + Order Groups)** ✅
  - **Issue**: In-chat prompts were merged too aggressively and role ordering differed.
  - **ST Behavior**:
    - Group by `injection_order` (higher orders appear later / closer to end).
    - Within an order group, roles are ordered `assistant → user → system`.
    - Prompts merge only within the same `(depth, order, role)` group.
  - **Fix**: Updated in-chat insertion in pipeline to match ST ordering and merge semantics.

- [x] **ST Built-in Macro Parity (Expanded Set)** ✅
  - Implemented: `{{newline}}`, `{{trim}}`, `{{noop}}`, `{{reverse:...}}`, `{{// ... }}`,
    `{{charIfNotGroup}}`, `{{group}}`, `{{groupNotMuted}}`, `{{notChar}}`,
    `{{charVersion}}`, `{{charDepthPrompt}}`, `{{creatorNotes}}`, `{{input}}`, `{{maxPrompt}}`,
    `{{date}}`, `{{time}}`, `{{weekday}}`, `{{isodate}}`, `{{isotime}}`, `{{datetimeformat ...}}`, `{{time_UTC±N}}`, `{{timeDiff::a::b}}`,
    `{{random::...}}`, `{{pick::...}}`, `{{roll:...}}`.
  - Not supported (intentional): legacy `<USER>/<BOT>/<CHAR>/<GROUP>/<CHARIFNOTGROUP>` (use `{{...}}` equivalents)

- [x] **Macro Value Sanitization Parity** ✅
  - **Issue**: TavernKit coerced macro results with Ruby `to_s`, producing non-JSON object strings.
  - **ST Behavior**: `sanitizeMacroValue` JSON-stringifies objects/arrays and emits ISO 8601 for Date/Time.
  - **Fix**: Added ST-style sanitization (nil → "", Hash/Array → JSON, Date/Time → ISO 8601 UTC).

- [x] **Preset Default Values Aligned with ST** ✅
  - **Issue**: Several `Preset` defaults differed from SillyTavern's actual defaults.
  - **ST Defaults** (verified from ST source):
    - `world_info_include_names`: `true` (was `false`)
    - `world_info_depth`: `2` (was not set)
    - `world_info_budget`: `25` (was not set)
    - `character_lore_insertion_strategy`: `character_first` (was `sorted_evenly`)
    - `DEFAULT_MAIN_PROMPT`: uses `{{charIfNotGroup}}` (was `{{char}}`)
  - **Fix**: Updated `Preset` defaults to match ST behavior.
  - **Ref**: ST `public/scripts/world-info.js`, `public/scripts/openai.js`

### Planned (P1)

- [x] **Generation Type Triggers** (World Info & Prompt Manager) ✅
  - `Lore::Entry` and `Prompt::PromptEntry` have `triggers` attribute
  - Controls activation based on generation type: `:normal`, `:continue`, `:impersonate`, `:swipe`, `:regenerate`, `:quiet`
  - Empty `triggers` array (default) = activates for ALL generation types
  - `triggered_by?(generation_type)` method on both Entry and PromptEntry
  - `Lore::Engine#evaluate` and `TavernKit.build` accept `generation_type:` parameter
  - CLI: `--generation-type TYPE` flag
  - **Ref**: [ST World Info - Triggers](https://docs.sillytavern.app/usage/core-concepts/worldinfo/)

- [x] **Group Chat Context for Macro Vars** ✅
  - Add a minimal group context object to prompt build inputs (members, muted, current_character)
  - Thread group context into macro variables so `{{group}}`, `{{groupNotMuted}}`, `{{charIfNotGroup}}`, `{{notChar}}` match ST behavior
  - **Ref**: `docs/spec/TAVERNKIT_BEHAVIOR.md` (Group chat context for group-aware macros)

---

## Phase 3 — Advanced Prompt Control ✅

**Goal**: Extended Prompt Manager features and programmatic injection.

**Status**: Complete — Conditional entries, marker prompts, forbid overrides, Author's Note parity controls, InjectionRegistry, and build-time hooks (before_build, after_build) are all implemented.

### Prompt Manager Extensions

- [x] **Ordered Prompt Entries** ✅ (Phase 1.5)
  - Named entries with enable/disable
  - Drag-and-drop style reordering (via prompt_entries order)
  - Ref: [ST Prompt Manager](https://docs.sillytavern.app/usage/prompts/prompt-manager/)

- [x] **Injection Positions** ✅ (Phase 1.5)
  - Before/After Character Definitions (via pinned groups)
  - Before/After Examples (via pinned groups)
  - In-Chat (with depth and role merging)
  - Post-History (always last)

- [x] **Conditional Entries** ✅
  - Enable based on chat content (keyword or JS-regex literal like `/dragon(s)?/i`)
  - Enable based on turn count (`min` / `max` / `equals` / `every`)
  - Enable based on character/user attributes (`tags_any` / `tags_all`, user persona, etc.)

- [x] **Marker Prompts & Forbid Overrides** ✅
  - Match ST marker prompts and forbid_overrides behavior

- [x] **Author's Note Parity Controls** ✅
  - Defaults aligned with ST source: `position=in_chat`, `depth=4`, `role=system`
  - Per-chat overrides via `authors_note: { position:, depth:, role: }` (Builder + top-level API)

### Programmatic Injection

- [x] **InjectionRegistry** ✅
  - `register(id:, content:, position:, **options)` / `remove(id:)`
  - Overlapping ID = replace
  - Positions: `before` / `after` / `chat` / `none`
  - Options: `depth`, `role`, `scan`, `filter`, `ephemeral`
  - `scan=true` injects are included in World Info scanning even when `position=none`
  - Ref: [STscript inject](https://docs.sillytavern.app/usage/st-script/)

- [x] **Hook System** ✅
  - **Build-Time Hooks** ✅ (no LLM required):
    - `before_build` — Modify inputs (card, user, history)
    - `after_build` — Modify plan (add/remove/reorder blocks)
    - Hooks receive `HookContext` object with full build state
    - Per-builder via `builder.before_build { |ctx| ... }` or shared via `HookRegistry`
  - **Runtime Hooks** (pending) → See [Appendix: LLM Adapter](#appendix-llm-adapter)
    - `before_call`, `after_call`, `on_tool_call` require LLM Adapter

---

## Phase 4 — Extended Macros & Memory 🚧

**Goal**: Rich macro system, conversation memory, and external knowledge injection.

**Status**: Partial — Extended macros (date/time, random/dice, variables) and custom macro registration are complete. Memory system and Knowledge Provider (RAG) are planned.

### Extended Macros

- [x] `{{date}}` — Current date
- [x] `{{time}}` — Current time
- [x] `{{weekday}}` — Day of week
- [x] `{{isodate}}` / `{{isotime}}` — ISO date/time
- [x] `{{datetimeformat ...}}` — Formatted date/time
- [x] `{{time_UTC±N}}` — Time with UTC offset
- [x] `{{timeDiff::a::b}}` — Humanized time difference
- [x] `{{random::a,b,c}}` — Random selection
- [x] `{{roll:d20}}` — Dice roll
- [x] `{{pick::a,b,c}}` — Deterministic pick (uses Ruby `Random`; differs from ST `seedrandom` — see `docs/spec/SILLYTAVERN_DIVERGENCES.md`; provide `pick_seed` for per-chat stability)
- [x] `{{banned "..."}}` — Remove macro content ✅
- [x] `{{idle_duration}}` — Time since last message (defaults to "just now" unless provided) ✅
- [x] `{{lastMessageId}}` / `{{firstIncludedMessageId}}` / `{{firstDisplayedMessageId}}` — Message ID macros ✅

### Macros 2.0 (Experimental Macro Engine parity)

SillyTavern v1.15.0 introduces a preview "Experimental Macro Engine" (Macros 2.0) with true nested macros and stable evaluation order.

- [ ] Add a parse-based macro engine option (in addition to the current legacy pass-based expander)
- [ ] Support nested macros inside arguments (e.g., `{{reverse::{{user}}}}`) and stable left-to-right evaluation
- [ ] Match MacroEngine-specific behaviors: preserve unknown macros but still resolve nested macros inside them; pre/post processing (rewrite `{{time_UTC±N}}`, rewrite `<USER>`-style markers, unescape `\{` / `\}`, post-process `{{trim}}`)
- [ ] Add MacroEngine-only utilities: `{{space}}` / `{{space::N}}` and `{{newline::N}}`
- [ ] Define and test `{{pick}}` semantics per engine (legacy offset-after-replacements vs MacroEngine stable offsets); document expected result changes

### Prompt Manager parity (ST 1.15+)

- [ ] Main prompt absolute position: when `main_prompt` is in-chat, preserve "relative-to-main" before/after inserts by converting them to in-chat injections adjacent to `main_prompt`
- [ ] Add conformance fixtures for `main_prompt` in-chat + before/after prompt inserts (Prompt Manager + InjectionRegistry)

### Custom Macro Registration

- [x] **MacroRegistry** ✅
  ```ruby
  TavernKit.macros.register("myvar") { |ctx, _inv| ctx.variables["myvar"] }
  ```
- [x] Proc-based lazy evaluation ✅
- [x] Context access (card, user, history, variables) ✅

### Memory System

- [x] **Short-term Memory** (Session history) — No LLM required ✅
  - [x] Message history storage (`ChatHistory::InMemory`)
  - [x] JSON persistence (`dump`/`load`, `dump_to_file`/`load_from_file`)

- [ ] **Swipe/Regenerate Version Tracking** — Future enhancement
  - Manage multiple response versions per message (add swipe, switch swipe)
  - Track regeneration history
  - Better suited for DB-backed `ChatHistory` implementations (e.g., Redis, SQLite)
  - Current `Message` already stores `swipes` and `swipe_id` fields

- [ ] **Mid-term Memory** (Summarization)
  - Trigger: every N messages or budget overflow
  - Output: summary block injected at configurable position
  - Ref: [ST Summarize](https://docs.sillytavern.app/extensions/summarize/)
  - ⚠️ **Requires LLM**: Use dependency injection (`summarizer:` lambda) or [Appendix: LLM Adapter](#appendix-llm-adapter)

- [ ] **Long-term Memory** (Vector retrieval)
  - `VectorStore` adapter interface
  - Inject retrieved facts as PromptBlock
  - Ref: [ST Smart Context](https://docs.sillytavern.app/extensions/smart-context/)
  - ⚠️ **Requires Embeddings**: Use dependency injection (`embedding_fn:` lambda) or [Appendix: LLM Adapter](#appendix-llm-adapter)

### Knowledge Provider (RAG)

TavernKit provides the interface; users implement the retrieval logic. No LLM required for the interface itself.

- [ ] **KnowledgeProvider Interface**
  ```ruby
  class MyKnowledgeProvider
    def retrieve(query:, messages:, k:, filters: {})
      # User implements: execute vector DB, search engine, etc.
      # Returns array of { content:, metadata: } hashes
    end
  end
  ```

- [ ] **Builder Integration**
  ```ruby
  TavernKit.build_messages(
    character: character,
    user: user,
    message: "...",
    knowledge_providers: [MyKnowledgeProvider.new],
  )
  ```

- [ ] Results injected as PromptBlocks at configurable position
- [ ] Ref: [ST Data Bank](https://docs.sillytavern.app/usage/core-concepts/data-bank/)

---

## Phase 5 — Ecosystem & Integrations 🚧

**Goal**: Production-ready library with full format support.

**Status**: Partial — Character Card V1 detection, PNG read/write, V3 support, chat/text completion formats, ST preset loading, and CLI tools are complete. Remaining: Rails integration, streaming support, ST backup import/export, Tool Calling.

### Tool Calling System

ST provides a complete Tool Calling / Function Calling system via `tool-calling.js`. This is planned for Phase 5+.

- [ ] **ToolManager** — Tool registration and management
  ```ruby
  TavernKit.tools.register(
    name: "get_weather",
    description: "Get weather for a location",
    parameters: { location: { type: "string", required: true } },
    action: ->(params) { WeatherAPI.get(params[:location]) }
  )
  ```

- [ ] **ToolDefinition Structure**
  - `name` — Unique tool identifier
  - `description` — Human-readable description for the model
  - `parameters` — JSON Schema-style parameter definitions
  - `action` — Ruby callable for tool execution

- [ ] **Tool Invocation Injection**
  - Inject tool definitions into prompt (provider-specific format)
  - Parse tool call responses from model output
  - Execute tool and inject results

- [ ] **Stealth Tools**
  - Tools hidden from model (for internal automation)
  - Ref: [ST Function Calling](https://docs.sillytavern.app/extensions/function-calling/)

### Character Card Formats

- [x] **Character Card V1** ✅ (Detection Only)
  - Auto-detect V1 format (fields: `name`, `description`, `personality`, `scenario`, `first_mes`, `mes_example` at top-level, no `spec` or `data` wrapper)
  - Raise `TavernKit::UnsupportedVersionError` with clear message
  - CLI shows user-friendly "Character Card V1 is not supported. Please convert to V2 or V3 format." message
  - **Note**: V1 → V2 conversion is out of scope; recommend external tools or manual migration

- [x] **PNG Embedded Cards** ✅ (Read)
  - Read character data from PNG `tEXt`/`zTXt`/`iTXt` chunks
  - Support `chara` (V2) and `ccv3` (V3) keywords
  - Base64 + JSON decoding
  - [x] Write character data to PNG ✅ (dual-write V2+V3)

- [x] **Character Card V3** ✅
  - Full V3 spec support (kwaroran spec)
  - `group_only_greetings`, `assets`, `nickname`, `source`, timestamps
  - Unified loader with auto-detection

- [ ] **CharX Import** (CCv3 ZIP archive) — Planned
  - Parse `card.json` from `.charx` and return card + avatar buffer + extracted asset buffers
  - Support JPEG-wrapped / SFX CharX by scanning for ZIP signature (`PK\x03\x04`)
  - Implement ST-aligned asset extraction heuristics:
    - Embedded URI prefixes: `embeded://`, `embedded://`, `__asset:`
    - Extension handling: derive from metadata or zip path; strip trailing ext from asset names; filter to known image extensions
    - Avatar selection: use embedded icon assets (`type=icon`, prefer `name=main`); ignore `icon`/`user_icon` for auxiliary assets
    - Naming: lowercase + collapse non-alphanumeric; use hyphens for sprite basenames; delete existing files with same basename before overwrite
    - Storage: sprites→`characters/{character_name}/`, backgrounds→`characters/{character_name}/backgrounds/`, misc→`user_images/{character_name}/` (use character name folder, not PNG basename)

### Output Formats

- [x] **Chat Completion** ✅
  - `Plan#to_messages` outputs `[{role:, content:}]` format
  - Ready for OpenAI API consumption

- [x] **Text Completion** ✅
  - `Plan#to_messages(dialect: :text)` outputs a single prompt string (role-prefixed)
  - [ ] Configurable separators/templates (Advanced Formatting parity)
  - Ref: [ST Advanced Formatting](https://docs.sillytavern.app/usage/core-concepts/advancedformatting/)

### Import/Export

- [x] **ST Preset JSON Loading** ✅
  - `Preset.from_st_preset_json(hash)` / `Preset.load_st_preset_file(path)`
  - Supports `prompts`, `prompt_order`, injection settings

- [ ] Import SillyTavern backup files
- [ ] Import SillyTavern chats (JSONL) including unified `chat_metadata` header (regular + group chats) and deprecated group.json `chat_metadata`/`past_metadata` migration handling
- [ ] Support legacy group definition metadata (`chat_metadata` / `past_metadata`) as deprecated fallback when importing old backups
- [ ] Export to SillyTavern format
- [ ] Preset file format (YAML)

### Integrations

- [x] **CLI Tool** ✅ (Partial)
  - `tavern_kit validate-card` — Validate character card
  - `tavern_kit extract-card` — Extract from PNG
  - `tavern_kit convert-card` — Convert V2↔V3
  - `tavern_kit prompt` — Build prompt with `--debug` support
  - `tavern_kit lore test` — Test World Info triggers
  - [x] `tavern_kit prompt --dialect (openai|anthropic|text)` — output dialect-specific format ✅

- [ ] **Rails Integration** — Service object examples
- [ ] **Streaming Support** — Chunk-based message iteration

---

## Appendix: LLM Adapter

> **Status**: Independent development track. May or may not be implemented.
>
> TavernKit is primarily a **prompt building library**. This appendix describes optional LLM integration that would be developed separately from the main prompt building features.

### Design Philosophy

TavernKit outputs `[{role:, content:}]` messages that can be sent to any LLM:

```ruby
# TavernKit builds the prompt
messages = TavernKit.build_messages(character: character, user: user, message: "Hello!")

# User sends to their preferred LLM client
client = OpenAI::Client.new
response = client.chat(parameters: { model: "gpt-4", messages: messages })
```

For features that require LLM calls (e.g., Phase 4 Memory), TavernKit supports **dependency injection** as the primary approach:

```ruby
# User provides the LLM execute implementation
summarizer = ->(text) { my_llm_client.summarize(text) }
embedding_fn = ->(text) { my_llm_client.embed(text) }
```

### LLM Adapter Interface

If implemented, would provide a thin abstraction for users who prefer an integrated solution:

- [ ] **Adapter Interface**
  ```ruby
  class TavernKit::LLM::Adapter
    def chat(messages:, model:, **params, &on_chunk)
      raise NotImplementedError
    end

    def complete(prompt:, model:, **params, &on_chunk)  # For Text Completion
      raise NotImplementedError
    end

    def embed(text:, model:)  # For Long-term Memory
      raise NotImplementedError
    end
  end
  ```

- [ ] **OpenAI-Compatible Adapter**
  - Works with OpenAI, local servers (LM Studio, Ollama /v1), proxies
  - Streaming support

- [ ] **Ollama Adapter** (optional)
  - Native Ollama API

### Runtime Hooks

Hooks that execute during LLM calls. Only available when using TavernKit LLM Adapter:

- [ ] `before_call` — Pre-LLM hook (modify messages before sending)
- [ ] `after_call` — Post-LLM hook (process response)
- [ ] `on_tool_call` — Tool/function call hook

> **Note**: Build-time hooks (`before_build`, `after_build`) are in Phase 3 and do not require LLM Adapter.

### Integration with Main Features

When LLM Adapter is available, it can be used with:

| Feature | Without Adapter | With Adapter |
|---------|-----------------|--------------|
| Mid-term Memory (Phase 4) | User provides `summarizer:` lambda | Adapter handles summarization |
| Long-term Memory (Phase 4) | User provides `embedding_fn:` lambda | Adapter handles embeddings |
| Runtime Hooks | Not available | `before_call`, `after_call`, `on_tool_call` |

### Example: Using Adapter with Memory

```ruby
# With LLM Adapter (if implemented)
adapter = TavernKit::LLM::OpenAIAdapter.new(api_key: ENV["OPENAI_API_KEY"])

plan = TavernKit.build_messages(
  character: character,
  user: user,
  message: "Hello!",
  llm_adapter: adapter,           # Enables integrated features
  summarize_after: 20,            # Mid-term memory
  vector_store: my_vector_store,  # Long-term memory
)

# Adapter-powered response
response = adapter.chat(messages: plan.to_messages, model: "gpt-4")
```

---

## ST Preset Import Parity Checklist

This section tracks critical gaps in importing SillyTavern preset JSON files without data loss.
Issues are prioritized by severity: **P0** = data loss/silent degradation, **P1** = feature gap, **P2** = nice to have.

### P0 — Critical (Data Loss / Silent Degradation) ✅

- [x] **P0-1: Nested `prompt_order` structure** ✅
  - ST exports `prompt_order: [{ character_id: 100000, order: [...] }]` in addition to flat arrays
  - **Fix**: `extract_prompt_order_entries` detects nested structure and extracts `order` array from matching `character_id` bucket (prefers 100000 as global)
  - **File**: `lib/tavern_kit/preset.rb`

- [x] **P0-2: `system_prompt=true` should not imply `pinned`** ✅
  - **Fix**: Only use `ST_PINNED_IDS.key?(id)` for pinned detection; unknown `system_prompt=true` entries are treated as custom prompts
  - **File**: `lib/tavern_kit/preset.rb` → `build_st_prompt_entry`

- [x] **P0-3: Read core text from `prompts[]` as fallback** ✅
  - Many ST presets store main prompt / jailbreak content inside `prompts[]` array
  - **Fix**: `build_prompts_by_id` lookup; if top-level field missing/empty, use content from `prompts[]`
  - **File**: `lib/tavern_kit/preset.rb` → `from_st_preset_json`

- [x] **P0-4: Numeric `injection_trigger` encoding** ✅
  - ST exports triggers as `[0, 1, 2]` (numeric codes) not `["normal", "continue"]`
  - **Fix**: Added `TRIGGER_CODE_MAP` and `TavernKit::Coerce.trigger_value` / `TavernKit::Coerce.triggers` for mixed format support
  - **Files**: `lib/tavern_kit/constants.rb`, `lib/tavern_kit/prompt/prompt_entry.rb`, `lib/tavern_kit/lore/entry.rb`

### P1 — Important (Feature Gaps)

- [x] **P1-1: Format Templates**
  - `wi_format` — World Info wrapper template (uses `{0}` placeholder)
  - `scenario_format` — Scenario wrapper template (uses `{{scenario}}`)
  - `personality_format` — Personality wrapper template (uses `{{personality}}`)
  - **Ref**: [ST Prompt Manager - Utility Prompts](https://docs.sillytavern.app/usage/prompts/prompt-manager/)

- [x] **P1-2: Utility Prompts**
  - `continue_nudge_prompt` — Appended for `:continue` generation type
  - `new_chat` / `new_group_chat` — Chat separators
  - `group_nudge_prompt` — Appended for group chats (skipped for `:impersonate`)
  - `replace_empty_message` — Replaces empty user input
  - **Note**: `new_example_chat` already exists

- [x] **P1-3: Fix `enhanceDefinitions` mapping**
  - Currently mapped to `authors_note` (wrong — they are distinct prompts)
  - **Fix**: Map to new `enhance_definitions` ID; implement as separate pinned group

- [x] **P1-4: Add `auxiliaryPrompt`**
  - Not in `ST_PINNED_IDS` or `default_prompt_entries`
  - **Fix**: Add mapping and include in default entries

- [x] **P1-5: Character's Note (Depth Prompt) injection**
  - ✅ `build_scan_context` correctly reads from `extensions["depth_prompt"]["prompt"]`
  - ❌ Not auto-injected as in-chat block at specified `depth` with specified `role`
  - **Fix**: Add injection logic in `build_in_chat_injections` using depth_prompt config

### P2 — Nice to Have

- [x] **P2-1: Unknown built-in ID fallback strategy** ✅
  - Added `pinned_group_resolver` hook on `Preset` (resolved during pipeline execution)
  - Unknown `pinned` prompts with content → treated as custom prompt (content preserved)
  - Unknown marker-only pinned prompts → emit warning (collected in `Prompt::Plan#warnings`, printed to stderr by default)

---

## RisuAI Integration Considerations

[RisuAI](https://github.com/kwaroran/RisuAI) is an alternative character card ecosystem built on CCv3.
As TavernKit aims to be a general-purpose prompt building library, we track potential RisuAI compatibility.

### RisuAI Unique Features

- **Lorebook Scripting** — Risu supports Lua/JS scripting in lorebook entries for dynamic content
- **Variable System** — Runtime variables (`{{var::name}}`, `{{setvar::...}}`) with state persistence
- **Conditional Blocks** — `{{#if}}` / `{{#each}}` template logic
- **Asset Management** — Referenced assets in character cards (images, audio)
- **Emotion Sprites** — Character expression system

### Integration Strategy

TavernKit should focus on **data format compatibility** rather than runtime scripting parity:

1. **Data Preservation** — Parse and preserve Risu-specific extensions in `Character.data.extensions`
2. **Script Passthrough** — Return script content as-is (let downstream apps handle execution)
3. **Template Expansion Points** — Expose hooks for custom macro handlers

### Potential API Extensions

```ruby
# Future: Custom macro registration for Risu/ST script systems
TavernKit.macros.register("var") do |ctx, args|
  ctx.variables[args.first] || ""
end

# Future: Hook for lorebook script execution
TavernKit.on_lore_entry_content do |entry, ctx|
  if entry.has_script?
    MyScriptEngine.evaluate(entry.script, ctx)
  else
    entry.content
  end
end
```

### Non-Goals

- **Script Execution** — TavernKit won't implement Lua/JS runtimes
- **UI Components** — Emotion sprites, asset rendering are frontend concerns
- **State Persistence** — Variable storage is application-level responsibility

---

## SillyTavern Parity Gaps (Tracked)

This section lists notable SillyTavern features that are **not yet fully implemented** in TavernKit
(or are only implemented partially) so they don't get lost.

### Macros (Not Exhaustive)

- [x] Date/time macros: `{{time}}`, `{{date}}`, `{{weekday}}`, `{{isotime}}`, `{{isodate}}`, `{{datetimeformat ...}}`, `{{timeDiff::...::...}}`
- [x] Random/pick macros: `{{random::...}}`, `{{pick::...}}` (weighted variants not yet implemented)
- [x] Dice roll macro: `{{roll:...}}`
- [x] Variable macros (ST): `{{setvar::...}}`, `{{getvar::...}}`, `{{addvar::...}}`, `{{incvar::...}}`, `{{decvar::...}}` (+ `*globalvar` variants)
  - Host-persisted via `TavernKit::ChatVariables` in `macro_vars[:local_store]` / `macro_vars[:global_store]`
  - TavernKit alias: `{{var::...}}`
- [x] `{{input}}` macro (current user input)
- [x] Swipe/regen and other UI session-state macros with real values (host apps can override via `macro_vars`; `{{lastSwipeId}}`/`{{currentSwipeId}}` derive from history message `swipes`/`swipe_id`)

**Not Implemented (Intentional):**

- [ ] `{{#if}}` / `{{#unless}}` / `{{#each}}` — Handlebars-style conditional/loop macros
  - ST uses Handlebars.js for template processing
  - TavernKit only supports simple `{{macro}}` replacement
  - Workaround: Use multiple prompt entries with conditional triggers

- [ ] `{{random:weighted::a=5,b=3}}` — Weighted random selection
  - Current `{{random::...}}` only supports equal-weight selection

- [ ] `{{eval}}` / `{{calc}}` — Mathematical expression evaluation
  - Variable increment/decrement macros are supported

### World Info (Lorebook)

- [x] Min activations scanning (`world_info_min_activations`, `world_info_min_activations_depth_max`) (`test/lore_engine_min_activations_test.rb`)
- [x] Timed effects: sticky / cooldown / delay (per entry; persisted via `ChatVariables` key `__tavern_kit__timed_world_info`) (`test/lore_engine_timed_effects_test.rb`)
- [x] Probability + group scoring/weights (entry groups) (`test/lore_engine_test.rb`)
- [x] Scan injection buffer support (include scannable injections in WI scan buffer) (`lib/tavern_kit/prompt/builder.rb`)
- [x] External/forced activations + automation IDs (via DSL `force_world_info`; `test/lore_engine_forced_activations_test.rb`)
- [x] `ignoreBudget` support and more ST export fields (`lib/tavern_kit/lore/entry.rb`, `lib/tavern_kit/lore/engine.rb`)
- [x] `@@activate` / `@@dont_activate` decorators (content modifiers that force/prevent activation)
- [x] `preventRecursion` — Prevents entry from being triggered during recursive scans
- [x] `delayUntilRecursion` — Entry only activates during recursive scan phase at specified recursion level

**Not Implemented:**

- [ ] **Vector Storage Matching** — Semantic/embedding-based entry activation
  - Requires embedding model integration
  - Alternative to keyword-based matching for semantic search
  - Ref: [ST World Info - Vector Storage](https://docs.sillytavern.app/usage/core-concepts/worldinfo/)

### Prompting / Prompt Manager

- [x] Squash system messages toggle (ST `squash_system_messages`)
- [x] Continue/prefill behaviors and provider-specific message shaping
- [x] Full ST extension prompt system parity (beyond current block/preset model)

Notes (implementation scope):
- `Preset` parses ST fields: `squash_system_messages`, `continue_prefill`, `continue_postfix`, `assistant_prefill`, `assistant_impersonation`, `claude_use_sysprompt`.
- `Prompt::Plan#to_messages(..., squash_system_messages: true)` implements ST-like squashing for OpenAI outputs (only squashes unnamed system messages; excludes chat separators).
- Pipeline supports continue-prefill vs continue-nudge branches.
- `Prompt::Dialects` mirrors ST `prompt-converters.js` for `:openai`, `:anthropic`, `:cohere`, `:google`, `:ai21`, `:mistral`, `:xai`, `:claude_prompt`, `:text`.
- Top-level `TavernKit.build_messages` auto-wires preset toggles (OpenAI squash, Anthropic sys/prefill) and preserves message `name` through history→blocks→output.

### Text Completion / Instruct Mode (Context Template)

- [x] Context Template / Story String prompt assembly (anchors + injection positions; ST "Context Template" UI)
  - `TavernKit::ContextTemplate` class with story_string, chat_start, example_separator, positions, roles
  - Handlebars-compatible story string rendering
  - Preset integration via `Preset#context_template`
- [x] Instruct-mode macro set (e.g., `{{chatStart}}`, `{{chatSeparator}}`, `{{systemPrompt}}`, and instruct prefix/suffix macros)
  - `TavernKit::Instruct` class with all ST instruct mode settings
  - Macros: `{{instructInput}}`, `{{instructOutput}}`, `{{instructSystem}}`, suffixes, first/last variants
  - `{{chatStart}}`, `{{chatSeparator}}`, `{{systemPrompt}}`, `{{globalSystemPrompt}}`
- [x] Stop sequences + wrap/include-names behaviors for text prompts (beyond `Prompt::Dialects` basic `:text` / `:claude_prompt`)
  - `:text` dialect returns `{prompt:, stop_sequences:}` hash
  - Instruct mode sequences auto-added to stop sequences
  - Names behavior: `:force`, `:remove`, `:default`

**Not Implemented (Instruct Mode):**

- [ ] `activation_regex` — Conditionally enable instruct mode based on model name regex
  - ST feature; TavernKit requires explicit enable/disable

### Provider-Specific Features

**Not Implemented:**

- [ ] Claude `cache_control` — Anthropic prompt caching header injection
- [ ] OpenRouter transforms — Provider-specific header injection and model routing
- [ ] Gemini thinking mode — Extended reasoning configuration

## SillyTavern Feature Mapping

For reference, here's how TavernKit concepts map to SillyTavern:

| SillyTavern | TavernKit | Phase |
|-------------|-----------|-------|
| Character Card V1 | Detection only → `UnsupportedVersionError` | 5 ✅ (Not Supported) |
| Character Card V2 | `Character` (via `CharacterCard.load`) | 0 ✅ |
| Character Card V3 | `Character` (via `CharacterCard.load`) | 2 ✅ |
| PNG Card Extract | `CharacterCard.load` | 1.6 ✅ |
| Macros (`{{char}}`, etc.) | `Macro::SillyTavernV1::Engine` | 0 ✅ |
| Variable macros (local/global) | `ChatVariables` + `Macro::SillyTavernV1::Engine` | 1 ✅ |
| `{{charPrompt}}` macro | `Macro::SillyTavernV1::Engine` | 1 ✅ |
| `{{charJailbreak}}` macro | `Macro::SillyTavernV1::Engine` | 1 ✅ |
| `{{mesExamples}}` macro | `Macro::SillyTavernV1::Engine` | 1 ✅ |
| Main Prompt | `Preset#main_prompt` | 0 ✅ |
| Post-History Instructions | `Preset#post_history_instructions` | 0 ✅ |
| Prefer Char. Prompt | `Preset#prefer_char_prompt` | 0 ✅ |
| World Info / Lorebook | `Lore::Engine` | 1 ✅ |
| Character Book | `Character#data.character_book` | 1 ✅ |
| Author's Note | `Preset#authors_note` | 1 ✅ |
| Prompt Manager | `Prompt::PromptEntry` + `Prompt::Pipeline` | 1.5 ✅ |
| In-Chat Injection | `Prompt::Middleware::Injection` | 1.5 ✅ |
| Context Trimming | `Prompt::Trimmer` | 1.5 ✅ |
| Context Template / Instruct Mode (Story String) | `TavernKit::Instruct` + `TavernKit::ContextTemplate` | 3 ✅ |
| Message Examples (`mes_example`) | `Prompt::ExampleParser` + `Builder` | 2 ✅ |
| First Message (`first_mes`) | `Character#data.first_mes` (parsed) | 2 ✅ (data only) |
| Alternate Greetings | `Character#data.alternate_greetings` (parsed) | 2 ✅ (data only) |
| Context Budget (basic) | `Prompt::Trimmer` eviction strategy | 2 ✅ (partial) |
| STscript /inject | `InjectionRegistry` | 3 |
| Build-time Hooks | `before_build`, `after_build` | 3 |
| Runtime Hooks | `before_call`, `after_call` | Appendix (requires LLM Adapter) |
| Tool Calling | `ToolManager` (planned) | 5+ |
| Data Bank (RAG) | `KnowledgeProvider` interface | 4 |
| Short-term Memory | `Memory::SessionStore` | 4 |
| Summarize | `Memory::Summarizer` | 4 (⚠️ requires LLM) |
| Smart Context | `Memory::VectorStore` | 4 (⚠️ requires Embeddings) |
| LLM Adapter | `TavernKit::LLM::Adapter` | Appendix |

---

## References

- [SillyTavern Documentation](https://docs.sillytavern.app/)
- [Character Card V2 Specification](https://github.com/malfoyslastname/character-card-spec-v2)
- [Character Card V3 Specification](https://github.com/kwaroran/character-card-spec-v3)
- [SillyTavern Source (AGPL)](https://github.com/SillyTavern/SillyTavern)

> **Note**: TavernKit is a clean-room Ruby implementation. We reference ST documentation for behavior alignment but do not copy ST code.
