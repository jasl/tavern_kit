# SillyTavern Divergences (Known Behavior Differences)

This document tracks known ways that TavernKit differs from SillyTavern (ST) behavior.
It exists to prevent future code reviews from "fixing" behavior by blindly re-applying ST semantics
when the difference is **intentional** or a **known limitation**.

If you find a new mismatch:
- If it is *unintentional*, treat it as a bug: add/adjust conformance tests and align behavior.
- If it is *intentional* (or unavoidable due to platform constraints), document it here and add a test
  that locks in the current behavior.

Related documents:
- [TAVERNKIT_BEHAVIOR.md](TAVERNKIT_BEHAVIOR.md) — TavernKit behavior specification
- [COMPATIBILITY_MATRIX.md](COMPATIBILITY_MATRIX.md) — Feature compatibility matrix

## Intentional incompatibilities

### Legacy angle-bracket macros (`<USER>` / `<BOT>` / `<CHAR>` / `<GROUP>` / `<CHARIFNOTGROUP>`)

ST historically supports legacy non-curly tokens like `<USER>` as aliases for the `{{...}}` macro system.

TavernKit intentionally does **not** implement these legacy `<...>` macros.
Use `{{user}}`, `{{char}}`, `{{group}}`, `{{charIfNotGroup}}`, etc.

### `data.extensions.fav` is not interpreted

ST uses `data.extensions.fav` as a UI favorite flag for filtering and sorting characters.

TavernKit **preserves** this field on import/export but does **not** interpret it. The field has no
effect on any TavernKit behavior.

Rationale: The favorite flag is pure UI metadata with no impact on prompt building or character
behavior. Host applications can implement their own favoriting system if needed.

### Character-linked lorebooks are name-based (soft links); additional links are exported as `extensions.extra_worlds`

**ST behavior**:
- **Primary**: `data.extensions.world` is a **string** that must match a World Info file name (exact match).
- **Additional**: stored in ST settings (`world_info.charLore[].extraBooks`) keyed by the character file name. This is local
  metadata and is not part of the character card export.

**TavernKit/Playground behavior**:
- **Primary**: uses `data.extensions.world` as the source of truth (same name-based soft link), resolved at runtime.
- **Additional**: uses `data.extensions.extra_worlds` (string array) as additional name-based links. These are exported with
  the character card (ST may ignore this field).
- **Cache**: uses `Rails.cache` to cache name → lorebook id (scoped by user context), and double-checks id validity
  (accessibility + name match) before using a cached id.
- **Indexing**: Playground extracts `world_name` and `extra_world_names` into `characters` table columns for searching and
  approximate “used by N characters” counts. The canonical source remains `data.extensions.*`.

### Legacy preset prompt fields (`main_prompt` / `nsfw_prompt` / `jailbreak_prompt`) are ignored

ST still accepts legacy prompt fields and migrates them into Prompt Manager entries on load.
TavernKit **does not** consume these legacy keys in `Preset.from_st_preset_json`.

Provide prompt text via `prompts[]` (Prompt Manager) instead.

### Legacy Claude text prompt converter is not supported

ST exposes a legacy Claude text prompt string converter (`:claude_prompt`) primarily for token counting
and older Claude integrations.

TavernKit does **not** provide the `:claude_prompt` dialect. Use `:text` or the Anthropic Messages
format instead.

### Preset-level Anthropic prefill toggles are not supported

ST presets can include `assistant_prefill`, `assistant_impersonation`, and `claude_use_sysprompt` settings
that affect provider-specific request shaping.

TavernKit ignores these preset fields. If you need those behaviors, pass dialect options directly to
`Plan#to_messages` / `TavernKit.build_messages`.

### Auto without human is conversation-level with round limits (not space-level unlimited)

**ST behavior**: AI-to-AI auto mode (`is_group_automode_enabled`) is a global toggle that enables unlimited
AI-to-AI exchanges. It can be disabled when the user starts typing (`onSendTextareaInput`).

**TavernKit/Playground behavior**: Auto without human is **conversation-level** with explicit **round limits** (1-10).
When Auto without human is started, it runs for a configurable number of rounds, then automatically stops.

This is intentional for a hosted application to:
- Prevent runaway token costs from unbounded AI conversations
- Provide explicit user control (start with N rounds vs toggle on/off)
- Remove the need for implicit "disable on typing" behavior

When Auto without human is started, the first AI response is triggered **immediately** - users don't need to
send a message first to start the AI-to-AI conversation.

| Aspect | SillyTavern | TavernKit |
|--------|-------------|-----------|
| Scope | Global setting (Space-level) | Per-conversation |
| Limits | Unlimited | 1-10 rounds (default: 4) |
| Stop trigger | User typing OR manual toggle | Rounds exhausted OR manual stop |
| Availability | Always | Group chats only |

The Auto without human toggle is accessible from the group chat toolbar, not from space settings.

### Unified turn-based scheduler (TurnScheduler)

**ST behavior**: SillyTavern uses separate logic paths for different auto-response scenarios:
- `autoModeWorker` for AI-to-AI auto mode
- Auto (user) logic embedded in various event handlers
- `getNextCharId()` and `getFallbackId()` for speaker selection
- Response planning triggered from various places (event handlers, timers, etc.)

**TavernKit/Playground behavior**: All turn management flows through a single `TurnScheduler` service with
**message-driven advancement** and a **command/query architecture**:

1. **Single queue for auto-respondable participants**: the round queue only includes AI characters and
   Auto users (human + persona). Regular humans are **triggers** (messages), not scheduled participants.

2. **Message-driven advancement**: Every message creation triggers `Message#after_create_commit`, which
   calls `TurnScheduler::Commands::AdvanceTurn`. This naturally handles both AI and human turns.

3. **ST/Risu-aligned human handling**: Auto without human and group scheduling are AI-only; there is no "human turn"
   concept in the scheduler. Human input starts/advances rounds via message triggers.

5. **Explicit persisted round state**: Scheduling state is stored in first-class round tables
   (`conversation_rounds`, `conversation_round_participants`) and runs reference rounds via
   `conversation_runs.conversation_round_id`. This makes it resilient to process restarts
   and keeps the scheduler debuggable without stuffing runtime state into `conversations`.

6. **Command/Query separation**: State mutations go through Command objects, queries through Query objects.

| Aspect | SillyTavern | TavernKit |
|--------|-------------|-----------|
| Scheduler | Multiple code paths | Single `TurnScheduler` |
| Turn advancement | Various triggers | Message `after_create_commit` |
| Turn order | Various strategies | Initiative-based (talkativeness) |
| Human handling | N/A (AI-to-AI is AI-only) | Same (AI-only queue; humans are triggers) |
| Auto + Auto without human | Separate handling | Unified queue (participant types unified; modes are UX-mutually-exclusive) |
| Queue state | In-memory | Explicit DB round tables |
| Run types | Multiple classes (STI) | `kind` enum (auto_response, auto_user_response, etc.) |

This is intentional to:
- Simplify the codebase (single source of truth, message-driven flow)
- Enable predictable behavior (deterministic turn order)
- Support mixed scenarios (auto-without-human + auto + human observation)
- Prevent "stuck conversation" bugs from conflicting schedulers
- Handle concurrent/distributed scenarios (queue state is persisted)

### User input always takes priority (cancels queued AI generations)

**ST behavior**: When a user starts typing during AI-to-AI auto mode, the `onSendTextareaInput` handler disables
AI-to-AI auto mode but does not cancel already-queued AI generations. This can lead to race conditions where
both user and AI messages appear simultaneously.

**TavernKit/Playground behavior**: User input is treated as authoritative:

1. **On typing (input event)**: Both Auto and Auto without human are immediately disabled via API calls.
   This prevents new AI generations from being queued.

2. **On submit**: All queued runs for the conversation are **canceled** before the user's message is
   created. This ensures the user's message is the definitive "next message" in the conversation.

This is intentional to:
- Prevent confusing duplicate messages (AI speaking as user + user's actual message)
- Give users clear priority over AI-generated content
- Avoid race conditions in concurrent AI generation scenarios

| Aspect | SillyTavern | TavernKit |
|--------|-------------|-----------|
| Typing disables modes | AI-to-AI only | Both Auto AND Auto without human |
| Cancel queued runs | No | Yes (on submit) |
| User message priority | Implicit (timing-dependent) | Explicit (queued runs canceled) |

### Input locking behavior (hard lock vs soft lock)

TavernKit distinguishes between **hard locks** and **soft locks** for input control:

**Hard locks** (user CANNOT type or send):
- `space_read_only`: Space is archived/inactive
- `generation_locked`: Reject policy enabled AND AI is currently generating (`scheduling_state = "ai_generating"`)

**Soft locks** (user CAN type to auto-disable the mode):
- `auto`: Auto is active (AI writing for user's persona)
- `auto_without_human`: Auto without human is active (AI-to-AI conversation)

When a soft lock is active:
1. The textarea remains enabled (but shows a different placeholder)
2. The Send button remains enabled
3. If the user starts typing, the mode is automatically disabled via API call
4. User can then send their message normally

This design follows ST's principle that user input always takes priority. The Vibe button is the only
UI element disabled during Auto (since manual suggestions aren't needed when AI is writing).

| Lock Type | Textarea | Send | Vibe | User Action |
|-----------|----------|------|------|-------------|
| Hard (Reject + AI Generating) | ❌ Disabled | ❌ Disabled | ❌ Disabled | Must wait |
| Soft (Auto ON) | ✅ Enabled | ✅ Enabled | ❌ Disabled | Type to disable Auto |
| Soft (Auto without human ON) | ✅ Enabled | ✅ Enabled | ✅ Enabled | Type to disable Auto without human |
| Normal | ✅ Enabled | ✅ Enabled | ✅ Enabled | - |

### Pooled `reply_order` stop condition (simplified pool management)

**ST behavior**: In pooled mode, after all characters have spoken once (pool exhausted), ST continues
selecting speakers randomly until the next user message. This can lead to unbounded AI-to-AI exchanges
if `auto_without_human` is enabled.

**TavernKit/Playground behavior**: Once all participating AI characters have spoken in the current epoch,
`TurnScheduler::Queries::NextSpeaker` returns `nil`, which stops Auto without human. This is intentional to:
- Control token costs in long-running sessions
- Provide predictable behavior (one round per user message)
- Avoid runaway AI conversations

The pool resets when a new user message arrives.

Additionally, TavernKit does not persist pool state — the "epoch" is implicitly defined by querying
messages since the last user message, making it stateless and easier to reason about in concurrent scenarios.

## Known limitations / partial compatibility

### Limited JavaScript RegExp syntax support (JS → Ruby conversion)

ST evaluates regex keys using JavaScript’s `RegExp` engine.
TavernKit supports **some** JS-regex usage (notably in World Info keys / prompt conditions) by
converting JS regex literals into Ruby `Regexp` objects using the `js_regex_to_ruby` gem (best-effort).

Consequences:
- Not all JS regex features/flags have Ruby equivalents (e.g., runtime flags like `g` / `y`, some Unicode-mode flags).
- Unicode property semantics and some edge cases (backreferences, engine quirks) may differ between JS and Ruby.
- When conversion fails, TavernKit falls back to treating the key as a plain string (or as non-matching, depending on the call site).

Recommendation: for maximum cross-engine parity, prefer simple patterns and avoid JS-engine-specific features.

### `{{pick}}` determinism is not ST-identical (Ruby `Random` vs `seedrandom`)

ST’s `{{pick::...}}` uses JavaScript hashing + the `seedrandom` RNG to select an item deterministically.

TavernKit implements `{{pick}}` as deterministic selection too, but uses Ruby stdlib primitives:
`Zlib.crc32` to derive a stable integer seed from `pick_seed`, input content, and macro offset, then Ruby’s built-in `Random`
to select the item.

Consequences:
- The selected item for the same prompt may differ from ST (and from other clients that implement `seedrandom`).
- The result may vary across Ruby versions/implementations if `Random`’s algorithm changes.

If you need byte-level parity with ST’s `{{pick}}`, this must be replaced with a `seedrandom`-compatible generator.

### `{{banned "..."}}` has no side effects (ST updates provider-specific ban lists)

ST’s `{{banned "word"}}` macro can update provider-specific banned word lists (notably for Text Generation Web UI).

TavernKit treats `{{banned "..."}}` as a **pure** macro: it is removed from the prompt and does not update any ban list.

## Feature gaps (not yet implemented)

### Handlebars-style conditional macros (`{{#if}}` / `{{#each}}`)

ST uses Handlebars.js for template processing, which supports conditional and loop constructs:
- `{{#if condition}}...{{/if}}`
- `{{#unless condition}}...{{/unless}}`
- `{{#each collection}}...{{/each}}`

TavernKit does **not** implement these Handlebars constructs. Only simple `{{macro}}` replacement is supported.

**Workaround**: Use multiple prompt entries with conditional triggers instead of inline conditionals.

### Weighted random selection (`{{random:weighted::...}}`)

ST supports weighted random selection with syntax like:
```
{{random:weighted::a=5,b=3,c=2}}
```

TavernKit's `{{random::...}}` macro only supports **equal-weight** selection across items.

**Status**: Planned for future implementation.

### Expression evaluation macros (`{{eval}}` / `{{calc}}`)

ST supports mathematical expression evaluation via `{{eval}}` and `{{calc}}` macros.

TavernKit does **not** implement these macros. Variable increment/decrement (`{{incvar}}`, `{{decvar}}`) are supported.

### Tool Calling / Function Calling

ST provides a complete Tool Calling system via `tool-calling.js`:
- `ToolManager.registerFunctionTool()` for registering tools
- `ToolDefinition` structure (name, description, parameters, action)
- Tool invocation and result injection into prompts
- Stealth tools (hidden from model)

TavernKit does **not** implement Tool Calling. This is planned for Phase 5+.

### STscript commands

ST provides a scripting language (STscript) with commands like:
- `/gen` — trigger generation
- `/inject` — register prompt injections
- `/setvar`, `/getvar` — variable operations
- `/if`, `/else` — flow control

TavernKit provides `InjectionRegistry` which covers the `/inject` use case conceptually, but does not
implement STscript parsing or other commands.

### Claude prompt caching (`cache_control`)

ST injects `cache_control` headers for Anthropic's prompt caching feature.

TavernKit does **not** implement Claude-specific prompt caching. The `:anthropic` dialect produces
standard Messages API payloads without cache control markers.

### OpenRouter-specific transforms

ST includes special handling for OpenRouter's API:
- Provider-specific header injection
- Model routing preferences
- Fallback handling

TavernKit's dialects produce standard payloads without OpenRouter-specific transforms.
Configure OpenRouter-specific options at the HTTP client level.

### Gemini thinking mode

ST supports Google Gemini's "thinking" mode with extended reasoning.

TavernKit's `:google` dialect produces standard Gemini API payloads without thinking mode configuration.

### Instruct Mode `activation_regex`

ST's Instruct Mode supports an `activation_regex` field that conditionally enables instruct mode
based on model name matching.

TavernKit does **not** implement `activation_regex`. Instruct mode is enabled/disabled explicitly.
