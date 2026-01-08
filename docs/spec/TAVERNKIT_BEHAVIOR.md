# TavernKit Behavior Specification (ST Compatible)

## 0. Scope

This document defines **TavernKit's behavior specification** for prompt building, designed to be
compatible with SillyTavern's user-visible configuration model.

**Document positioning:**
- This is the authoritative specification for TavernKit's implementation behavior
- SillyTavern compatibility is a primary design goal, not a constraint
- Differences from SillyTavern are documented in [SILLYTAVERN_DIVERGENCES.md](SILLYTAVERN_DIVERGENCES.md)
- For SillyTavern's original behavior reference, see the ST source code

Covered (core):
- Prompt Manager concepts (ordered prompts, role, triggers, depth)
- Macros (replacement tags)
- Injection positions & depth semantics
- Author's Note behavior
- World Info (lorebook) scanning behavior (high-level)
- Data Bank (RAG) conceptual behavior and injection

Not covered:
- UI, storage layout, multi-user server behavior
- exact token counting implementations (model-dependent)

## 1. Two prompting modes

TavernKit supports both prompting styles (matching SillyTavern):

1) **Chat Completion style** — using Prompt Manager (messages with roles)
2) **Text Completion style** — using templates (Story String / Context Template)

Both modes produce a single internal "prompt plan" that can be output as:
- A list of role-tagged messages (for chat APIs), or
- A single string (for text completion APIs)

### 1.1 Provider-specific message shaping (prompt-converters parity)

TavernKit converts built `messages[]` into provider-specific request payloads via
`TavernKit::Prompt::Dialects.convert(messages, dialect:, **opts)`.

**Supported dialects:**

| Dialect | Description |
|---------|-------------|
| `:openai` | Standard Chat Completions array of `{role, content, name?}` |
| `:anthropic` | `{messages:, system:}` (Messages API; names moved into content) |
| `:cohere` | `{chat_history: ...}` |
| `:google` | `{contents:, system_instruction: ...}` (Gemini-style) |
| `:ai21` | System-squash + merge behavior |
| `:mistral` | Supports `prefix: true` on last assistant message (when enabled) |
| `:xai` | Name-prefix shaping for xAI style |
| `:text` | Plain text completion prompt (string) |

**Common options:**
- `names: { user_name:, char_name:, group_names: }` — best-effort name-prefix parity for example messages

**Additional hooks:**
- `Prompt::Plan#to_messages(dialect: :openai, squash_system_messages: true)` — ST-like system-message squashing toggle (only squashes **unnamed** system messages)

**Top-level convenience:**
- `TavernKit.build_messages(...)` auto-wires preset-driven toggles:
  - OpenAI: `squash_system_messages`
  - Anthropic: pass dialect options explicitly (e.g., `assistant_prefill`, `use_sys_prompt`)

### 1.2 Text Completion templates (Context Template / Instruct Mode)

TavernKit can render a single string prompt using Context Template / Story String setup,
optionally augmented by Instruct Mode sequences and related macros.

This includes:
- Context Template anchors / injection positions
- Instruct-mode macro set (e.g., `{{chatStart}}`, `{{chatSeparator}}`, `{{systemPrompt}}`)
- Stop sequence handling for text completion providers

**Implementation status:**
- Text prompts via `Prompt::Dialects` (`:text`) — **implemented**
- **Instruct Mode** via `TavernKit::Instruct` class — **implemented**
  - Input/output/system sequences and suffixes
  - First/last input/output variants
  - Story string prefix/suffix
  - Stop sequences (explicit + derived from sequences)
  - Wrap and names behavior (`:force`, `:remove`, `:default`)
- **Context Template** via `TavernKit::ContextTemplate` class — **implemented**
  - Story string template (Handlebars-compatible)
  - Chat start and example separator strings
  - Story string position, role, and depth
  - Stop strings configuration
- **Instruct-mode macros** — **implemented** (see section 4.2.2)
- **Stop sequences** — returned by `:text` dialect as part of the result hash

#### 1.2.1 Instruct Mode Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `enabled` | Enable instruct mode formatting | `false` |
| `preset` | Instruct preset name | `"Alpaca"` |
| `input_sequence` | Sequence before user messages | `"### Instruction:"` |
| `output_sequence` | Sequence before assistant messages | `"### Response:"` |
| `system_sequence` | Sequence before system messages | `""` |
| `input_suffix` | Suffix after user messages | `""` |
| `output_suffix` | Suffix after assistant messages | `""` |
| `system_suffix` | Suffix after system messages | `""` |
| `first_input_sequence` | Override for first user message | `""` |
| `first_output_sequence` | Override for first assistant message | `""` |
| `last_input_sequence` | Override for last user message | `""` |
| `last_output_sequence` | Override for last assistant message | `""` |
| `story_string_prefix` | Prefix for story string | `""` |
| `story_string_suffix` | Suffix for story string | `""` |
| `stop_sequence` | Explicit stop sequence string | `""` |
| `wrap` | Wrap messages with newlines | `true` |
| `names_behavior` | Name handling (`:force`, `:remove`, `:default`) | `:force` |
| `sequences_as_stop_strings` | Add sequences to stop strings | `true` |

#### 1.2.2 Context Template Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `preset` | Context preset name | `"Default"` |
| `story_string` | Handlebars template for story string | (see below) |
| `chat_start` | Chat start marker | `"***"` |
| `example_separator` | Example dialogue separator | `"***"` |
| `use_stop_strings` | Use stop strings from context | `true` |
| `names_as_stop_strings` | Add participant names as stop strings | `true` |
| `story_string_position` | Where to place story string (0=in_prompt, 1=in_chat, 2=before_prompt) | `0` |
| `story_string_role` | Role when in_chat (0=system, 1=user, 2=assistant) | `0` |
| `story_string_depth` | Depth when in_chat | `1` |

Default story string template:
```handlebars
{{#if system}}{{system}}
{{/if}}{{#if description}}{{description}}
{{/if}}{{#if personality}}{{char}}'s personality: {{personality}}
{{/if}}{{#if scenario}}Scenario: {{scenario}}
{{/if}}{{#if persona}}{{persona}}
{{/if}}
```

## 2. Prompt Items (Prompt Manager mental model)

A Prompt Plan consists of ordered Prompt Items.

Each Prompt Item has:
- `name` (for humans; not sent to model)
- `role` ∈ {system, user, assistant}
- `content` (text with macros)
- `triggers` (optional; if unset, applies to all generation types)
- optional placement controls:
  - static position in the plan
  - or "in-chat @ depth" insertion (see depth semantics)

### 2.1 Conditional Entries (TavernKit extension)

SillyTavern's Prompt Manager does **not** currently define a first-class "conditional prompt" model.
TavernKit adds an optional `conditions` field on Prompt Manager entries to enable dynamic activation.

#### 2.1.1 Supported condition families

Conditions are evaluated at build time (after generation-type trigger filtering), and are ANDed by default:

- `conditions.chat` — Enable based on recent chat content (keyword or JS-regex literal)
- `conditions.turns` — Enable based on user turn count
- `conditions.user` — Enable based on user attributes
- `conditions.character` — Enable based on character attributes

Advanced boolean grouping is supported via recursive groups:

- `conditions.all: [ ... ]` — all subconditions must pass
- `conditions.any: [ ... ]` — at least one subcondition must pass

#### 2.1.2 Chat scan buffer semantics

Chat conditions scan a bounded, newest-first buffer:

- Source: `(non-system history messages) + (current user_message)`
- Ordering: newest → oldest (depth counts from the end of the chat)
- Default depth: `Preset#world_info_depth` when set, otherwise **2** (ST default)
- `depth <= 0`: scan nothing (conditions will not match unless you override depth per entry)
- Safety cap: depth is clamped to 100 messages

#### 2.1.3 Pattern matching rules

Patterns in `conditions.chat.any` / `conditions.chat.all` support:

- JS regex literals like `/dragon(s)?/i` (parsed via `js_regex_to_ruby`)
- Plain keywords like `dragon`

Defaults:
- Case-insensitive matching
- Substring matching (unless `match_whole_words: true` is set)
- Whole-word mode uses ST-like non-word boundaries (`[^A-Za-z0-9_]`) so punctuation boundaries work (e.g. `cat!`)

#### 2.1.4 Turn count semantics

`turn_count` is defined as:
- `history.user_message_count + 1` (includes the current user input)

Supported `conditions.turns` keys:
- `min`, `max`, `equals`, `every`

#### 2.1.5 Attribute conditions

Supported keys:

- `conditions.user`: `name`, `persona`
- `conditions.character`: `name`, `creator`, `character_version`, `tags_any`, `tags_all`

Notes:
- `name` / `creator` / `character_version` use case-insensitive equality by default, or a JS regex literal.
- `persona` uses substring matching by default, or a JS regex literal.
- `tags_any`/`tags_all` match case-insensitively against `Character.data.tags`.

#### 2.1.6 Minimal examples

```ruby
# Enable only when the last 2 messages (+ current) mention "dragon"
{ id: "my_prompt", content: "...", conditions: { chat: { any: ["dragon"] } } }

# Enable only every 5th user turn
{ id: "my_prompt", content: "...", conditions: { turns: { every: 5 } } }

# Enable only when persona contains "wizard" AND character has tag "magic"
{
  id: "my_prompt",
  content: "...",
  conditions: {
    user: { persona: "wizard" },
    character: { tags_any: ["magic"] },
  },
}
```

### 2.2 Unknown pinned / marker IDs (forward compatibility)

SillyTavern Prompt Manager includes **built-in placeholders** ("marker prompts") such as
`charDescription`, `personaDescription`, etc. These are exported as prompts with:

- `system_prompt: true`
- `marker: true`
- `content: null` / missing

They are not "real" prompt text; they are **IDs** that get substituted later during prompt assembly.

#### 2.2.1 TavernKit behavior

TavernKit maps known built-in IDs to internal pinned groups (main prompt, persona, character defs, etc).
For **unknown** pinned/marker IDs (e.g., new ST versions introducing new placeholders), TavernKit uses:

- Unknown pinned prompt **with content** → treat as **custom prompt** (preserve content; do not drop).
- Unknown pinned prompt **without content** (marker-only) → emit a **warning** and ignore the entry.

Warnings are:
- collected into `Prompt::Plan#warnings`
- printed to stderr by default (prefix: `WARN:`), configurable via `warning_handler`.
- when `strict: true`, warnings raise `TavernKit::StrictModeError` instead of being collected/printed.
  - the raised error carries the warning payload via `StrictModeError#warnings`.

#### 2.2.2 Extensibility hook: `pinned_group_resolver`

To support future ST marker IDs without changing TavernKit, you can provide a resolver callable:

- preset-level: `Preset.new(pinned_group_resolver: ...)`
- DSL-level via pipeline middleware (takes precedence)

The resolver is called with keyword args including:
`id:`, `preset:`, `character:`, `user:`, `lore_result:`, `outlets:`, `history_messages:`, `user_message:`, `generation_type:`, `prompt_entry:`.

If it returns `Array<Prompt::Block>`, those blocks are used as the pinned group for that ID.

### 2.3 Hook System (build-time)

SillyTavern exposes multiple extension points around generation and prompt assembly.
TavernKit provides a Ruby-level equivalent for **prompt building**:

- `before_build` — run before prompt assembly (mutate inputs)
- `after_build` — run after prompt assembly (mutate plan), but **before trimming**

#### 2.3.1 API

DSL-level (recommended):

```ruby
plan = TavernKit.build do
  character my_character
  user my_user
  preset my_preset

  before_build do |ctx|
    ctx.user_message = ctx.user_message.to_s.strip
  end

  after_build do |ctx|
    ctx.plan.blocks.unshift(TavernKit::Prompt::Block.new(role: :system, content: "HOOKED"))
  end

  message "Hello"
end
```

Registry-level (share hooks across multiple builds):

```ruby
hooks = TavernKit::HookRegistry.new
hooks.before_build { |ctx| ctx.user_message = "overridden" }

plan = TavernKit.build do
  character my_character
  user my_user
  preset my_preset
  hook_registry hooks
  message "Hello"
end
```

#### 2.3.2 HookContext fields

Hooks receive a `TavernKit::HookContext` instance.

- Mutable inputs (for `before_build`):
  - `ctx.character`
  - `ctx.user`
  - `ctx.history`
  - `ctx.user_message`
- Read-only references:
  - `ctx.preset`
  - `ctx.generation_type`
  - `ctx.injection_registry`
  - `ctx.macro_vars`
  - `ctx.group`
- Plan access (for `after_build`):
  - `ctx.plan` (a `Prompt::Plan`; you may mutate `ctx.plan.blocks` or replace `ctx.plan`)

#### 2.3.3 Ordering and error behavior

- Hooks run in **registration order**.
- Hook errors are **not swallowed**; exceptions propagate to the caller.
- `after_build` runs before `Trimmer` is applied, so trimming (if enabled) will reflect hook changes.

## 3. Injection positions & depth semantics

Many features insert text at a configurable position:

- `before`: before the main prompt / story string
- `after`: after the main prompt / story string
- `chat`: inserted into the chat history at a configured depth

**Depth semantics (in-chat):**
- depth = 0 → insert at the very end of chat history (after the most recent message)
- depth = 1 → insert before the most recent message
- depth = 2 → insert before the 2 most recent messages
- etc.

**In-chat merge semantics (important):**
- Prompts are grouped by `injection_order` (higher order ends up closer to the end).
- Within the same `(depth, order, role)` group, prompts are merged into a single message.
- Extension prompts (Author's Note / World Info @ depth / memory injections) are appended to the same role message rather than emitted as separate messages.

This same "position + depth" pattern is used by:
- Author's Note
- Summaries / memory injections
- Scripted injections
- Data Bank / vectorization injections

### 3.1 Script injections (InjectionRegistry)

SillyTavern's STscript provides a `/inject` command for named injections.
TavernKit provides a similar capability via `TavernKit::InjectionRegistry`.

**Key fields:**
- `id` — unique injection id (overlapping id replaces)
- `position` — `before` / `after` / `chat` / `none`
- `depth` — in-chat depth (only meaningful for `position=chat`, default: 4)
- `role` — injection role (meaningful for `position=chat` and relative positions; default: system)
- `scan` — whether the injection content is included in World Info scanning
- `filter` — an optional closure that gates whether the injection is active
- `ephemeral` — remove injection after one generation

**Important scan rule:** injections marked `scan=true` are appended into the World Info scan buffer
even when `position=none` (hidden injects can be used only for triggering lore).

#### 3.1.1 TavernKit behavior

- **Access**: via DSL `injection` method or explicit `InjectionRegistry` instance
- **Storage/lifecycle**: per-build (caller controls how long it lives)
- **API**: `register(id:, content:, position:, **options)` and `remove(id:)`
- **ID overwrite**: same `id` replaces previous options/content
- **Placement**:
  - `position=:before` → inserted at the **start of the main prompt region** (BEFORE_PROMPT)
  - `position=:after` → inserted at the **end of the main prompt region** (IN_PROMPT; placed before chat history blocks)
  - `position=:chat` → inserted in-chat at `depth` and `role` (ST-like order-group 100)
  - `position=:none` → not emitted into the prompt
- **World Info scanning**:
  - `scan=true` injections are appended into the lore scan text (base chat slice → match_* context → injects → recursion)
  - This applies regardless of `position` (including `:none`)
- **Filter**: `filter` is a Ruby callable receiving a context hash; if it returns false or raises, the injection is skipped
- **Ephemeral**: `ephemeral=true` injections are removed from the registry after one `Builder#build` (best-effort parity for ST's post-generation removal)

## 4. Macros (replacement tags)

### 4.1 Core rules

- Macros are written like `{{user}}` and `{{char}}`.
- Macros are **case-insensitive** (e.g., `{{User}}` = `{{user}}` = `{{USER}}`).
- TavernKit supports **two** macro expanders:
  - `TavernKit::Macro::SillyTavernV2::Engine` (default): a parser-based expander inspired by ST's experimental "MacroEngine".
    - Supports *true* nesting inside macro arguments (e.g., `{{upper::{{user}}}}`).
    - Uses a stable, left-to-right evaluation order.
    - Preserves unknown macros while still expanding nested macros inside them (e.g., `{{unknown::{{user}}}}` → `{{unknown::Alice}}`).
    - Tolerates stray braces near macros (e.g., `{{{char}}}` → `{Character}`).
    - Treats unterminated macro openers as plain text, but still expands later valid macros.
  - `TavernKit::Macro::SillyTavernV1::Engine` (legacy, opt-in): a fixed, ordered sequence of regex replacements (pre-env → env vars → post-env), matching ST's legacy behavior.
    - This means macros can appear *inside other macro payloads* and still work when an earlier pass expands them first (e.g., `{{random::{{char}},x}}` works because `{{char}}` expands before `{{random}}`).
    - Truly nested/unbalanced braces that survive earlier passes are undefined.
- `{{original}}` is **one-shot**: it expands to the provided original text once, and subsequent occurrences expand to an empty string (prevents accidental duplication in overrides).
- Macro replacement happens during prompt build, after all prompt parts are chosen.

To select a specific engine, set it in the Prompt DSL (default is `:silly_tavern_v2`):

```ruby
plan = TavernKit.build do
  macro_engine :silly_tavern_v1   # or :silly_tavern_v2
end
```

### 4.2 Macro set

To be ST-compatible, TavernKit supports the following macros:

**Identity:**
- `{{user}}` → current persona name
- `{{char}}` → current character name
- `{{charIfNotGroup}}` → character name in single chats, group member list in group chats
- `{{group}}` → group member list (or character name if not in a group)
- `{{groupNotMuted}}` → group members excluding muted entries
- `{{notChar}}` → everyone except the current character (user + other group members)

**Character fields:**
- `{{description}}`
- `{{scenario}}`
- `{{personality}}`
- `{{persona}}` (persona description)
- `{{charVersion}}` / `{{char_version}}`
- `{{charDepthPrompt}}` (character depth prompt extension)
- `{{creatorNotes}}` (character creator notes)

**Examples:**
- `{{mesExamples}}` → normalized example blocks (ST `parseMesExamples`-style)
- `{{mesExamplesRaw}}` → raw `mes_example` field string

**Conversation state:**
- `{{lastMessage}}`
- `{{lastUserMessage}}`
- `{{lastCharMessage}}`
- `{{lastMessageId}}` → 0-based index of last message
- `{{firstIncludedMessageId}}` → first message included in context
- `{{firstDisplayedMessageId}}` → first message displayed in UI
- `{{lastSwipeId}}` / `{{currentSwipeId}}` → swipe indices
- `{{idle_duration}}` → humanized time since last user message

**System/context:**
- `{{input}}` → current user input
- `{{maxPrompt}}` → max context size (tokens)
- `{{model}}` → active model name
- `{{lastGenerationType}}` → last/current generation type
- `{{isMobile}}` → `"true"` / `"false"` depending on client environment

**Time/date:**
- `{{date}}`, `{{time}}`, `{{weekday}}`
- `{{isodate}}`, `{{isotime}}`
- `{{datetimeformat ...}}` → format with moment-style tokens
- `{{time_UTC±N}}` → time with UTC offset
- `{{timeDiff::a::b}}` → humanized time difference

**Randomization / dice:**
- `{{random::a,b,c}}` → random pick (entropy-based)
- `{{pick::a,b,c}}` → deterministic pick (seeded by chat id hash + content + offset)
- `{{roll:dN}}` / `{{roll:NdM+K}}` → dice roll

**Variables:**
- `{{setvar::name::value}}` → sets chat-local variable, returns empty string
- `{{getvar::name}}` → returns variable value
- `{{addvar::name::value}}` → numeric add or string concat
- `{{incvar::name}}` / `{{decvar::name}}` → ±1, returns updated value

**Global variables:**
- `{{setglobalvar::name::value}}` / `{{getglobalvar::name}}`
- `{{addglobalvar::name::value}}` / `{{incglobalvar::name}}` / `{{decglobalvar::name}}`

**TavernKit extension:**
- `{{var::name}}` — alias for `{{getvar::name}}`
- `{{var::name::index}}` — JSON/object indexing

**Variable storage:** Application-owned via `TavernKit::ChatVariables`:
```ruby
macro_vars: {
  local_store: TavernKit::ChatVariables.new,
  global_store: TavernKit::ChatVariables.new
}
```

**Utilities:**
- `{{newline}}` → newline
- `{{trim}}` → removes itself and surrounding newlines
- `{{noop}}` → empty string
- `{{banned "word"}}` → removes the macro and registers the word as banned
- `{{reverse:...}}` → reverse the provided string
- `{{// ... }}` → comment block removed from the final prompt

#### 4.2.2 Instruct-mode macros

TavernKit implements ST's instruct-mode macros (requires `Instruct` settings on `Preset`):

**Instruct sequences:**
- `{{instructInput}}` / `{{instructUserPrefix}}` → Instruct input sequence
- `{{instructOutput}}` / `{{instructAssistantPrefix}}` → Instruct output sequence
- `{{instructSystem}}` → Instruct system sequence
- `{{instructInputSuffix}}` → Instruct input suffix
- `{{instructOutputSuffix}}` → Instruct output suffix
- `{{instructSystemSuffix}}` → Instruct system suffix

**Instruct sequence variants:**
- `{{instructFirstInput}}` → First input sequence (falls back to input_sequence)
- `{{instructFirstOutput}}` → First output sequence (falls back to output_sequence)
- `{{instructLastInput}}` → Last input sequence (falls back to input_sequence)
- `{{instructLastOutput}}` → Last output sequence (falls back to output_sequence)

**Story string:**
- `{{instructStoryStringPrefix}}` → Story string prefix
- `{{instructStoryStringSuffix}}` → Story string suffix

**Context template:**
- `{{chatStart}}` → Chat start marker from Context Template
- `{{chatSeparator}}` → Example separator from Context Template

**System prompt:**
- `{{systemPrompt}}` → System prompt (prefers character override if `prefer_char_prompt` is enabled)
- `{{globalSystemPrompt}}` → Always returns preset's main_prompt (ignores character override)

#### 4.2.3 Legacy (angle-bracket) macros

SillyTavern historically supports legacy tokens like `<USER>`, `<BOT>`, `<CHAR>`, `<GROUP>`, and `<CHARIFNOTGROUP>`.

TavernKit currently does **not** implement these legacy `<...>` macros. Migration mapping:
- `<USER>` → `{{user}}`
- `<BOT>` / `<CHAR>` → `{{char}}`
- `<GROUP>` → `{{group}}`
- `<CHARIFNOTGROUP>` → `{{charIfNotGroup}}`

### 4.2.4 Custom macro registration (TavernKit extension)

TavernKit provides custom macro registration:

```ruby
# Register a lazy macro (evaluated only when encountered)
TavernKit.macros.register("myvar") { |ctx, _inv| ctx.variables["myvar"] }

# Parameterized macros can accept a second argument: a call-site Invocation object
TavernKit.macros.register("date") { |_ctx, inv| inv.now.strftime("%Y-%m-%d") }

# Unregister
TavernKit.macros.unregister("myvar")
```

#### MacroContext

Custom macro blocks receive a `TavernKit::MacroContext` with:
- `ctx.card` — current `TavernKit::Character`
- `ctx.user` — current `TavernKit::User`
- `ctx.history` — `TavernKit::ChatHistory::Base` for the current build
- `ctx.local_store` — `TavernKit::ChatVariables::Base` variable store
- `ctx.preset` — current `TavernKit::Preset` (when available)
- `ctx.group` — normalized group context (when provided to the Builder)
- `ctx.input` — current user input string

#### Invocation (parameterized macros)

Macro handlers are called with `(ctx, invocation)`; ignore `invocation` if unused.
It carries parsed macro arguments and helpers for ST parity.

#### Macro value sanitization

Macro return values follow ST's `sanitizeMacroValue` behavior:
- `nil` → empty string
- `String` → unchanged
- `Time` / `DateTime` / `Date` → ISO 8601 UTC
- `Hash` / `Array` → JSON
- other types → `to_s`

#### Preprocessing pipeline

Some ST directives need *regex-level context* and are applied as dedicated passes:
- `{{trim}}` runs in the **pre-env** phase
- `{{// ... }}` comment blocks are removed in the **post-env** phase

TavernKit also exposes an optional preprocessing pipeline for host-defined rewrites.

#### Precedence

When multiple sources define the same macro name, TavernKit resolves in this order:
1. internal overrides (builder-controlled)
2. builder `macro_vars`
3. global `TavernKit.macros`
4. built-in macro packs (default: `TavernKit::Macro::Packs::SillyTavern`)

### 4.3 Group chat context for group-aware macros

Group chat state is **session data**, not part of CCv2/CCv3. TavernKit represents this as
`TavernKit::GroupContext` (passed to `TavernKit.build` via `group:`).

**Minimal group context:**
- ordered `members[]` list (group character display names)
- per-member `muted` flag (or a `muted_members[]` list)
- `current_character` (the active character for this turn)

**Macro resolution with group context:**
- `{{group}}` → joined list of all group members
- `{{groupNotMuted}}` → joined list excluding muted members
- `{{charIfNotGroup}}` → same as `{{group}}`
- `{{notChar}}` → user name + group members excluding `current_character`

**Fallback (no group context):**
- `{{group}}` / `{{groupNotMuted}}` / `{{charIfNotGroup}}` → `{{char}}`
- `{{notChar}}` → `{{user}}`

**Formatting:** ST joins group member names with `", "`.

## 5. Main Prompt & Post-History Instructions

SillyTavern treats the "Main Prompt / System Prompt" as the top-level instruction
that frames the whole chat, and "Post-History Instructions" as guidance appended near the end.

Both can contain macros.

## 6. Character-level prompt overrides

SillyTavern supports per-character overrides:
- "Main Prompt override"
- "Post-History Instructions override"
- Prompt-entry `forbid_overrides` to disable character overrides for a given prompt

Key behavior:
- `{{original}}` inside the override splices the global default prompt in-place.

TavernKit supports:
- global defaults
- per-character overrides
- `{{original}}` placeholder (string replacement) when overrides are active

## 7. Prompt formats & utility prompts

SillyTavern presets include additional prompt templates and utility separators.

**Format templates:**
- `wi_format` — wrapper for World Info **before/after** strings (uses `{0}` placeholder)
- `scenario_format` — wrapper for scenario (uses `{{scenario}}`)
- `personality_format` — wrapper for personality (uses `{{personality}}`)

**Utility prompts / separators:**
- `new_chat_prompt` — inserted at the **start** of chat history
- `new_group_chat_prompt` — same as above for group chats
- `new_example_chat` (ST: `new_example_chat_prompt`) — inserted before each example dialogue block
- `group_nudge_prompt` — appended at the **end** of chat history for group chats
- `continue_nudge_prompt` — used for **continue** generation (when `continue_prefill=false`)
- `continue_prefill` — when enabled, continue generation uses assistant prefill instead
- `continue_postfix` — postfix string appended to continued assistant prefill
- `replace_empty_message` / `send_if_empty` — insert user message if last chat message is empty assistant reply

**Default utility prompt values (ST parity):**
- `new_chat_prompt` — `[Start a new Chat]`
- `new_group_chat_prompt` — `[Start a new group chat. Group members: {{group}}]`
- `new_example_chat` — `[Example Chat]`
- `group_nudge_prompt` — `[Write the next reply only as {{char}}.]`
- `continue_nudge_prompt` — `[Continue your last message without repeating its original content.]`

All of the above can be set to blank to disable the corresponding injection.

**Prompt post-processing:**
- `squash_system_messages` — OpenAI-style: squashes consecutive unnamed system messages into one

**Prompt Manager additions:**
- `enhanceDefinitions` is a **separate** built-in prompt (not Author's Note)
- `nsfw` / `auxiliaryPrompt` is the **Auxiliary Prompt** entry

**Character Depth Prompt:**
- `extensions.depth_prompt` defines `{ prompt, depth, role }`
- If `prompt` is non-empty, injected **in-chat** at `depth` with `role`
- Defaults: `depth=4`, `role=system`

## 8. Author's Note behavior

Author's Note is an optional injection with:
- placement mode:
  - static: "after scenario" (near character definition area), OR
  - dynamic: "in-chat @ depth"
- frequency:
  - **0 = NEVER insert** (Author's Note is disabled)
  - **1 = insert every user turn** (always insert)
  - **N > 1 = insert every Nth user turn**

### 8.1 Per-chat settings & defaults

SillyTavern stores Author's Note settings as **per-chat metadata**:

- `note_prompt` — Author's Note text
- `note_interval` — insertion frequency (0 disables)
- `note_position` — insertion position (numeric enum)
- `note_depth` — in-chat depth
- `note_role` — role to inject as

**Defaults:**
- `note_position`: **IN_CHAT (1)**
- `note_depth`: **4**
- `note_role`: **SYSTEM**
- `note_interval`: **1**

**Position encoding:**
- `0 = IN_PROMPT` — end of `main` prompt collection
- `1 = IN_CHAT` — in chat history at `note_depth`
- `2 = BEFORE_PROMPT` — start of `main` prompt collection

**TavernKit implementation:**
- Frequency semantics match ST exactly
- Negative frequency values normalized to 0
- Exposed via:
  - preset-level defaults: `Preset#authors_note_position`, `#authors_note_depth`, `#authors_note_role`
  - per-chat overrides via DSL or `TavernKit.build` / `TavernKit.to_messages`

## 9. World Info (Lorebook) behavior

World Info is a set of entries activated by keyword matching.

**High-level process:**
1. Choose a "scan buffer" from the last N messages (scan depth)
2. Optionally include message prefixes with participant names
3. For each entry: if keys found in scan buffer, entry is a candidate
4. Apply constraints: token budget, recursion rules, timed effects
5. Insert activated entries into the prompt

**Scan depth semantics:**
- **scan_depth = 0**: Only recursed entries and Author's Note are evaluated
- **scan_depth = 1**: Scan only the last message
- **scan_depth = N**: Scan the last N messages

### 9.1 Scan buffer composition

- Base buffer: generation chat messages, ordered newest → oldest
- Excludes: character example dialogues (`mesExamples`)
- Optional per-entry additions: persona/character fields via `match_*` flags
- Additional sources: scannable injections, recursion buffer text

**Prioritization:**
- constant entries first
- then entries ordered by their configured order
- directly matched entries have higher priority than indirectly activated ones

### 9.2 Default settings

- `world_info_depth` defaults to **2**
- `world_info_include_names` defaults to **true**
- Character lore insertion strategy defaults to **character_first**
- `world_info_min_activations` defaults to **0** (disabled)

**Insertion strategy source classification:**
- "Character lore" includes entries with `source: :character` and any `source` prefixed with `character_` (e.g., `:character_primary`, `:character_additional`).
- "Global lore" includes entries with `source: :global` and any `source` prefixed with `global_`.

### 9.3 Min activations scan

SillyTavern supports expanding scan depth until at least N entries activate.

**Settings:**
- `world_info_min_activations`
- `world_info_min_activations_depth_max`

**Behavior:**
- Start with `world_info_depth`
- If activated entries < `world_info_min_activations`, increase depth and rescan
- Stop when min activations satisfied, depth max reached, or chat exhausted

**TavernKit implementation:**
- Exposed via `Preset#world_info_min_activations` and `Preset#world_info_min_activations_depth_max`
- Min activations and recursive scanning are treated as **mutually exclusive**

### 9.4 Timed effects: sticky / cooldown / delay

- `sticky`: When active, entry added regardless of key match; probability not re-rolled
- `cooldown`: Suppresses activation while active; sticky overrides cooldown
- `delay`: Suppresses activation until `chat_message_count >= delay`

**TavernKit implementation:**
- Stored in `ChatVariables` store (`macro_vars: { local_store: ... }`)
- Storage key: `__tavern_kit__timed_world_info` (JSON)

### 9.5 Probability + inclusion groups + optional group scoring

**Probability:**
- `useProbability` + `probability` (0..100) gates activation
- Sticky entries bypass re-rolling

**Inclusion groups:**
- `group` defines one or more group names (comma-separated)
- If multiple entries in same group would activate, ST chooses a winner:
  - `groupOverride=true` entries win first (highest order)
  - otherwise weighted random by `groupWeight`

**Optional group scoring:**
- `world_info_use_group_scoring` (global) or per-entry `useGroupScoring`
- When enabled, entries with lower match score are removed before picking winner

**TavernKit:** Exposed via `Preset#world_info_use_group_scoring`

### 9.6 Forced activations, ignoreBudget, and automationId

**Forced activations:**
- ST supports forcing specific World Info entries active via `WORLDINFO_FORCE_ACTIVATE`
- Forced entries may override fields like content/position/depth/role

**ignoreBudget:**
- Entries with `ignoreBudget=true` bypass token budget cutoff
- Still contribute to running token count for subsequent checks

**automationId:**
- String identifier for automation tooling

**TavernKit:**
- `TavernKit.build` with `force_world_info` DSL method for one-shot forced activations
- `Lore::Engine#evaluate(forced_activations: ...)` for direct engine usage

### 9.7 Decorators: @@activate / @@dont_activate

SillyTavern supports decorators at the start of entry content:

- `@@activate` — Forces the entry to activate (bypasses key matching)
- `@@dont_activate` — Prevents the entry from activating

TavernKit parses and honors these decorators.

## 10. Data Bank (RAG) behavior

Data Bank is an attachment/document system with:
- scopes: global / character / chat
- vectorization (embeddings) and retrieval
- injection template and injection position
- optional "include in World Info scanning"

**TavernKit status:** Planned for Phase 4, not yet implemented.
The library is designed to accept external knowledge providers via interface.

## 11. Conformance tests

See `docs/spec/fixtures/st_prompt_build_min_case.yml` for minimal deterministic test cases.
