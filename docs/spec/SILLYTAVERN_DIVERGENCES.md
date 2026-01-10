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

### Auto-mode is conversation-level with round limits (not space-level unlimited)

**ST behavior**: Auto-mode (`is_group_automode_enabled`) is a global toggle that enables unlimited
AI-to-AI exchanges. It can be disabled when the user starts typing (`onSendTextareaInput`).

**TavernKit/Playground behavior**: Auto-mode is **conversation-level** with explicit **round limits** (1-10).
When auto-mode is started, it runs for a configurable number of rounds, then automatically stops.

This is intentional for a hosted application to:
- Prevent runaway token costs from unbounded AI conversations
- Provide explicit user control (start with N rounds vs toggle on/off)
- Remove the need for implicit "disable on typing" behavior

When auto-mode is started, the first AI response is triggered **immediately** - users don't need to
send a message first to start the AI-to-AI conversation.

| Aspect | SillyTavern | TavernKit |
|--------|-------------|-----------|
| Scope | Global setting (Space-level) | Per-conversation |
| Limits | Unlimited | 1-10 rounds (default: 4) |
| Stop trigger | User typing OR manual toggle | Rounds exhausted OR manual stop |
| Availability | Always | Group chats only |

The auto-mode toggle is accessible from the group chat toolbar, not from space settings.

### Unified turn-based scheduler (ConversationScheduler)

**ST behavior**: SillyTavern uses separate logic paths for different auto-response scenarios:
- `autoModeWorker` for AI-to-AI auto-mode
- Copilot logic embedded in various event handlers
- `getNextCharId()` and `getFallbackId()` for speaker selection
- Response planning triggered from various places (event handlers, timers, etc.)

**TavernKit/Playground behavior**: All turn management flows through a single `ConversationScheduler` with
**message-driven advancement**:

1. **Single queue for ALL participants**: AI characters, Copilot users, AND regular human users are placed
   in one queue ordered by **initiative** (talkativeness factor, 0.0-1.0).

2. **Message-driven advancement**: Every message creation triggers `Message#after_create_commit`, which
   calls `scheduler.advance_turn!`. This naturally handles both AI and human turns.

3. **Natural human blocking**: When it's a human's turn (without Copilot), the scheduler simply waits for
   their message. No special handling needed — the next `after_create_commit` advances the turn.

4. **Auto mode human skip**: In auto mode, humans get a delayed skip job (`HumanTurnSkipJob`). If they
   don't respond within the timeout, their turn is skipped.

5. **Queue state persistence**: Turn queue state is stored in `conversation.turn_queue_state` (jsonb),
   making it resilient to process restarts and enabling debugging.

| Aspect | SillyTavern | TavernKit |
|--------|-------------|-----------|
| Scheduler | Multiple code paths | Single `ConversationScheduler` |
| Turn advancement | Various triggers | Message `after_create_commit` |
| Turn order | Various strategies | Initiative-based (talkativeness) |
| Human handling | N/A (auto-mode is AI-only) | In queue, skip timeout in auto mode |
| Copilot + Auto | Separate handling | Unified queue (all are participants) |
| Queue state | In-memory | Persisted in `turn_queue_state` |
| Run types | Multiple (auto_mode, copilot_*) | Single (`auto_turn`) with reason |

This is intentional to:
- Simplify the codebase (single source of truth, message-driven flow)
- Enable predictable behavior (deterministic turn order)
- Support mixed scenarios (auto-mode + copilot + human observation)
- Prevent "stuck conversation" bugs from conflicting schedulers
- Handle concurrent/distributed scenarios (queue state is persisted)

### User input always takes priority (cancels queued AI generations)

**ST behavior**: When a user starts typing during auto-mode, the `onSendTextareaInput` handler disables
auto-mode but does not cancel already-queued AI generations. This can lead to race conditions where
both user and AI messages appear simultaneously.

**TavernKit/Playground behavior**: User input is treated as authoritative:

1. **On typing (input event)**: Both Copilot mode and Auto mode are immediately disabled via API calls.
   This prevents new AI generations from being queued.

2. **On submit**: All queued runs for the conversation are **canceled** before the user's message is
   created. This ensures the user's message is the definitive "next message" in the conversation.

This is intentional to:
- Prevent confusing duplicate messages (AI speaking as user + user's actual message)
- Give users clear priority over AI-generated content
- Avoid race conditions in concurrent AI generation scenarios

| Aspect | SillyTavern | TavernKit |
|--------|-------------|-----------|
| Typing disables modes | Auto-mode only | Both Copilot AND Auto mode |
| Cancel queued runs | No | Yes (on submit) |
| User message priority | Implicit (timing-dependent) | Explicit (queued runs canceled) |

### Pooled `reply_order` stop condition (simplified pool management)

**ST behavior**: In pooled mode, after all characters have spoken once (pool exhausted), ST continues
selecting speakers randomly until the next user message. This can lead to unbounded AI-to-AI exchanges
if `auto_mode` is enabled.

**TavernKit/Playground behavior**: Once all participating AI characters have spoken in the current epoch,
`SpeakerSelector` returns `nil`, which stops auto-mode. This is intentional to:
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
