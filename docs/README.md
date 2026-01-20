# TavernKit Gem Documentation Index

> **Note**: For Playground (Rails app) documentation, see `../playground/docs/`

---

## Overview

This directory contains specification and design documents for the **TavernKit gem**.

TavernKit is a Ruby gem providing SillyTavern-compatible LLM prompt building. It offers the same powerful prompt engineering features as SillyTavern (Prompt Manager, World Info, macros, etc.) in a clean, idiomatic Ruby API.

**Start here:**
- `../README.md` — Project overview and quick start
- `../AGENTS.md` — AI agent guidelines (must-read for Claude/GPT)
- `../ARCHITECTURE.md` — Internal design and data flow

---

## Interop Spec Notes (CCv2 / CCv3 / SillyTavern Prompt Behavior)

### 1. What is this?

This directory provides implementer-focused, testable notes for interoperability with:

- Character Card V2 (CCv2)
- Character Card V3 (CCv3)
- A subset of SillyTavern prompt-building behavior (macros, injections, world info, author's note, and RAG/Data Bank concepts)

For known, intentional (or currently unavoidable) behavior differences vs SillyTavern, see:
- `docs/spec/SILLYTAVERN_DIVERGENCES.md`

These documents are designed to be read by:
- humans implementing the library, and
- codegen agents (Codex/etc.) implementing conformance checks.

## 2. Legal & licensing notes (important)

- This repository is MIT.
- SillyTavern is GPL/AGPL: do NOT copy its source code or documentation text into this repo.
- This documentation is written from scratch as "behavioral requirements for interoperability".
- Where upstream behavior is referenced, we link to upstream sources for verification.

## 3. Normative language

We use RFC-style keywords:
- MUST / MUST NOT
- SHOULD / SHOULD NOT
- MAY

When a section is labeled "Non-normative", it is informational and not required for conformance.

## 4. How to use these docs

1. Implement card parsing:
   - Parse CCv2 and CCv3 into your internal model.
   - Preserve unknown fields (forward compatibility).
2. Implement prompt building:
   - Implement macro replacement (case-insensitive; pass-based like ST, not a recursive macro parser).
   - Implement injection positions and depth semantics.
   - Implement optional features (World Info, Author's Note, Data Bank) behind interfaces.
3. Add conformance tests:
   - Use `docs/spec/fixtures/*` as test vectors.
   - Use `docs/spec/CONFORMANCE_RULES.yml` as machine-readable criteria.

## 5. References (upstream)

Put these links in your repo as *references only*:

- CCv2 spec repository:
  https://github.com/malfoyslastname/character-card-spec-v2

- CCv3 spec repository (proposal):
  https://github.com/kwaroran/character-card-spec-v3

- SillyTavern official docs (behavior descriptions):
  Prompt Manager:
  https://docs.sillytavern.app/usage/prompts/prompt-manager/

  Prompts overview:
  https://docs.sillytavern.app/usage/prompts/

  Macros:
  https://docs.sillytavern.app/usage/core-concepts/macros/

  World Info:
  https://docs.sillytavern.app/usage/core-concepts/worldinfo/

  Author's Note:
  https://docs.sillytavern.app/usage/core-concepts/authors-note/

  Data Bank (RAG):
  https://docs.sillytavern.app/usage/core-concepts/data-bank/

  Context Template (anchors & injection positions):
  https://docs.sillytavern.app/usage/prompts/context-template/

## 6. TavernKit Implementation Status

| Feature | Status | Notes |
|---------|--------|-------|
| CCv2 parsing | ✅ Complete | Full spec support |
| CCv3 parsing | ✅ Complete | Full spec support (see [CCv3_UNIMPLEMENTED.md](CCv3_UNIMPLEMENTED.md) for optional features) |
| Core macros | ✅ Complete | `{{char}}`, `{{user}}`, `{{persona}}`, `{{description}}`, etc. |
| `{{newline}}`, `{{trim}}`, `{{noop}}` | ✅ Complete | ST-compatible behavior |
| Extended macros | ✅ Complete | `{{charIfNotGroup}}`, `{{group}}`, `{{lastMessageId}}`, `{{idle_duration}}`, `{{banned "..."}}`, date/time/random/pick/roll, etc. |
| Prompt Manager | ✅ Complete | Entry ordering, in-chat injection |
| World Info | ✅ Complete | Keyword matching, positions, recursion |
| Author's Note | ✅ Complete | Frequency, depth injection |
| Data Bank (RAG) | ❌ Not implemented | Interface planned for Phase 4 |

---

## Document Index

### Character Card Specifications
- **[CHARACTER_CARD_V2.md](CHARACTER_CARD_V2.md)** — Character Card V2 specification
- **[CHARACTER_CARD_V3.md](CHARACTER_CARD_V3.md)** — Character Card V3 specification (extended)
- **[CCv3_UNIMPLEMENTED.md](CCv3_UNIMPLEMENTED.md)** — CCv3 features not yet implemented

### Behavior & Compatibility
- **[TAVERNKIT_BEHAVIOR.md](TAVERNKIT_BEHAVIOR.md)** — TavernKit behavior specification (SillyTavern compatible)
- **[CONFORMANCE_RULES.yml](CONFORMANCE_RULES.yml)** — Machine-readable conformance criteria
- **[SILLYTAVERN_DIVERGENCES.md](SILLYTAVERN_DIVERGENCES.md)** — Differences from SillyTavern behavior

### Feature Comparisons
- **[FEATURE_COMPARISON.md](FEATURE_COMPARISON.md)** — Feature comparison with other implementations
- **[COMPATIBILITY_MATRIX.md](COMPATIBILITY_MATRIX.md)** — Compatibility matrix across versions

### Prompt Engineering
- **[PROMPT_SETTINGS_MATRIX.md](PROMPT_SETTINGS_MATRIX.md)** — Prompt settings and their effects
- **[MACROS_2_ENGINE.md](MACROS_2_ENGINE.md)** — Macros 2 engine specification

### Development Planning
- **[ROADMAP.md](ROADMAP.md)** — Development roadmap and phases

### Test Fixtures
- **[fixtures/](fixtures/)** — Test fixtures for character cards, prompts, etc.

---

## Quick Reference

### Character Card Format

**V2 Structure:**
```json
{
  "spec": "chara_card_v2",
  "spec_version": "2.0",
  "data": {
    "name": "Character Name",
    "description": "Character description",
    "personality": "Personality traits",
    "scenario": "Scenario description",
    "first_mes": "First message",
    "mes_example": "Example dialogue"
  }
}
```

**V3 Extensions:**
- Multiple greetings (`alternate_greetings`)
- Character book (world info)
- Advanced prompt options
- Asset references

### Macro Syntax

Common macros:
- `{{char}}` — Character name
- `{{user}}` — User name
- `{{original}}` — Original content (in prompt overrides)
- `{{random::option1::option2}}` — Random selection
- `{{roll:1d20}}` — Dice roll

### Conformance Testing

Run conformance tests:
```bash
bundle exec rake test:conformance
```

---

## Contributing to Docs

When adding new documentation:

1. Add entry to this README.md
2. Follow existing document structure
3. Include code examples
4. Link to related documents
5. Update `../AGENTS.md` if adding critical patterns
6. Add test fixtures if documenting formats

---

## External References

- **SillyTavern**: https://github.com/SillyTavern/SillyTavern
- **SillyTavern Docs**: https://docs.sillytavern.app/
- **Character Card Spec**: https://github.com/malfoyslastname/character-card-spec-v2
- **Playground Docs**: `../playground/docs/` (Rails app documentation)
