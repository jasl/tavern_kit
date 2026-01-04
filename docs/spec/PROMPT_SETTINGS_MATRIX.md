# Prompt Settings Matrix

Reference sources:
- SillyTavern (vendored): `tmp/SillyTavern`
- RisuAI (vendored): `tmp/Risuai`

Scope:
- This matrix tracks **settings that influence prompt building** in TavernKit Playground (Rails) and/or TavernKit.
- We intentionally **do not** aim for 1:1 compatibility with ST/Risu setting names or storage.

## 1. Space Settings (Prompt Builder)

| Setting (Space schema path) | Storage | Source | Status | Notes |
|---|---|---|---|---|
| `space.reply_order` | `spaces.reply_order` (column) | ST | ✅ | Affects speaker selection (`SpeakerSelector` / `Conversation::RunPlanner`). |
| `space.allow_self_responses` | `spaces.allow_self_responses` (column) | ST | ✅ | Used by auto-response scheduling (not TavernKit). |
| `space.card_handling_mode` | `spaces.card_handling_mode` (column) | ST | ✅ | Affects group prompt building (swap/join) via `PromptBuilder#effective_character_participant`. |
| `space.join_prefix` / `space.join_suffix` | `spaces.settings["join_prefix"]` / `spaces.settings["join_suffix"]` | ST | ✅ | Used by group join prompt assembly in `PromptBuilder`. |
| `space.scenario_override` | `spaces.settings["scenario_override"]` | ST | ✅ | Overrides `{{scenario}}` via `PromptBuilder#effective_character_participant`. |
| `space.preset.*` | `spaces.settings["preset"][...]` | ST/Risu | ✅ | Mapped into `TavernKit::Preset` in `PromptBuilder#effective_preset`. |
| `space.world_info.*` | `spaces.settings["world_info_*"]` | ST | ✅ | Mapped into `TavernKit::Preset` + `TavernKit::Lore::Engine` options. |

## 2. SpaceMembership Settings (Prompt Budget)

| Setting (SpaceMembership schema path) | Storage | Source | Status | Notes |
|---|---|---|---|---|
| `space_membership.llm.providers.*.generation.max_context_tokens` | `space_memberships.settings["llm"]["providers"][provider_identification]["generation"]["max_context_tokens"]` | ST/Risu | ✅ | Controls `Preset.context_window_tokens` (trimming budget). |
| `space_membership.llm.providers.*.generation.max_response_tokens` | `space_memberships.settings["llm"]["providers"][provider_identification]["generation"]["max_response_tokens"]` | ST/Risu | ✅ | Controls `Preset.reserved_response_tokens` (trimming budget). |

Provider selection is not stored in schema pack; it is derived from:
`space_membership.llm_provider_id → space_membership.effective_llm_provider.identification`.

## 3. Character Fields (Character Card)

| Setting (Character schema path) | Storage | Source | Status | Notes |
|---|---|---|---|---|
| `character.name` | `characters.data["name"]` | CCv2/CCv3 | ✅ | Used in macros and display. |
| `character.description` / `personality` / `scenario` | `characters.data[...]` | CCv2/CCv3 | ✅ | Used in prompt assembly. |
| `character.first_mes` / `alternate_greetings` / `mes_example` | `characters.data[...]` | CCv2/CCv3 | ✅ | Used for greeting/examples. |
| `character.system_prompt` / `post_history_instructions` | `characters.data[...]` | CCv2/CCv3 | ✅ | Used when `Preset.prefer_char_*` is enabled. |
| `character.depth_prompt` | `characters.data["depth_prompt"]` | ST/Risu | ✅ | Macro: `{{charDepthPrompt}}`. |
| `character.creator_notes` | `characters.data["creator_notes"]` | CCv2/CCv3 | ✅ | Macro: `{{creatorNotes}}`. |

## 4. Unsupported / Disabled (Planned)

| Setting | Source | Status | Notes |
|---|---|---|---|
| `space.memory.*` | ST/Risu | ⬜ (disabled in schema) | Memory injection (summary / vector memory) not implemented yet. |
| `space.rag.*` | ST/Risu | ⬜ (disabled in schema) | RAG / knowledge base retrieval not implemented yet. |
