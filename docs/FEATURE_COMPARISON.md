# Feature Comparison: TavernKit/Playground vs SillyTavern vs RisuAI

This document provides a comprehensive comparison of features across TavernKit (Ruby gem), Playground (Rails app), SillyTavern, and RisuAI. It serves as a reference for final polishing before release and for making decisions about feature priorities.

**Reference versions:**
- SillyTavern: v1.15.0 (vendored in `tmp/SillyTavern`)
- RisuAI: Latest (vendored in `tmp/Risuai`)

**Status Legend:**
| Symbol | Meaning |
|--------|---------|
| ✅ | Fully implemented |
| ⚠️ | Partially implemented |
| ❌ | Not implemented |
| 🔄 | Planned / In backlog |
| N/A | Not applicable / Out of scope |

---

## Table of Contents

1. [Core Prompt Building](#1-core-prompt-building)
2. [World Info / Lorebook](#2-world-info--lorebook)
3. [Macro System](#3-macro-system)
4. [Provider / Format Support](#4-provider--format-support)
5. [Character Card Formats](#5-character-card-formats)
6. [Chat / Conversation Features](#6-chat--conversation-features)
7. [Group Chat Features](#7-group-chat-features)
8. [Memory / Summary](#8-memory--summary)
9. [RAG / Data Bank](#9-rag--data-bank)
10. [Instruct Mode / Context Template](#10-instruct-mode--context-template)
11. [Scripting / Extensions](#11-scripting--extensions)
12. [UI/UX Features](#12-uiux-features)
13. [Data Management](#13-data-management)
14. [Key Findings](#key-findings)
15. [Decision Points](#decision-points)

---

## 1. Core Prompt Building

The foundation of roleplay AI applications - how prompts are constructed and sent to LLMs.

| Feature | SillyTavern | RisuAI | TavernKit/Playground | Notes |
|---------|-------------|--------|---------------------|-------|
| **Prompt Manager** | ✅ Full UI with drag-drop ordering, conditional triggers | ⚠️ Simplified preset template system | ✅ Full implementation with conditions, depth, role | TavernKit extends condition system beyond ST |
| **Main Prompt + PHI** | ✅ Global default + character override + `{{original}}` | ✅ System prompt override support | ✅ Fully compatible | |
| **In-chat Injection (Depth)** | ✅ depth=0 at end, depth=N before Nth message | ✅ Depth insertion supported | ✅ Fully compatible | |
| **Author's Note** | ✅ Frequency, position, depth, role | ✅ Author's Note support | ✅ Fully compatible | |
| **Character Depth Prompt** | ✅ `extensions.depth_prompt` | ✅ Character depth prompts | ✅ Fully implemented | |
| **Group Nudge** | ✅ Appends speaker instruction at end of group chat | ✅ Group chat support | ✅ Implemented | |
| **Continue Generation** | ✅ With prefill or nudge prompt | ✅ Supported | ✅ Via prefill | |
| **Impersonate** | ✅ Write as user persona | ✅ Supported | ✅ Copilot feature | |
| **System Message Squashing** | ✅ OpenAI-style consecutive system merge | Unknown | ✅ Configurable | |
| **Role-based Grouping** | ✅ Assistant → User → System order at same depth | Unknown | ✅ Implemented | |
| **forbid_overrides** | ✅ Prompt entry blocks character overrides | ❌ | ✅ Supported | |

### Analysis

TavernKit's prompt building is **fully compatible** with SillyTavern's model. Key advantages:
- Extended condition system (`conditions.chat`, `conditions.turns`, `conditions.user`, `conditions.character`)
- Boolean grouping with `all`/`any` for complex conditions
- Clean separation between Prompt Manager logic and macro expansion

---

## 2. World Info / Lorebook

Dynamic content injection based on keyword matching in conversation context.

| Feature | SillyTavern | RisuAI | TavernKit/Playground | Notes |
|---------|-------------|--------|---------------------|-------|
| **Keyword Matching** | ✅ Plain text, regex, whole-word | ✅ Keywords, regex | ✅ Fully implemented | |
| **Secondary Keys (Selective)** | ✅ AND logic for activation | ✅ Supported | ✅ Implemented | |
| **Constant Entries** | ✅ Always active | ✅ `alwaysActive` | ✅ Implemented | |
| **Recursive Scanning** | ✅ Configurable depth | ✅ `recursiveScanning` | ✅ Implemented | |
| **Timed Effects** | ✅ sticky/cooldown/delay | ❌ Not found | ✅ Fully implemented | **RisuAI gap** |
| **Probability** | ✅ 0-100% random activation | ❌ Not found | ✅ Implemented | **RisuAI gap** |
| **Inclusion Groups** | ✅ groupOverride/groupWeight | ❌ Not found | ✅ Fully implemented | **RisuAI gap** |
| **Group Scoring** | ✅ Score-based selection | ❌ Not found | ✅ Implemented | **RisuAI gap** |
| **Token Budget** | ✅ Configurable limit | ✅ `loreToken` | ✅ Implemented | |
| **Min Activations** | ✅ Expand depth until N entries activate | ❌ Not found | ✅ Implemented | |
| **Position Options** | ✅ before_char/after_char/in_chat/outlet etc. | ⚠️ `insertorder` | ✅ Full support | |
| **Match Flags** | ✅ match_persona/match_description etc. | ❌ Not found | ✅ Implemented | |
| **Decorators** | ✅ `@@activate`/`@@dont_activate` etc. | ❌ Not found | ✅ Core decorators implemented | See CCv3_UNIMPLEMENTED.md |
| **Vector Matching** | ✅ Embedding-based semantic matching | ✅ Vector search support | ❌ Not implemented | 🔄 Phase 4 |
| **Lorebook Sources** | ✅ Global/Character/Chat/Persona | ✅ Global/Chat local | ✅ Global/Space/Character/Chat | |
| **ignoreBudget** | ✅ Bypass token budget | Unknown | ✅ Implemented | |
| **preventRecursion** | ✅ Prevent recursive activation | Unknown | ✅ Implemented | |
| **delayUntilRecursion** | ✅ Only activate during recursion | Unknown | ✅ Implemented | |

### Analysis

TavernKit has **superior World Info implementation** compared to RisuAI, matching ST's advanced features:
- Timed effects (sticky/cooldown/delay)
- Inclusion groups with weight and override
- Probability-based activation
- Min activations with depth expansion

The main gap is **vector/embedding-based matching** (planned for Phase 4).

---

## 3. Macro System

Template replacement tags for dynamic content in prompts.

| Feature | SillyTavern | RisuAI | TavernKit | Notes |
|---------|-------------|--------|-----------|-------|
| **Basic Macros** | ✅ `{{char}}`/`{{user}}` etc. | ✅ Similar macros | ✅ Implemented | |
| **Character Field Macros** | ✅ `{{description}}`/`{{personality}}` | ✅ Supported | ✅ Implemented | |
| **Conversation Macros** | ✅ `{{lastMessage}}`/`{{lastUserMessage}}` | ✅ Supported | ✅ Implemented | |
| **Variable Macros** | ✅ `{{setvar}}`/`{{getvar}}` | ✅ `chatVars` | ✅ Implemented | |
| **Global Variables** | ✅ `{{setglobalvar}}`/`{{getglobalvar}}` | ✅ Supported | ✅ Implemented | |
| **Random Macros** | ✅ `{{random}}`/`{{pick}}`/`{{roll}}` | ✅ `pickHashRand` | ✅ Implemented | |
| **Time Macros** | ✅ `{{date}}`/`{{time}}`/`{{timeDiff}}` | ✅ Supported | ✅ Implemented | |
| **Instruct Macros** | ✅ `{{instructInput}}`/`{{chatStart}}` | ✅ Template system | ✅ Implemented | |
| **Legacy Macros** | ✅ `<USER>`/`<BOT>` etc. | Unknown | ❌ Intentionally not implemented | Use `{{user}}`/`{{char}}` |
| **Handlebars Conditionals** | ✅ `{{#if}}`/`{{#each}}` | ❌ Not found | ❌ Not implemented | Use conditional prompts instead |
| **Weighted Random** | ✅ `{{random:weighted::...}}` | ❌ Not found | ❌ Not implemented | 🔄 Planned |
| **Expression Evaluation** | ✅ `{{eval}}`/`{{calc}}` | ❌ Not found | ❌ Not implemented | |
| **Macro Engine 2.0** | ⚠️ Experimental (behind flag) | Unknown | ✅ Default engine | TavernKit leads here |
| **Custom Macro Registration** | ✅ Plugin API | ✅ Plugin API | ✅ `TavernKit.macros.register` | |
| **Comment Macro** | ✅ `{{// ... }}` | Unknown | ✅ Implemented | |
| **Banned Words** | ✅ `{{banned "..."}}` | Unknown | ⚠️ Removed only (no side effects) | |
| **Outlet Macro** | ✅ `{{outlet::name}}` | Unknown | ✅ Implemented | |

### Analysis

TavernKit's macro system is **strong**, with Macro Engine 2.0 as the **default** (ST still has it experimental):
- True nested macro support
- Stable left-to-right evaluation
- Unknown macros preserved while nested macros still expand

Gaps are **Handlebars conditionals** and **weighted random**, but these have workarounds.

---

## 4. Provider / Format Support

LLM provider API formats and dialect conversion.

| Provider | SillyTavern | RisuAI | TavernKit | Notes |
|----------|-------------|--------|-----------|-------|
| **OpenAI** | ✅ | ✅ | ✅ | |
| **Anthropic** | ✅ + `cache_control` | ✅ | ✅ (no cache) | Cache control not implemented |
| **Google Gemini** | ✅ + thinking mode | ✅ | ✅ | Thinking mode not implemented |
| **Cohere** | ✅ | ✅ | ✅ | |
| **AI21** | ✅ | ✅ | ✅ | |
| **Mistral** | ✅ + prefix | ✅ | ✅ + prefix | |
| **xAI** | ✅ | Unknown | ✅ | |
| **Text Completion** | ✅ | ✅ | ✅ | |
| **OpenRouter** | ✅ + special handling | ✅ | ❌ No special handling | Configure at HTTP client level |
| **KoboldAI/llama.cpp** | ✅ | ✅ webllm | Via Playground | |
| **NovelAI** | ✅ | ✅ | ❌ | Specialized provider |
| **Horde** | ✅ | ✅ | ❌ | Specialized provider |

### Analysis

TavernKit covers all **mainstream providers**. Missing features:
- Claude `cache_control` (cost optimization)
- Gemini thinking mode
- OpenRouter-specific transforms

These are **nice-to-haves** rather than blockers.

---

## 5. Character Card Formats

Character card specification support and import/export.

| Feature | SillyTavern | RisuAI | TavernKit/Playground | Notes |
|---------|-------------|--------|---------------------|-------|
| **CCv2 Read** | ✅ | ✅ CCardLib | ✅ | |
| **CCv3 Read** | ✅ | ✅ CCardLib | ✅ | |
| **PNG Metadata Write** | ✅ | ✅ | ✅ | |
| **CharX (.charx)** | ✅ | ✅ | ❌ | 🔄 Phase 5 |
| **JPEG-wrapped CharX** | ✅ | ✅ | ❌ | 🔄 Phase 5 |
| **Assets (images/audio)** | ✅ Full support | ✅ Full support | N/A | TavernKit is prompt builder |
| **group_only_greetings** | ✅ | ✅ | ✅ | |
| **nickname** | ✅ | ✅ | ✅ | |
| **creator_notes_multilingual** | ✅ | ✅ | ✅ | Parsed, preserved |
| **source** | ✅ | ✅ | ✅ | |
| **creation/modification_date** | ✅ | ✅ | ✅ | |

### Analysis

Character card support is **comprehensive**. CharX format support is planned for Phase 5 but not critical for initial release since PNG cards are the most common format.

---

## 6. Chat / Conversation Features

Message management and conversation operations.

| Feature | SillyTavern | RisuAI | Playground | Notes |
|---------|-------------|--------|------------|-------|
| **Swipes** | ✅ Multiple response versions | ✅ | ✅ MessageSwipe model | |
| **Regenerate** | ✅ | ✅ | ✅ | |
| **Continue** | ✅ | ✅ | ✅ Via prefill | |
| **Impersonate** | ✅ | ✅ | ✅ Copilot | |
| **Edit Message** | ✅ | ✅ | ✅ | |
| **Delete Message** | ✅ | ✅ | ✅ | |
| **Branch/Fork** | ✅ | ✅ | ✅ | |
| **Chat Export** | ✅ JSONL/TXT | ✅ | ❌ | 🔄 Backlog |
| **Chat Import** | ✅ | ✅ | ❌ | 🔄 Backlog |
| **Message Exclude** | ✅ | Unknown | ✅ `excluded_from_prompt` | |
| **Streaming Response** | ✅ | ✅ | ✅ ActionCable | |
| **Chat Metadata** | ✅ JSONL header | ✅ | ✅ DB fields | Different storage approach |
| **Checkpoints/Bookmarks** | ✅ | ✅ | 🔄 | Partial implementation |

### Analysis

Core chat features are **fully implemented**. Export/import are in backlog but not critical for MVP.

---

## 7. Group Chat Features

Multi-character conversation management.

| Feature | SillyTavern | RisuAI | Playground | Notes |
|---------|-------------|--------|------------|-------|
| **Multiple Characters** | ✅ | ✅ | ✅ SpaceMembership | |
| **Speaker Order** | ✅ manual/natural/list | ✅ Multiple modes | ✅ manual/natural/list/pooled | Playground adds `pooled` |
| **Mute Members** | ✅ | ✅ | ✅ `participation=muted` | |
| **Auto-mode** | ✅ AI→AI continuous | ✅ | ✅ | |
| **Group Nudge** | ✅ | Unknown | ✅ | |
| **Group-only Greetings** | ✅ | ✅ | ✅ | |
| **Per-member Settings** | ⚠️ Limited | Unknown | ✅ SpaceMembership.settings | Playground advantage |

### Analysis

Group chat is **fully featured** with Playground offering **additional flexibility** via per-member settings.

---

## 8. Memory / Summary

Long-term context management and summarization.

| Feature | SillyTavern | RisuAI | Playground | Notes |
|---------|-------------|--------|------------|-------|
| **Summarization** | ✅ Extension support | ✅ Multiple implementations | ❌ | 🔄 Phase 4+ |
| **Memory Bank** | ✅ Extension support | ✅ hypav2/hypav3 | ❌ | |
| **Vector Memory** | ✅ vectors extension | ✅ supaMemory | ❌ | |
| **Chat Summary Injection** | ✅ | ✅ | ❌ | |

### Analysis

**Major gap** - both ST and RisuAI have robust memory systems. This is a key differentiator for long conversations. Planned for Phase 4.

---

## 9. RAG / Data Bank

Document retrieval and knowledge injection.

| Feature | SillyTavern | RisuAI | Playground | Notes |
|---------|-------------|--------|------------|-------|
| **Document Attachments** | ✅ | Unknown | ❌ | 🔄 Phase 4 |
| **Vector Embeddings** | ✅ | ✅ embedding | ❌ | |
| **Retrieval Injection** | ✅ | ✅ | ❌ | |
| **Injection Template** | ✅ | Unknown | ❌ | |
| **Multiple Sources** | ✅ Transformers/OpenAI/Cohere etc. | ✅ | ❌ | |
| **Include in WI Scanning** | ✅ | Unknown | ❌ | |

### Analysis

**Major gap** - RAG is increasingly important for grounded conversations. Planned for Phase 4.

---

## 10. Instruct Mode / Context Template

Text completion formatting and template handling.

| Feature | SillyTavern | RisuAI | TavernKit | Notes |
|---------|-------------|--------|-----------|-------|
| **Input/Output Sequences** | ✅ | ✅ templates | ✅ | |
| **First/Last Variants** | ✅ | ✅ | ✅ | |
| **Story String** | ✅ | ✅ | ✅ | |
| **Stop Sequences** | ✅ | ✅ | ✅ | |
| **Names Behavior** | ✅ force/remove/default | ✅ | ✅ | |
| **activation_regex** | ✅ Enable by model name | Unknown | ❌ | Niche feature |
| **System/Input/Output Suffixes** | ✅ | ✅ | ✅ | |
| **Wrap Behavior** | ✅ | Unknown | ✅ | |

### Analysis

Instruct mode is **fully implemented**. The only gap (`activation_regex`) is a niche feature.

---

## 11. Scripting / Extensions

Automation and extensibility features.

| Feature | SillyTavern | RisuAI | Playground | Notes |
|---------|-------------|--------|------------|-------|
| **STscript** | ✅ Full scripting language | ❌ | ❌ | ST-specific feature |
| **Plugin API** | ✅ | ✅ API v3.0 | ❌ | |
| **Tool Calling** | ✅ ToolManager | Unknown | ❌ | 🔄 Phase 5+ |
| **MCP Support** | Unknown | ✅ mcp directory | ❌ | RisuAI unique |
| **Injection Registry** | ✅ `/inject` command | Unknown | ✅ InjectionRegistry | |
| **Triggers/Regex** | ✅ regex extension | ✅ triggers.ts | ❌ | |
| **Quick Replies** | ✅ | Unknown | ❌ | |
| **Custom Slash Commands** | ✅ | ❌ | ❌ | ST-specific |

### Analysis

Playground takes a **different approach** - rather than client-side scripting, it offers:
- Server-side hooks via `HookRegistry`
- `InjectionRegistry` for dynamic prompt injection
- Condition-based prompt activation

Tool Calling is planned for Phase 5+.

---

## 12. UI/UX Features

User interface and experience features.

| Feature | SillyTavern | RisuAI | Playground | Notes |
|---------|-------------|--------|------------|-------|
| **Themes** | ✅ Rich theming | ✅ | ✅ DaisyUI themes | |
| **Hotkeys** | ✅ Full keyboard shortcuts | ✅ defaulthotkeys | ⚠️ Partial | 🔄 Backlog |
| **Settings Search** | ✅ | Unknown | ❌ | |
| **Prompt Preview** | ✅ | ✅ | ✅ | |
| **Token Counter** | ✅ | ✅ | ✅ | |
| **Visual Novel Mode** | ❌ | ✅ VisualNovel | ❌ | RisuAI unique |
| **3D Model Support** | Unknown | ✅ 3d directory | ❌ | RisuAI unique |
| **Sprites/Expressions** | ✅ | ✅ | ❌ | Asset feature |
| **TTS** | ✅ | ✅ voice.ts | ❌ | |
| **STT** | ✅ | Unknown | ❌ | |
| **Image Generation** | ✅ SD extension | ✅ stableDiff | ❌ | |
| **Mobile Support** | ⚠️ | ✅ Mobile directory | ✅ Responsive | |
| **PWA** | ❌ | Unknown | 🔄 Backlog | |

### Analysis

Playground has **modern responsive UI** but lacks some media features (TTS, sprites, image gen). These are secondary to core RP functionality.

---

## 13. Data Management

Data organization, storage, and synchronization.

| Feature | SillyTavern | RisuAI | Playground | Notes |
|---------|-------------|--------|------------|-------|
| **Character Management** | ✅ | ✅ | ✅ | |
| **Preset Management** | ✅ Full UI | ✅ | ⚠️ Basic | 🔄 Backlog |
| **Lorebook Management** | ✅ | ✅ | ✅ | |
| **User Persona** | ✅ Full system | ✅ | ⚠️ Text only | 🔄 Backlog |
| **Backup/Restore** | ✅ | ✅ drive sync | ❌ | |
| **Cloud Sync** | ❌ | ✅ | ❌ | RisuAI unique |
| **Multi-user** | ✅ | ❌ | ✅ | Playground advantage |
| **Tags System** | ✅ | ✅ | ✅ | |

### Analysis

Playground's **multi-user support** is a key differentiator. Persona system enhancement is in backlog.

---

## Key Findings

### TavernKit/Playground Advantages

1. **Modern Architecture**: Rails + Hotwire with native multi-user support
2. **Complete World Info**: Timed effects, inclusion groups, and advanced features RisuAI lacks
3. **Macro Engine 2.0 Default**: True nested macro support as default (ST has it experimental)
4. **Extended Conditions**: Prompt Manager conditions more powerful than ST
5. **Clean Codebase**: Well-documented, maintainable Ruby code
6. **Per-member Settings**: Group chat flexibility via SpaceMembership

### Gaps to Address

| Priority | Feature | Status | Notes |
|----------|---------|--------|-------|
| **High** | Memory/RAG | Phase 4 | Both references have implementations |
| **Medium** | Tool Calling | Phase 5+ | ST has full implementation |
| **Medium** | Hotkeys | Backlog | UX improvement |
| **Low** | CharX Format | Phase 5 | PNG cards are most common |
| **Low** | STscript | N/A | Different approach taken |
| **Low** | Assets/Media | N/A | Out of scope for prompt builder |

### RisuAI Unique Features (For Reference)

1. **MCP Integration**: Model Context Protocol support
2. **Visual Novel Mode**: Visual novel style presentation
3. **3D Model Support**: Character 3D models
4. **Cloud Sync**: Non-multi-user sync
5. **Rich Memory**: hypav2/hypav3/supaMemory implementations

### Intentional Divergences

See [SILLYTAVERN_DIVERGENCES.md](spec/SILLYTAVERN_DIVERGENCES.md) for intentional behavior differences:
- Legacy macros (`<USER>` etc.) not implemented
- Pooled reply_order stops after one round (controllable)
- `{{pick}}` uses different RNG (Ruby vs seedrandom)

---

## Decision Points

### 1. Memory/RAG Priority

**Question**: Should Memory/RAG move up in priority?

**Context**:
- Both ST and RisuAI have robust implementations
- Critical for long conversations (>100 messages)
- Requires embedding service integration

**Options**:
- a) Keep as Phase 4 (after release)
- b) Prioritize for initial release
- c) Implement basic summarization first, vector later

### 2. RisuAI-Unique Features

**Question**: Which RisuAI features should be considered?

**Candidates**:
- MCP Integration (emerging standard)
- Visual Novel Mode (differentiation)
- Cloud Sync (convenience)

**Recommendation**: MCP is most aligned with modern AI tooling trends and could be a future differentiator.

### 3. Hotkey Completion

**Question**: Should hotkeys be completed before release?

**Context**:
- Significant UX improvement
- Relatively low effort (documented in BACKLOGS.md)
- ST users expect certain shortcuts

**Recommendation**: High impact/effort ratio - consider for pre-release polish.

---

## Summary Statistics

| Category | Implemented | Partial | Not Implemented | N/A |
|----------|-------------|---------|-----------------|-----|
| Core Prompt Building | 11 | 0 | 0 | 0 |
| World Info | 15 | 0 | 1 | 0 |
| Macros | 12 | 2 | 3 | 0 |
| Providers | 8 | 0 | 3 | 0 |
| Character Cards | 9 | 0 | 2 | 1 |
| Chat Features | 10 | 1 | 2 | 0 |
| Group Chat | 7 | 0 | 0 | 0 |
| Memory/RAG | 0 | 0 | 7 | 0 |
| Instruct Mode | 8 | 0 | 1 | 0 |
| Scripting | 2 | 0 | 6 | 0 |
| UI/UX | 5 | 2 | 7 | 0 |
| Data Management | 5 | 2 | 2 | 0 |
| **Total** | **92** | **7** | **34** | **1** |

**Coverage**: ~73% fully implemented, ~5% partial, ~22% not implemented (mostly out of scope or planned)

---

## References

### Roadmaps

- [TavernKit Gem Roadmap](spec/ROADMAP.md) - TavernKit gem 发布路线图
- [Playground Roadmap](playground/ROADMAP.md) - Playground app 发布路线图

### Specifications

- [TAVERNKIT_BEHAVIOR.md](spec/TAVERNKIT_BEHAVIOR.md) - TavernKit behavior specification
- [COMPATIBILITY_MATRIX.md](spec/COMPATIBILITY_MATRIX.md) - Feature compatibility matrix
- [SILLYTAVERN_DIVERGENCES.md](spec/SILLYTAVERN_DIVERGENCES.md) - Known intentional differences
- [CCv3_UNIMPLEMENTED.md](spec/CCv3_UNIMPLEMENTED.md) - CCv3 features not yet implemented
- [BACKLOGS.md](playground/BACKLOGS.md) - Playground backlog items
