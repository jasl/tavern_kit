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
