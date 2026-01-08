# Compatibility Matrix

Reference implementation: SillyTavern v1.15.0 (vendored under `tmp/SillyTavern`).

## 1. CCv2 / CCv3 Feature Coverage

| Feature | CCv2 | CCv3 | TavernKit |
|---------|------|------|-----------|
| spec identifier | ✅ | ✅ | ✅ |
| data wrapper | ✅ | ✅ | ✅ |
| name/description/personality | ✅ | ✅ | ✅ |
| scenario | ✅ | ✅ | ✅ |
| first_mes | ✅ | ✅ | ✅ |
| mes_example | ✅ | ✅ | ✅ |
| alternate_greetings | ✅ | ✅ | ✅ |
| system_prompt | ✅ | ✅ | ✅ |
| post_history_instructions | ✅ | ✅ | ✅ |
| creator_notes | ✅ | ✅ | ✅ |
| character_book | ✅ | ✅ | ✅ |
| tags | ✅ | ✅ | ✅ |
| creator | ✅ | ✅ | ✅ |
| character_version | ✅ | ✅ | ✅ |
| extensions (preserve unknown) | ✅ | ✅ | ✅ |
| group_only_greetings | ❌ | ✅ | ✅ |
| assets | ❌ | ✅ | ✅ |
| nickname | ❌ | ✅ | ✅ |
| creator_notes_multilingual | ❌ | ✅ | ✅ |
| source | ❌ | ✅ | ✅ |
| creation_date | ❌ | ✅ | ✅ |
| modification_date | ❌ | ✅ | ✅ |

## 2. SillyTavern Prompt Features

| Feature | ST Behavior | TavernKit Status |
|---------|-------------|------------------|
| Main Prompt | Global default + char override | ✅ |
| Main Prompt (absolute position) | Prompt Manager can inject Main Prompt in-chat (depth/order) | ✅* |
| Post-History Instructions | Global default + char override | ✅ |
| `{{original}}` in overrides | Splices global default (one-shot) | ✅ |
| prefer_char_prompt | Use char system_prompt if present | ✅ |
| prefer_char_instructions | Use char PHI if present | ✅ |
| forbid_overrides | Prompt entry can block character overrides | ✅ |
| Prompt entries ordering | Via prompt_entries array | ✅ |
| In-chat injection | depth=0 at end, depth=N before N messages | ✅ |
| Role-based grouping (in-chat) | Assistant → User → System order | ✅ |
| Same role+depth+order merging | Entries combined per order group | ✅ |
| Group nudge (group chats) | `group_nudge_prompt` appended at end of chat history | ✅ |

\* TavernKit can place `main_prompt` as an in-chat prompt entry, but does not yet emulate ST's "relative-to-main" fallback behavior when the main prompt itself is in-chat.

## 2.1 Chat Storage / Metadata

| Feature | ST | TavernKit |
|---------|----|-----------|
| Chat JSONL metadata header | First line may be `{ "chat_metadata": { ... }, "user_name": "unused", "character_name": "unused" }` | ❌ Phase 5 |
| Unified group chat metadata format | Group chats use the same metadata header format as regular chats | ❌ Phase 5 |
| Group definition `chat_metadata` / `past_metadata` | Deprecated legacy source (migrated into per-chat JSONL headers) | ❌ Phase 5 |

## 3. Macro Support

### Macro engines

| Engine | ST | TavernKit |
|--------|----|-----------|
| Legacy substitution (`substituteParamsLegacy`) | ✅ | ✅ |
| Experimental Macro Engine / Macros 2.0 (`MacroEngine`) | ✅ (preview) | ✅* |

In ST 1.15.0, the MacroEngine path is behind `power_user.experimental_macro_engine`. Legacy substitution is deprecated upstream and will eventually be removed.

### Macros 2.0 semantics (Experimental Engine)

| Behavior | ST (MacroEngine) | TavernKit |
|----------|------------------|-----------|
| Nested macros inside arguments (true nesting) | ✅ | ✅* |
| Stable evaluation order (left-to-right; nested before parent) | ✅ | ✅* |
| Unknown macros preserved while still resolving nested macros inside | ✅ | ✅* |
| Deterministic `{{pick}}` uses original-input offsets (pre-replacement) | ✅ | ✅* |
| Post-process `{{trim}}` and unescape `\\{` / `\\}` | ✅ | ✅* |
| Pre-process legacy `{{time_UTC±N}}` into `{{time::UTC±N}}` | ✅ | ✅ (supports `{{time_UTC±N}}`) |
| Pre-process legacy non-curly markers (`<USER>`, `<BOT>`, …) | ✅ | ❌ |

\* Via `TavernKit::Macro::SillyTavernV2::Engine` (default). The legacy `TavernKit::Macro::SillyTavernV1::Engine` remains available as an opt-in.

| Macro | ST | TavernKit |
|-------|----|-----------| 
| `{{char}}` | ✅ | ✅ |
| `{{user}}` | ✅ | ✅ |
| `{{persona}}` | ✅ | ✅ |
| `{{description}}` | ✅ | ✅ |
| `{{personality}}` | ✅ | ✅ |
| `{{scenario}}` | ✅ | ✅ |
| `{{mesExamples}}` | ✅ | ✅ |
| `{{mesExamplesRaw}}` | ✅ | ✅ |
| `{{charPrompt}}` | ✅ | ✅ |
| `{{charJailbreak}}` / `{{charInstruction}}` | ✅ | ✅ |
| `{{original}}` | ✅ | ✅ |
| `{{outlet::name}}` | ✅ | ✅ |
| `{{charIfNotGroup}}` | ✅ | ✅ |
| `{{group}}` | ✅ | ✅ |
| `{{groupNotMuted}}` | ✅ | ✅ |
| `{{notChar}}` | ✅ | ✅ |
| `{{charVersion}}` / `{{char_version}}` | ✅ | ✅ |
| `{{charDepthPrompt}}` | ✅ | ✅ |
| `{{creatorNotes}}` | ✅ | ✅ |
| `{{input}}` | ✅ | ✅ |
| `{{lastMessage}}` | ✅ | ✅ |
| `{{lastUserMessage}}` | ✅ | ✅ |
| `{{lastCharMessage}}` | ✅ | ✅ |
| `{{lastMessageId}}` | ✅ | ✅ |
| `{{firstIncludedMessageId}}` | ✅ | ✅* |
| `{{firstDisplayedMessageId}}` | ✅ | ✅* |
| `{{lastSwipeId}}` | ✅ | ✅* |
| `{{currentSwipeId}}` | ✅ | ✅* |
| `{{idle_duration}}` | ✅ | ✅* |
| `{{maxPrompt}}` | ✅ | ✅ |
| `{{model}}` | ✅ | ✅* |
| `{{lastGenerationType}}` | ✅ | ✅* |
| `{{isMobile}}` | ✅ | ✅* |
| `{{newline}}` | ✅ | ✅ |
| `{{newline::N}}` | ✅ (exp) | ❌ |
| `{{space}}` / `{{space::N}}` | ✅ (exp) | ❌ |
| `{{trim}}` | ✅ | ✅ |
| `{{noop}}` | ✅ | ✅ |
| `{{reverse:...}}` | ✅ | ✅ |
| `{{// ... }}` | ✅ | ✅ |
| `\{` / `\}` unescape | ✅ (exp) | ✅* |
| `{{banned "..."}}` | ✅ | ✅ |
| `{{setvar::name::value}}` | ✅ | ✅ |
| `{{getvar::name}}` | ✅ | ✅ |
| `{{addvar::name::value}}` | ✅ | ✅ |
| `{{incvar::name}}` / `{{decvar::name}}` | ✅ | ✅ |
| `{{setglobalvar::name::value}}` | ✅ | ✅ |
| `{{getglobalvar::name}}` | ✅ | ✅ |
| `{{addglobalvar::name::value}}` | ✅ | ✅ |
| `{{incglobalvar::name}}` / `{{decglobalvar::name}}` | ✅ | ✅ |
| `<USER>` / `<BOT>` / `<CHAR>` / `<GROUP>` / `<CHARIFNOTGROUP>` | ✅ | ❌ |
| `{{date}}` / `{{time}}` | ✅ | ✅ |
| `{{weekday}}` / `{{isodate}}` / `{{isotime}}` | ✅ | ✅ |
| `{{datetimeformat ...}}` | ✅ | ✅ |
| `{{time_UTC±N}}` | ✅ | ✅ |
| `{{timeDiff::a::b}}` | ✅ | ✅ |
| `{{random::a,b,c}}` | ✅ | ✅ |
| `{{pick::a,b,c}}` | ✅ | ✅ |
| `{{roll:dN}}` | ✅ | ✅ |
| Case-insensitive | ✅ | ✅ |

\* Some macros (`{{model}}`, `{{lastGenerationType}}`, `{{isMobile}}`, swipe/id/idle macros, and deterministic `{{pick}}`) require the caller to provide values/metadata (e.g., `send_date` for idle time, chat-id hash as `pick_seed`, mobile state); TavernKit supplies empty/"false"/"just now" defaults unless overridden.

  For deterministic `{{pick}}`:
  * `TavernKit::Macro::SillyTavernV1::Engine` (legacy, multi-pass) behaves like ST legacy and uses the *current string* offset (after earlier replacements).
  * `TavernKit::Macro::SillyTavernV2::Engine` (parser-based, Macros 2.0) behaves like ST MacroEngine and uses the *original input* offset (pre-replacement).

  Note: results still may not be byte-for-byte identical to ST in all cases (see `docs/spec/SILLYTAVERN_DIVERGENCES.md`).

## 4. World Info (Lorebook)

| Feature | ST | TavernKit |
|---------|----|-----------| 
| Keyword matching | ✅ | ✅ |
| Secondary keys (selective) | ✅ | ✅ |
| Regex keys | ✅ | ✅ |
| match_whole_words | ✅ | ✅ |
| case_sensitive | ✅ | ✅ |
| Constant entries | ✅ | ✅ |
| Position: before_char_defs | ✅ | ✅ |
| Position: after_char_defs | ✅ | ✅ |
| Position: before_example_messages | ✅ | ✅ |
| Position: after_example_messages | ✅ | ✅ |
| Position: top_of_an | ✅ | ✅ |
| Position: bottom_of_an | ✅ | ✅ |
| Position: at_depth (in-chat) | ✅ | ✅ |
| Position: outlet | ✅ | ✅ |
| Token budget | ✅ | ✅ |
| Recursive scanning | ✅ | ✅ |
| scan_depth semantics (0=none) | ✅ | ✅ |
| Insertion strategies | ✅ | ✅ |
| Min activations depth skew | ✅ | ✅ |
| Timed effects (sticky/cooldown/delay) | ✅ | ✅ |
| Probability | ✅ | ✅ |
| Generation triggers | ✅ | ✅ |

## 5. Author's Note

| Feature | ST | TavernKit |
|---------|----|-----------| 
| In-chat @ depth | ✅ | ✅ |
| Frequency: 0 = never | ✅ | ✅ |
| Frequency: 1 = always | ✅ | ✅ |
| Frequency: N = every Nth | ✅ | ✅ |
| Macro expansion | ✅ | ✅ |

## 6. Context Trimming

| Feature | ST | TavernKit |
|---------|----|-----------| 
| context_window_tokens | ✅ | ✅ |
| reserved_response_tokens | ✅ | ✅ |
| Examples: trim | ✅ | ✅ |
| Examples: always_keep | ✅ | ✅ |
| Examples: disable | ✅ | ✅ |
| Priority-based eviction | ✅ | ✅ |
| Trim report | ✅ | ✅ |

## 7. PNG Metadata & Card Import Formats

| Feature | ST | TavernKit |
|---------|----|-----------| 
| Read `chara` chunk (V2) | ✅ | ✅ |
| Read `ccv3` chunk (V3) | ✅ | ✅ |
| Write PNG metadata | ✅ | ✅ |
| Import CharX (`.charx`) | ✅ | ❌ Phase 5 |
| Import JPEG-wrapped CharX | ✅ | ❌ Phase 5 |

### CharX assets (server import)

| Feature | ST | TavernKit |
|---------|----|-----------|
| SFX/JPEG-wrapped CharX: scan for ZIP signature (`PK\\x03\\x04`) | ✅ | ❌ Phase 5 |
| Embedded asset URI prefixes (`embeded://`, `embedded://`, `__asset:`) | ✅ | ❌ Phase 5 |
| Avatar selection from embedded icon asset (prefer `type=icon`, `name=main`) | ✅ | ❌ Phase 5 |
| Auxiliary asset mapping: sprites/backgrounds/misc + ST folder targets | ✅ | ❌ Phase 5 |
| Name normalization: strip trailing ext, hyphenate sprite basenames, overwrite by basename | ✅ | ❌ Phase 5 |

## 8. Data Bank (RAG)

| Feature | ST | TavernKit |
|---------|----|-----------| 
| Document attachments | ✅ | ❌ Phase 4 |
| Vector embeddings | ✅ | ❌ Phase 4 |
| Retrieval injection | ✅ | ❌ Phase 4 |
| Injection template | ✅ | ❌ Phase 4 |

## 9. Tool Calling / Function Calling

| Feature | ST | TavernKit |
|---------|----|-----------| 
| Function registration (`ToolManager.registerFunctionTool`) | ✅ | ❌ Phase 5+ |
| Tool definition structure | ✅ | ❌ Phase 5+ |
| Tool invocation injection | ✅ | ❌ Phase 5+ |
| Tool result handling | ✅ | ❌ Phase 5+ |
| Stealth tools | ✅ | ❌ Phase 5+ |

## 10. Advanced Macros

| Feature | ST | TavernKit |
|---------|----|-----------| 
| `{{#if}}` / `{{#unless}}` conditionals | ✅ | ❌ |
| `{{#each}}` loops | ✅ | ❌ |
| `{{eval}}` / `{{calc}}` expression evaluation | ✅ | ❌ |
| `{{random:weighted::...}}` weighted selection | ✅ | ❌ |
| Basic `{{random::...}}` equal-weight | ✅ | ✅ |

## 11. Provider-Specific Features

| Feature | ST | TavernKit |
|---------|----|-----------| 
| OpenAI Chat Completions | ✅ | ✅ |
| Anthropic Messages API | ✅ | ✅ |
| Cohere Chat | ✅ | ✅ |
| Google Gemini | ✅ | ✅ |
| AI21 | ✅ | ✅ |
| Mistral (with prefix) | ✅ | ✅ |
| xAI | ✅ | ✅ |
| Text Completion | ✅ | ✅ |
| Claude `cache_control` | ✅ | ❌ |
| OpenRouter transforms | ✅ | ❌ |
| Gemini thinking mode | ✅ | ❌ |

## 12. Instruct Mode

| Feature | ST | TavernKit |
|---------|----|-----------| 
| Input/output/system sequences | ✅ | ✅ |
| First/last sequence variants | ✅ | ✅ |
| Story string prefix/suffix | ✅ | ✅ |
| Stop sequences | ✅ | ✅ |
| Wrap behavior | ✅ | ✅ |
| Names behavior (force/remove/default) | ✅ | ✅ |
| `activation_regex` | ✅ | ❌ |

## 13. STscript / Scripting

| Feature | ST | TavernKit |
|---------|----|-----------| 
| `/inject` command | ✅ | ✅ (InjectionRegistry) |
| `/gen` command | ✅ | ❌ |
| `/setvar` / `/getvar` | ✅ | ✅ (macro equivalents) |
| `/if` / `/else` flow control | ✅ | ❌ |
| Full STscript parser | ✅ | ❌ |

## 14. World Info Advanced Features

| Feature | ST | TavernKit |
|---------|----|-----------| 
| `@@activate` decorator | ✅ | ✅ |
| `@@dont_activate` decorator | ✅ | ✅ |
| Inclusion groups | ✅ | ✅ |
| Group override | ✅ | ✅ |
| Group weight | ✅ | ✅ |
| Group scoring | ✅ | ✅ |
| Forced activations | ✅ | ✅ |
| `ignoreBudget` | ✅ | ✅ |
| `automationId` | ✅ | ✅ (parsed, not used) |
| `preventRecursion` | ✅ | ❌ |
| `delayUntilRecursion` | ✅ | ❌ |
| Per-entry scan depth override | ✅ | ✅ |
| Match flags (persona/description/etc) | ✅ | ✅ |
