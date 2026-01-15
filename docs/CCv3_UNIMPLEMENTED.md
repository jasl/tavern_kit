# CCv3 Unimplemented Features

This document tracks CCv3 spec features that TavernKit has not yet implemented.

All listed features are **optional** per the CCv3 specification - applications MAY implement them and MAY ignore them. However, even if not implemented, applications SHOULD preserve these fields for safe round-trip export.

## Status Legend

| Status | Description |
|--------|-------------|
| 🟡 Parsed | Field is parsed but not used in prompt building |
| ⚪ Not Parsed | Field is not parsed (should be preserved in `extensions`) |
| 🔴 Not Implemented | Feature is not implemented |

---

## Decorators

### State-Tracking Decorators

These decorators require cross-prompt state persistence to function correctly.

| Decorator | Status | Impact | Implementation Notes |
|-----------|--------|--------|---------------------|
| `@@keep_activate_after_match` | 🔴 | Low | Entry stays active after first match. Requires match history storage. |
| `@@dont_activate_after_match` | 🔴 | Low | Entry deactivates after first match. Requires match history storage. |

**Implementation Difficulty:** Medium - Requires persistent state between evaluations

### Instruct Mode Decorators

These decorators are designed for non-chat (instruct/completion) contexts.

| Decorator | Status | Impact | Implementation Notes |
|-----------|--------|--------|---------------------|
| `@@instruct_depth` | 🔴 | Low | Token-based depth (vs message-based). Only for instruct mode. |
| `@@reverse_depth` | 🔴 | Low | Depth from oldest message. Simple arithmetic: `total - value` |
| `@@reverse_instruct_depth` | 🔴 | Low | Token-based reverse depth. Only for instruct mode. |
| `@@instruct_scan_depth` | 🔴 | Low | Token-based scan depth. Only for instruct mode. |

**Implementation Difficulty:** Easy (reverse_*) to Medium (instruct_*)

### Greeting/UI Decorators

| Decorator | Status | Impact | Implementation Notes |
|-----------|--------|--------|---------------------|
| `@@is_greeting` | 🔴 | Low | Only activate for specific greeting index. Requires greeting tracking. |
| `@@is_user_icon` | 🔴 | Low | Only activate for specific user icon. Requires UI support. |
| `@@disable_ui_prompt` | 🔴 | Low | Disable system_prompt/post_history_instructions. Edge case. |

**Implementation Difficulty:** Easy (`@@is_greeting`) to Medium (UI integration)

---

## Asset Handling

| Feature | Status | Impact | Implementation Notes |
|---------|--------|--------|---------------------|
| Asset URI parsing (`embeded://`, `ccdefault:`) | 🔴 | None | Only affects visual display, not prompt building |
| CharX export with embedded assets | 🔴 | None | CHARX import is supported; export not needed for prompt building |

**Implementation Difficulty:** Medium - Requires binary file handling

---

## Alternative Activation Methods

| Feature | Status | Impact | Implementation Notes |
|---------|--------|--------|---------------------|
| Vector Storage Matching | 🔴 | Low | Semantic/embedding-based entry activation. Requires embedding model. |

**Implementation Difficulty:** High - Requires external embedding service integration

---

## Lorebook Association Features

### What's Implemented (Playground)

| Feature | Status | Notes |
|---------|--------|-------|
| Embedded character_book | ✅ | Stored in `data.character_book`, always active |
| Primary lorebook | ✅ | ST's "Link to World Info" - exported with character |
| Additional lorebooks | ✅ | ST's "Extra World Info" - local only, not exported |
| Global space lorebooks | ✅ | Via SpaceLorebook association |
| Chat-bound lorebook | ✅ | Via ConversationLorebook association (ST: Chat Lore) |
| Export merging | ✅ | Primary lorebook merged into character_book on export |

### What's NOT Implemented

| Feature | ST Behavior | Status | Notes |
|---------|-------------|--------|-------|
| Persona-bound lorebook | User persona can link to lorebook | ❌ | [Backlog](../playground/docs/BACKLOGS.md#persona-bound-lorebooks) - requires persona feature |
| Lorebook extraction on import | Offer to extract embedded lorebook to separate file | ❌ | UX enhancement |

---

## Summary

### What's Implemented (affects prompt building)

✅ All required CCv3 fields  
✅ `{{char}}` uses `nickname` when present  
✅ `{{// comment}}` macro (removed from output)  
✅ `{{hidden_key:A}}` macro (for recursive lorebook scanning)  
✅ `{{comment: A}}` macro (removed from output)  
✅ `use_regex` field and regex key matching  
✅ Core decorators: `@@depth`, `@@role`, `@@position`, `@@scan_depth`  
✅ Activation decorators: `@@constant`, `@@dont_activate`, `@@activate`  
✅ Timing decorators: `@@activate_only_after`, `@@activate_only_every`  
✅ Key decorators: `@@additional_keys`, `@@exclude_keys`  
✅ Matching decorators: `@@use_regex`, `@@case_sensitive`  
✅ Context decorators: `@@ignore_on_max_context`  
✅ Position values: `before_desc`, `after_desc`, `personality`, `scenario`  
✅ Character-lorebook associations (primary + additional)

### What's NOT Implemented (minimal/no impact on typical usage)

❌ State-tracking decorators (`@@keep_activate_after_match`, `@@dont_activate_after_match`)  
❌ Instruct mode decorators (`@@instruct_depth`, `@@instruct_scan_depth`, etc.)  
❌ UI-dependent decorators (`@@is_greeting`, `@@is_user_icon`, `@@disable_ui_prompt`)  
❌ Asset URI parsing (display only, not prompt-related)  
❌ Vector/embedding-based matching (requires external service)  
❌ Persona-bound lorebooks ([Backlog](../playground/docs/BACKLOGS.md#persona-bound-lorebooks))

---

## References

- [CCv3 Specification](https://github.com/kwaroran/character-card-spec-v3)
- [SillyTavern World Info Docs](https://docs.sillytavern.app/usage/core-concepts/worldinfo/)
- [Local spec copy](../tmp/SPEC_V3.md)
