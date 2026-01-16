# Character Card V2 (CCv2) — Interop Notes

## 0. Scope

This document describes the CCv2 *data interchange* shape and minimal semantics needed for:
- importing/exporting character cards, and
- building prompts from card content.

PNG embedding details are non-normative (optional).

## 1. Overview

CCv2 extends the older "V1 / TavernAI-style" character card JSON by adding a nested `data` object.
The `data` object is intended to contain all CCv2 fields (including new ones), while legacy/V1 fields
may remain at the root for backward compatibility.

> Practical guidance:
> - Read `data` as the canonical source of truth.
> - Mirror to root fields only for compatibility during export.

## 2. Identification

A CCv2 card SHOULD include:

- `spec`: string, MUST be `"chara_card_v2"`
- `spec_version`: string, SHOULD be `"2.0"`

Future minor versions MUST be backward-compatible (additive only).

## 3. Canonical data location

- `data` MUST be an object for CCv2 cards.
- When both root-level fields and `data.*` exist, implementations SHOULD prefer `data.*`.

## 4. Data Model

### 4.1 Root object (common in the ecosystem)

Legacy/V1-style fields commonly found at the root (non-exhaustive):
- `name`, `description`, `personality`, `scenario`, `first_mes`, `mes_example`
- plus ecosystem-specific metadata (avatar/chat/talkativeness/fav/etc.)

CCv2 adds:
- `spec`, `spec_version`, `data`

### 4.2 `data` object (CCv2 fields)

Minimum fields for prompt-building:
- `name: string`
- `description: string`
- `personality: string`
- `scenario: string`
- `first_mes: string`
- `mes_example: string`

New CCv2 fields:
- `creator_notes: string` (creator → user notes)
- `system_prompt: string` (system/main prompt override; see defaults)
- `post_history_instructions: string` (post-history instruction block; see defaults)
- `alternate_greetings: string[]` (additional greeting options)
- `character_book: object` (lorebook embedded in card; treat as structured-but-forward-compatible)
- `tags: string[]`
- `creator: string`
- `character_version: string`
- `extensions: object` (application-defined storage; MUST preserve unknown fields)

### 4.3 `extensions` preservation

Importer MUST NOT delete unknown keys under `data.extensions`.
Exporter MUST write back preserved values.

This is required for cross-app interoperability.

### 4.3.1 Common SillyTavern `extensions` keys

SillyTavern (and other frontends) commonly store extra per-character metadata under `data.extensions`.
TavernKit always **preserves** these keys. In addition, TavernKit/Playground may interpret a few
well-known keys for ST parity:

- `data.extensions.talkativeness` (number|string):
  Per-character "chatty" probability used in group activation (ST `talkativeness_default = 0.5`).
  Playground follows ST's coercion rules (invalid/missing → default, JSON `null` → `0.0`).
- `data.extensions.world` (string):
  Character-bound **primary** World Info / lorebook name. Playground resolves this to a local
  lorebook (if present) and treats it like ST "Link to World Info" for prompt building and export.
- `data.extensions.fav` (boolean|string):
  Favorite flag. Pure metadata; host apps can use it for UI filtering/sorting.
- `data.extensions.depth_prompt` (object):
  Character Depth Prompt config (`{ prompt, depth, role }`). TavernKit uses this for macro expansion
  and depth injection (see `docs/TAVERNKIT_BEHAVIOR.md` for details).

### 4.4 `character_book` shape (minimal contract)

CCv2 defines a "character book" concept intended to coexist with global/world books.

Because different frontends evolve their lorebook formats, implementers SHOULD:
- support a minimal common subset, and
- preserve unknown fields for forward compatibility.

Minimal contract:
- `character_book.entries` MUST be an array if `character_book` is present.
- each entry SHOULD be an object containing:
  - `keys: string[]`
  - `content: string`
  - optional flags/metadata (`enabled`, ordering, etc.)
- unknown fields MUST be preserved.

> Recommendation from the CCv2 ecosystem:
> character book entries should be applied in addition to any active world book
> rather than replacing it.

## 5. Default semantics (prompt-building)

If these fields are absent or empty, applications may fall back to defaults:

- `system_prompt` default intent:
  A "you are {{char}}" style system instruction.

- `post_history_instructions` default intent:
  A "write the next reply of {{char}} in a fictional chat with {{user}}" style instruction.

Note: The exact default strings vary by frontend; you SHOULD treat defaults as configurable
in your own library (because SillyTavern exposes prompt editing).

## 6. Import/Export rules

### 6.1 Import (lenient)
- If `spec == "chara_card_v2"` and `data` exists: parse as CCv2.
- If `data` missing but legacy fields exist: import as "legacy card" and auto-upgrade into internal model.
- MUST preserve unknown fields:
  - root unknown fields
  - `data` unknown fields
  - `data.extensions` unknown fields
  - `data.character_book` unknown fields

### 6.2 Export (stable)
- When exporting CCv2, write canonical content into `data`.
- For backward compatibility, SHOULD also mirror core legacy fields (`name`, `description`, …) at the root.

## 7. Non-normative: PNG embedding

Many tools embed a base64 JSON payload inside PNG metadata.
If you implement PNG support:
- keep chunk identifiers configurable,
- validate base64 and JSON strictly,
- preserve original PNG bytes where possible.

## 8. Conformance checklist (summary)

An implementation is CCv2-conformant for this repo if it:
- parses `spec/spec_version/data`
- supports core prompt-building fields
- preserves unknown fields
- supports `extensions` as arbitrary JSON
