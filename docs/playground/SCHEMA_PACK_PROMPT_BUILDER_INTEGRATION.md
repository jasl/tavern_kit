# Schema Pack ↔ PromptBuilder 对接追踪

目标：确保 **Settings Schema Pack** 写入的配置（`Space.prompt_settings` / `SpaceMembership.settings`）能够实际影响 TavernKit 的 **PromptBuilder** 产物（最终 messages / plan）。

## 范围与入口

- Schema Pack（后端 bundle 输出）：`GET /schemas/conversation_settings`
- 配置落库：
  - Space：`spaces.prompt_settings`（以及少量 column，取决于 schema 的 `x-storage.kind`）
  - SpaceMembership：`space_memberships.settings`（目前主要用 `llm.*`）
- Prompt 构建入口：`playground/app/services/prompt_builder.rb`

## 已对接（当前生效）

### Space.prompt_settings → Prompt 内容

- `space.prompt_settings.scenario_override`  
  - 作用：覆盖所有角色的 `{{scenario}}` 内容（影响最终 prompt）  
  - 实现：`PromptBuilding::CharacterParticipantBuilder` 会把 `participant.data.scenario` 覆盖为该值（或在 group append 模式下参与 group card join）

### Space.prompt_settings.preset → TavernKit::Preset（影响 prompt 结构）

来源路径（schema pack）：`space.prompt_settings.preset` 下的键。

已映射（部分）：

- `preset.main_prompt` → `Preset.main_prompt`
- `preset.post_history_instructions` → `Preset.post_history_instructions`
- `preset.new_chat_prompt` → `Preset.new_chat_prompt`
- `preset.new_group_chat_prompt` → `Preset.new_group_chat_prompt`
- `preset.new_example_chat` → `Preset.new_example_chat`
- `preset.group_nudge_prompt` → `Preset.group_nudge_prompt`
- `preset.continue_nudge_prompt` → `Preset.continue_nudge_prompt`
- `preset.continue_prefill` → `Preset.continue_prefill`
- `preset.continue_postfix` → `Preset.continue_postfix`
- `preset.replace_empty_message` → `Preset.replace_empty_message`
- `preset.prefer_char_prompt` → `Preset.prefer_char_prompt`
- `preset.prefer_char_instructions` → `Preset.prefer_char_instructions`
- `preset.squash_system_messages` → `Preset.squash_system_messages`
- `preset.examples_behavior` → `Preset.examples_behavior`
- `preset.message_token_overhead` → `Preset.message_token_overhead`
- `preset.authors_note*` → `Preset.authors_note*`
- `preset.enhance_definitions` → `Preset.enhance_definitions`
- `preset.auxiliary_prompt` → `Preset.auxiliary_prompt`
- `preset.*_format` → `Preset.wi_format` / `Preset.scenario_format` / `Preset.personality_format`

### SpaceMembership.settings → Token 预算（影响 plan/trimming）

来源路径（schema pack）：

- `space_membership.settings["llm"]["providers"][provider_identification]["generation"]["max_context_tokens"]`
- `space_membership.settings["llm"]["providers"][provider_identification]["generation"]["max_response_tokens"]`

对接到 TavernKit：

- `max_context_tokens` → `TavernKit::Preset.context_window_tokens`
- `max_response_tokens` → `TavernKit::Preset.reserved_response_tokens`

说明：

- 这是 prompt 组装过程的一部分：`context_window_tokens` 会启用 TavernKit 的 trimming middleware，并在 `plan.trim_report` 里反映预算（即使无需裁剪也会记录 `max_tokens`）。
- 若 space_membership 未显式存储这些字段，PromptBuilder 会使用默认值（目前是 `8192/512`）以确保预算行为与 UI 默认一致。

### Space.prompt_settings → World Info（影响 lore 注入策略/预算）

对接键（schema pack `x-storage.path`）：

- `world_info_depth` → `Preset.world_info_depth`
- `world_info_include_names` → `Preset.world_info_include_names`
- `world_info_insertion_strategy` → `Preset.character_lore_insertion_strategy`
- `world_info_min_activations` → `Preset.world_info_min_activations`
- `world_info_min_activations_depth_max` → `Preset.world_info_min_activations_depth_max`
- `world_info_use_group_scoring` → `Preset.world_info_use_group_scoring`
- `world_info_budget`（百分比） → `Preset.world_info_budget`（tokens）
  - 换算：`floor((context_window_tokens - reserved_response_tokens) * percent / 100)`
- `world_info_budget_cap` → `Preset.world_info_budget_cap`
- `world_info_match_whole_words` / `world_info_case_sensitive` / `world_info_max_recursion_steps` → `TavernKit::Lore::Engine`（通过 `PromptBuilder` 传入 `lore_engine:`）
- `world_info_recursive` → 强制写入 lorebook 的 recursion flag（对 `character_book` / `lore_books` 统一生效）

说明：
- 覆盖逻辑集中在 `PromptBuilding::WorldInfoBookOverrides`，同时支持 Hash（character_book）与 `TavernKit::Lore::Book`（standalone lorebook）。
- TavernKit 的 Lore middleware 会对重复的 world info books 做去重（按 book raw 内容签名），避免重复评估/重复注入。

## provider_identification 来源（必须可追溯）

`provider_identification` 不落库在 schema pack 的 provider blocks 中，完全由：

`space_membership.llm_provider_id` → `space_membership.effective_llm_provider.identification`

实现位置：

- `playground/app/models/space_membership.rb`：`effective_llm_provider` / `provider_identification`
- `playground/app/models/llm_provider.rb`：`identification`

## 测试覆盖

- `playground/test/services/prompt_builder_test.rb`
  - space `scenario_override` 会进入最终 messages / character participant
  - space_membership generation token settings 会影响 `Preset.context_window_tokens` / `Preset.reserved_response_tokens`
  - space `world_info_budget`（百分比）会按 token 预算写入 `Preset.world_info_budget`

## 已知缺口 / TODO（不影响当前验收，但需要追踪）

- RAG / 知识库 / 记忆：schema 已保留入口但默认禁用，待实现后接入 PromptBuilder。
