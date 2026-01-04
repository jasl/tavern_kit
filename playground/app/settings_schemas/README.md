# Settings Schema Pack (v0.6)

This directory contains a modularized JSON Schema pack split by domain/module.

- `root.schema.json` is the entry schema.
- `defs/` contains shared and domain schemas.
- `providers/` contains per-provider LLM settings schemas.
- `manifest.json` lists all modules.

Notes:
- Provider selection is **not** stored in the schema. UI should derive `provider_identification` from `participant.llm_provider_id` and use `x-ui.visibleWhen.context == "provider_identification"` to gate provider-specific blocks.
- This pack uses external `$ref` across files; bundle/dereference before shipping to the browser if needed.
- This pack is intentionally **prompt-building focused** (no UI/TTS/image-generation settings).
