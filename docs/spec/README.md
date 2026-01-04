# Interop Spec Notes (CCv2 / CCv3 / SillyTavern Prompt Behavior)

## 1. What is this?

This directory provides implementer-focused, testable notes for interoperability with:

- Character Card V2 (CCv2)
- Character Card V3 (CCv3)
- A subset of SillyTavern prompt-building behavior (macros, injections, world info, author's note, and RAG/Data Bank concepts)

For known, intentional (or currently unavoidable) behavior differences vs SillyTavern, see:
- `docs/spec/SILLYTAVERN_DIVERGENCES.md`

These documents are designed to be read by:
- humans implementing the library, and
- codegen agents (Codex/Copilot/etc.) implementing conformance checks.

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
| CCv3 parsing | ✅ Complete | Full spec support |
| Core macros | ✅ Complete | `{{char}}`, `{{user}}`, `{{persona}}`, `{{description}}`, etc. |
| `{{newline}}`, `{{trim}}`, `{{noop}}` | ✅ Complete | ST-compatible behavior |
| Extended macros | ✅ Complete | `{{charIfNotGroup}}`, `{{group}}`, `{{lastMessageId}}`, `{{idle_duration}}`, `{{banned "..."}}`, date/time/random/pick/roll, etc. |
| Prompt Manager | ✅ Complete | Entry ordering, in-chat injection |
| World Info | ✅ Complete | Keyword matching, positions, recursion |
| Author's Note | ✅ Complete | Frequency, depth injection |
| Data Bank (RAG) | ❌ Not implemented | Interface planned for Phase 4 |
