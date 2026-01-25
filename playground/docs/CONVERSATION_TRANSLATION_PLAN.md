# Conversation 翻译支持：调研评估与实施计划（Playground）

目标：在 `playground/` 的 Rails 应用中，为 **Conversation** 引入可配置、可扩展的翻译能力，优先对齐 SillyTavern / RisuAI 的成熟交互，并吸收 LinguaGacha / AiNiee 的工程化翻译经验。

本文档处于“方案调研 → 制定计划”阶段：重点给出**关键设计取舍**、**落点位置**、**分阶段 Roadmap + 验收**，便于后续按阶段实现。

---

## 0. 范围与目标（明确边界）

### 0.1 需要支持的三种模式（对外行为）

- **Off**：不进行任何翻译。
- **Translate both（ST 风格）**：
  - UI 展示目标语言（例如 zh-CN）
  - Prompt / 内部上下文使用内部语言（建议默认 en）
  - 输入（user）与输出（assistant）均自动翻译
  - 支持单条消息翻译 toggle、Clear Translations（清除译文但保留原文/内部文本）、缓存、分段、格式保真
- **Native**：不走翻译服务，通过 prompt 约束让模型直接用目标语言输出（保持现有 streaming 体验）。
- **Hybrid**：Native 优先 + 语言检测兜底（必要时翻译/改写），目标是“自动最佳效果”。

### 0.2 非目标（本期不做 / 延后）

- 不做全站 UI 国际化（Rails `I18n.t` 的界面语言切换不是本任务重点）。
- 不追求流式翻译（streaming 过程中实时翻译）作为 MVP；先做**生成完成后翻译并替换显示**。
- 不把外部翻译 API（DeepL/Google/Bing）作为首要依赖；优先复用现有 `LLMClient` 能力（在 Job 内非流式调用）。

---

## 1. 对 GPT 初步报告的评估（保留 / 修正）

### 1.1 报告的高价值点（建议采纳）

- **Canonical / Display 分离**：是三种模式统一落地的关键。
- **Mask/Unmask + 校验 + Repair**：角色扮演文本翻译要稳定，必须工程化保护格式与占位符。
- **Chunking + Cache**：控制成本与失败率的核心；对齐 ST 翻译扩展的做法。
- **“命中才注入”的 Glossary/NTL 思路**：吸收 AiNiee 的经验，减少 prompt 噪声与 token 成本。
- **UI 交互对齐 ST**：单条消息翻译按钮、清除翻译、输入/输出/both 模式的语义清晰。

### 1.2 需要修正/补充的点（结合 Playground 实际架构）

1) **`Message` 存储与 UI/Prompt 的耦合比报告假设更强**  
Playground 的消息渲染与 streaming 依赖 `message.content`（见 `playground/app/views/messages/_message.html.erb`），且 `Message`/`MessageSwipe` 使用 COW（TextContent）存储策略（见 `playground/app/models/message.rb` / `playground/app/models/message_swipe.rb`）。  
因此，“把 `messages.content` 永远当 canonical”的方案会牵动：

- UI 默认展示逻辑（尤其是 sender 自己发的消息）
- 预览/列表（`Space.with_last_message_preview` 直接 select `messages.content`）
- 编辑/分支/复制（内容与 swipes 同步规则）

1) **Swipe（多版本 AI 回复）需要“每个 swipe 单独翻译”**  
Playground 的 regenerate 产物是 `MessageSwipe`（`message_swipes.metadata` 独立存在，见 `playground/db/schema.rb`），而 UI 展示的是“当前 active swipe 对应的内容”。  
因此翻译结果不能只挂在 `Message.metadata`（否则切换 swipe 时译文错位），应考虑将译文挂在：

- `MessageSwipe.metadata["i18n"]`（推荐），或
- 以 `content_sha256` 为 key 的翻译缓存（更通用但实现复杂）。

1) **Space 层设置已经有乐观锁与更新入口**  
Space 使用 `settings_version` 作为 optimistic lock（`playground/app/models/space.rb`），目前 “Chat tab” 下的空间设置是 `PlaygroundsController#update` 的表单提交（`playground/app/views/conversations/_right_sidebar.html.erb`）。  
若要做 schema-driven 的 Space prompt_settings 自动保存，确实可以新增类似 `SpaceMemberships::SettingsPatch` 的 JSON patch，但这属于“UI 工程”工作量，需要明确分期。

---

## 2. 面向 Playground 的推荐设计（落点清晰）

### 2.1 Settings：把翻译设置放到哪里？

**推荐**：作为 `Space.prompt_settings` 的一个 nested schema：`ConversationSettings::I18nSettings`（示例字段见 2.2）。  
理由：

- 翻译策略直接影响 PromptBuilder/ContextBuilder 的输入输出，是“prompt building 相关设置”。
- Space 是对话容器（“chat”语义），与 ST“翻译设置按 chat 生效”一致。

落点：

- `playground/app/models/conversation_settings/i18n_settings.rb`（新增）
- `playground/app/models/conversation_settings/space_settings.rb`（新增 nested schema：`i18n:`）
- `GET /schemas/conversation_settings` 的 schema bundle 会自动包含（现有 schema pack 体系）

### 2.2 Space.prompt_settings.i18n：建议字段（MVP → 可演进）

（字段命名以 Ruby idiom + schema pack 风格为准，最终可调整）

- `mode`: `"off" | "translate_both" | "native" | "hybrid"`
- `internal_lang`: `"en"`（默认）
- `target_lang`: `"zh-CN"`（默认可由 UI 选择）
- `source_lang`: `"auto" | "en" | "zh-CN"`（MVP 先 `auto`）
- `auto_vibe_target_lang`: `true|false`（默认 `true`；仅当 mode != off 且 target_lang != internal_lang 时生效，用于 Auto/Vibe 生成目标语言内容）
- `provider`：
  - `kind`: `"llm"`（MVP 先做）
  - `llm_provider_id`: 复用现有 `LLMProvider`（可选：允许单独指定“翻译专用 provider”）
  - `model_override`: 可选
- `prompt_preset`: `"strict_roleplay_v1"`（可扩展为多 preset）
- `masking`：
  - `enabled`、`protect_code_blocks`、`protect_inline_code`、`protect_urls`、`protect_handlebars` 等
- `chunking`：
  - `max_chars`（默认 1500~2000）
- `cache`：
  - `enabled`、`ttl_seconds`、`scope`（`"message" | "conversation" | "global"`）
- `glossary` / `ntl`：
  - `enabled`
  - `entries_json`（MVP 用 textarea JSON，后续再做表格编辑/导入导出）

说明（重要）：

- `internal_lang` 是 **Space 级 canonical/prompt 语言**（ST 经验默认 `en`）。MVP 暂不开放 UI 修改，但应作为字段持久存在，便于未来支持非 `en`。
- 当 `internal_lang == target_lang` 时，翻译应视为 **no-op**：不要 enqueue 翻译任务、不要写入 `translation_pending`，按钮可提示 “nothing to translate”。

### 2.3 Message/Swipe 的 i18n metadata 结构（建议）

目标：既能支持 ST 风格 toggle，也能保证 regenerate/swipe 不错位。

**建议：**

- user 消息：写入 `Message.metadata["i18n"]`
- assistant 消息：写入 `MessageSwipe.metadata["i18n"]`（active swipe 决定显示）

推荐结构（示例）：

```json
{
  "i18n": {
    "internal_lang": "en",
    "target_lang": "zh-CN",
    "canonical": "Hello, ...",          // 仅当 content=display 时需要（推荐 content 保持 display）
    "translations": {
      "zh-CN": {
        "text": "你好，…",
        "provider": "llm",
        "provider_id": 12,
        "model": "gpt-4.1-mini",
        "input_sha256": "…",
        "settings_sha256": "…",
        "created_at": "2026-01-23T00:00:00Z"
      }
    },
    "last_error": {
      "code": "mask_mismatch",
      "message": "…"
    }
  }
}
```

说明：

- `input_sha256/settings_sha256` 用于“内容或配置变化时自动失效”的判断。
- `canonical` vs `content` 的取舍见 2.4。

### 2.4 Canonical/Display：推荐在 Playground 里如何落库？

这里是最大设计取舍。结合 Playground 当前实现（UI 直接渲染 `message.content`、Inline Edit 不允许在 Controller 同步调用 LLM、且 assistant 可能出现 swipes），本文档推荐的 MVP 策略是：

**推荐方案（MVP，兼顾“ST 对齐”与“编辑不依赖 LLM”）：按 role 做不对称存储**  

- **user 消息**：
  - `Message.content`：保持用户原始输入（Display）
  - `Message.metadata["i18n"]["canonical"]`：存 internal（en）译文（用于 prompt）
- **assistant 消息**：
  - `Message.content`：保持模型原始输出（Canonical，通常为 internal=en）
  - `Message.metadata["i18n"]["translations"][target_lang]`：存 Display 译文（UI 默认展示）
  - 若/当出现 swipes：优先把译文写到 `active_message_swipe.metadata["i18n"]`，并以 swipe 为准（避免切换 swipe 时译文错位）

PromptBuilder 需要做一次集中适配：

- `PromptBuilding::MessageHistory#convert_message`（`playground/app/services/prompt_building/message_history.rb`）改为使用一个统一的 `prompt_text_for(message, space_settings:)` 规则：
  - Translate both/Hybrid 且 `message.user?`：优先用 `metadata.i18n.canonical`
  - 其他情况：用 `message.content`

说明：

- 这个不对称策略与 ST 的实际行为很接近：incoming（assistant）保留原文，display 存额外字段；outgoing（user）则需要额外保存“发送前/翻译前”的文本（ST 用 `extra.display_text`，我们用 `metadata.i18n`）。
- 后续若想进一步对齐 ST（“content 永远 canonical”），可以在不破坏接口的前提下做迁移；但 MVP 不建议让 Inline Edit 依赖后台翻译回写。

---

## 3. 翻译子系统（后端）：服务拆分与接口草案

### 3.1 目录与命名（避免与 Rails I18n 混淆）

建议使用 `Translation` 或 `MessageTranslation` 命名空间（不要叫 `I18n`）。

候选目录：

- `playground/app/services/translation/*`

### 3.2 核心对象

- `Translation::Request`：text、source_lang、target_lang、mode、provider、preset、masking、glossary/ntl、chunking、context（可选）
- `Translation::Result`：translated_text、detected_lang、cache_hit、chunks、warnings、provider_meta
- `Translation::Service`：唯一入口（内部 orchestrate mask/chunk/cache/provider/extract/validate）
- `Translation::Providers::LLM`：复用现有 LLMClient（非流式）
- `Translation::Masker`：mask/unmask + 校验（参考 AiNiee 的“代码段/占位符处理 + 行结构保留”）
- `Translation::Chunker`：按行/段落切分，优先保证 markdown/代码块不被拆（参考 ST 对 provider 字符上限的 chunkedTranslate）
- `Translation::Cache`：
  - message-level（持久化到 metadata）
  - global-level（`Rails.cache` / SolidCache；key 需 versioned + digest 全量覆盖配置）
- `Translation::Extractor`：要求输出契约（建议 `<textarea>…</textarea>`）并只提取正文（参考 AiNiee 的 ResponseExtractor）
- `Translation::Repair`：mask mismatch / 提取失败时的二次提示词重试（限次），失败则返回原文并记录 error

### 3.3 Cache key（建议）

关键原则：任何可能影响输出的配置都进入 key，且版本化。

示例（按 chunk 缓存）：

```
tx:v1:
  provider=llm:
  provider_id=12:
  model=default:
  sl=auto:
  tl=zh-CN:
  preset_sha=...:
  masking_sha=...:
  glossary_sha=...:
  ntl_sha=...:
  text_sha=sha256(masked_chunk)
```

### 3.4 TranslationRun（像 ConversationRun 一样可追踪）

现状：当前翻译只落在 `Message/MessageSwipe.metadata["i18n"]`（`translation_pending/last_error/translations`），没有一个“可查询的任务记录”，因此无法像 `ConversationRun` 一样集中追踪和可视化（队列/耗时/失败原因/进度）。

建议引入一个专用的执行记录：`TranslationRun`（名字可调整，例如 `MessageTranslationRun`），用于承载：

- 翻译请求的生命周期：queued → running → succeeded/failed/canceled/skipped
- 幂等/去重信息：`input_sha256/settings_sha256/target_lang`
- 进度：`chunks_total/chunks_done`、`repair_attempts`
- 可观测性：provider/model、usage、错误码、耗时
- 取消语义：Clear translations / mode=off 后可标记 canceled，并让 job 早退

推荐字段（草案）：

- 关联：
  - `space_id`, `conversation_id`
  - `target_type`, `target_id`（polymorphic，支持 `Message` / `MessageSwipe`；后续可扩展到“翻译 prompt component”）
- 配置与幂等：
  - `mode`（translate_both/native/hybrid）、`source_lang`, `target_lang`, `internal_lang`
  - `provider_kind`, `llm_provider_id`, `model`
  - `input_sha256`, `settings_sha256`
- 状态与进度：
  - `status`（queued/running/succeeded/failed/canceled/skipped）
  - `queued_at`, `started_at`, `finished_at`
  - `chunks_total`, `chunks_done`
  - `attempts`, `repair_attempts`
  - `error`（json：code/message）
  - `debug`（json：mask mismatch 统计、cache hit、warnings 等）

写入策略（与现有 metadata 并存）：

- 翻译结果仍然写回 `Message/MessageSwipe.metadata["i18n"]["translations"][target_lang]`（这是 UI 展示与导出需要的长期数据）。
- `TranslationRun` 负责“过程与可视化”；`translation_pending` 可逐步过渡为由 `TranslationRun.status` 推导（MVP 可先双写，避免一次性改动太大）。

#### 3.4.1 Event（建议）

为了与现有 Runs/TurnScheduler 的可观测性一致，建议为 TranslationRun 增加 domain events（落在 `conversation_events`）：

- `translation_run.queued`
- `translation_run.started`
- `translation_run.progress`（可选：chunk 完成时；注意 event 数量与成本）
- `translation_run.succeeded`
- `translation_run.failed`
- `translation_run.canceled`

建议 payload 统一带上：

- `translation_run_id`
- `target_type/target_id`（message/swipe）
- `source_lang/target_lang/internal_lang`
- `provider_id/model`
- `input_sha256/settings_sha256`
- `chunks_total/chunks_done`
- `error.code/error.message`（失败时）

UI 上可在 Conversation 的 “Runs / Events” 面板新增一个 scope：Translation，或在现有 Events panel 中按前缀归类展示。

---

## 4. 集成点（Playground 现有执行链路）

Playground 的 LLM 调用发生在 `ActiveJob` 内（`ConversationRunJob` → `Conversations::RunExecutor`），符合“异步 IO 强制约束”。

### 4.1 输入翻译（user → internal）建议落点

触发点：`Conversations::RunExecutor` 在 `ContextBuilder#build` 之前。

做法（推荐）：

- 找到本次 run 依赖的“尾部 user 消息”（或 prompt scope 内需要 canonical 的 user 消息）
- 若 `space.prompt_settings.i18n.mode` 为 `translate_both`/`hybrid` 且需要：
  - 同步翻译到 internal（en）
  - 写入 `Message.metadata["i18n"]["canonical"]`（不改 `content`）
  - 记录 `input_sha256/settings_sha256`，避免重复翻译

注意：

- 这里的翻译必须发生在 Job 内（RunExecutor 本身在 Job 内，因此 OK）。
- 要考虑 `during_generation_user_input_policy` 与 queued/run cancel 语义：翻译不应创建新的 message，避免影响 TurnScheduler。

### 4.2 输出翻译（internal → display）建议落点

触发点：`Conversations::RunExecutor` 完成 `persist_response_message!` 之后。

做法（MVP 推荐：异步 job，不影响 run 成功与调度）：

- `RunExecutor` 在生成消息/新增 swipe 后：
  - 若空间处于 `translate_both`/`hybrid` 且 `target_lang != internal_lang`：
    - enqueue 一个翻译 job（例如 `TranslateMessageJob` / `TranslateMessageSwipeJob`）
    - job 内调用 `Translation::Service` 翻译 `canonical_text` → `target_lang`
    - 成功后将结果写回：
      - 若 `message.active_message_swipe` 存在：写 `MessageSwipe.metadata["i18n"]["translations"][target_lang]`
      - 否则：写 `Message.metadata["i18n"]["translations"][target_lang]`
    - 广播更新（Turbo Streams `broadcast_update`），让 UI 替换展示

注意：

- 翻译失败 **不能** 让 `ConversationRun` 失败；失败仅记录在 metadata，并让 UI 退回显示 canonical（`content`）。
- 由于 Playground “无 placeholder message”，异步翻译意味着用户会先看到英文回复，再在译文完成后替换；MVP 可接受，并可在 UI 上加一个轻量状态（“Translating…” badge）。

### 4.3 PromptBuilder 适配点（内部文本选择）

需要集中改造的唯一入口：`PromptBuilding::MessageHistory#convert_message`（`playground/app/services/prompt_building/message_history.rb`）。

建议新增一个小 helper（放在 MessageHistory 内部或独立模块）：

- 输入：`message`, `space.prompt_settings.i18n`
- 输出：用于 prompt 的文本（canonical）

规则（MVP）：

- `mode == "translate_both"`：
  - user：用 `metadata.i18n.canonical`（若缺失则 fallback `content`）
  - assistant/system：用 `content`
- `mode == "native"`：
  - 全部用 `content`（因为不强制 internal=en）
- `mode == "hybrid"`：
  - v1 可以先沿用 translate_both 的 internal=en 规则（先做稳定闭环）
  - v2 再实现“native 生成 + 检测 + rewrite”的复杂策略

### 4.4 UI 集成点（Conversation 页）

#### 4.4.1 右侧栏：新增 “Language / Translation” 面板

位置：`playground/app/views/conversations/_right_sidebar.html.erb` 的 “Chat Tab - Space-level settings” 内。

MVP 交互：

- mode（Off / Translate both / Native / Hybrid）
- target_lang（下拉）
- provider（先只暴露 “LLM”，并选择一个 `LLMProvider` 作为翻译专用 provider，可选）
- Clear translations（对当前 conversation 或当前 space 的 scope 先选一个）

存储：

- Space 层：写入 `space.prompt_settings.i18n.*`（schema pack）

#### 4.4.2 Message 展示：按模式优先显示译文

位置：`playground/app/views/messages/_message.html.erb`（以及 `_message_content.html.erb` 如有）。

约束：为了 streaming，`<template data-markdown-target="content">` 与 output 容器必须永远存在。  
实现建议：

- 抽一个 helper：`message_display_text(message, space:)`：
  - translate_both/hybrid：优先用 i18n translations[target_lang]（若存在），否则 `message.content`
  - native/off：用 `message.content`
- 在 `<template data-markdown-target="content">` 中写入 display_text，而不是直接 `message.content`。
- 为“toggle 回原文”预留 data attribute（例如 `data-original-text` / `data-translated-text`），由 Stimulus 切换。

### 4.5 Message actions：单条消息翻译 / toggle

位置：`message-actions` Stimulus controller + `_message.html.erb` 的 action bar。

MVP 行为：

- **toggle**：若译文已存在，则前端直接切换显示（无需请求）。
- **translate now**：若译文不存在，点击触发 `POST /messages/:id/translate`（或 nested route），仅 enqueue job，完成后 broadcast update。

注意：

- assistant 若已有 swipes：翻译应作用于 active swipe（或者明确让用户选择翻译哪个 swipe；MVP 可先翻译 active）。
- user 消息可选支持 “显示 canonical” toggle（因为我们存了 `metadata.i18n.canonical`）。

### 4.6 Clear Translations

MVP 先做 “当前 conversation 清除译文”：

- 遍历 `conversation.messages`：
  - 清空 `metadata.i18n.translations`（不删 `metadata.i18n.canonical`，否则会破坏 internal prompt）
  - 若存在 swipes：清空 `message_swipes.metadata.i18n.translations`
- broadcast 批量更新（或让用户刷新，MVP 二选一）

后续可扩展：

- scope=space：清空整个 space 的所有 conversations（成本高，谨慎）
- 支持只清空某个 `target_lang`

---

## 5. Roadmap（按阶段可验收）

### Milestone 1（开始阶段）：Translate both 输出翻译闭环（Phase 0 + Phase 1）

目标：把 “ST 风格 Translate both” 的 **输出翻译** 做成可用闭环（可开关、可展示、可清除、可按 swipe 生效），不引入输入侧 canonical（留到 Phase 2）。

#### 工作清单（按落点拆分）

- **Space 设置（Schema + UI）**
  - [x] 新增 `ConversationSettings::I18nSettings` 并挂到 `ConversationSettings::SpaceSettings`（`space.prompt_settings.i18n`）
  - [x] 设定默认值（MVP）：
    - `mode="off"`（默认不改变现有体验；需要手动开启 Translate both）
    - `internal_lang="en"`（先固定）
    - `target_lang="zh-CN"`（可改）
    - `auto_vibe_target_lang=true`（默认开启；仅当 mode != off 且 target_lang != internal_lang 时生效）
    - `provider.kind="llm"`（先只做 LLM）
    - `chunking.max_chars`、`cache.enabled` 等（按默认）
  - [x] 扩展 `PlaygroundsController#playground_params`，允许提交 `prompt_settings: { i18n: ... }`
  - [x] Conversation 右侧栏 Chat tab 增加 Language/Translation 面板（先用普通 `PATCH /playgrounds/:id` 表单提交）

- **翻译服务（后端最小闭环，LLM-only）**
  - [x] 新增 `Translation::Service` + `Request/Result`（`playground/app/services/translation/*`）
  - [x] Provider：`Translation::Providers::LLM`（非流式，Job 内调用）
  - [x] Mask/Unmask（最小集合）：code fence、inline code、URL、`{{...}}`（并做 token 完整性校验）
  - [x] Extractor：要求 `<textarea>...</textarea>` 输出契约（提取失败时可做 1 次 repair 重试）
  - [x] Chunker：按 `max_chars` 分段（先保证不拆 code fence；其余可先粗分）
  - [x] Cache：`Rails.cache`（versioned key + digest 覆盖配置；同时把最终译文落到 message metadata）

- **Job + 持久化（不影响 ConversationRun 成功）**
  - [x] `MessageTranslationJob`（一个 job 支持 Message/Swipe）
  - [x] 只翻译 assistant 输出（M1），写入：
    - 有 active swipe：`MessageSwipe.metadata["i18n"]["translations"][target_lang]`
    - 否则：`Message.metadata["i18n"]["translations"][target_lang]`
  - [x] 翻译失败不 raise 到上层：记录 `i18n.last_error`，UI 回退显示原文
  - [x] 更新后 `broadcast_update`（让 Turbo 替换内容）

- **RunExecutor 接入（enqueue 翻译 job）**
  - [x] 在 `RunPersistence#create_final_message` / `#add_swipe_to_target_message!` 完成后 enqueue 翻译 job
  - [x] Gate 条件：`space.prompt_settings.i18n.mode == "translate_both"` 且 `target_lang != internal_lang`
  - [x] 对齐 ST：`FirstMessagesCreator` 创建的 `first_mes` 也应自动 enqueue 翻译 job（避免“首条不翻译、regen 才翻译”的割裂体验）

- **UI 展示（默认展示译文）**
  - [x] 增加 `message_display_text(message, space:)`（helper）：译文存在则用译文，否则 `message.content`
  - [x] `_message.html.erb` 中 `<template data-markdown-target="content">` 渲染 display_text（保持 streaming 结构不变）
  - [x]（可选）显示 “Translating…” / “Translation failed” 的轻量状态

- **交互（可清除、可单条触发）**
  - [x] 单条消息 translate/toggle（先对 assistant）：无译文则触发 job，有译文则前端 toggle
  - [x] Clear translations（conversation scope）：清空 `translations[target_lang]`（保留 user 的 `i18n.canonical` 不动）

#### Definition of Done（阶段验收）

- `mode=translate_both` 时，新生成的 assistant 消息能自动得到译文（允许先显示原文→后替换译文）。
- regenerate 产生 swipe 时，译文与 active swipe 对齐（切换 swipe 不串）。
- Clear translations 后消息恢复显示原文，但不破坏后续生成。
- 翻译失败不会导致 run 失败或调度卡死，仅在 metadata 记录错误。
- `cd playground && bin/ci` 通过，且无新增 warnings。

#### Milestone 1.1（建议补强）：解决“第一眼体验”割裂与工程边界

这部分来自对 ST/RisuAI 行为与 Playground 现状的对齐评估，属于 **M1 之后立刻值得做的小补强**（不改变大架构，但能显著减少用户困惑）。

- **列表预览一致性（必须）**
  - 问题：`Space/Conversation.with_last_message_preview` 仅选取 `messages.content`，在 Translate both 下 assistant 的 content 多为 canonical（英文），导致“列表预览是英文、对话里是译文”的割裂。
  - 方案（推荐优先级从高到低）：
    1) 让 preview 查询同时拿到 last message 的 `role + metadata + active_message_swipe_id + swipe.metadata`，在 view/helper 层用同一套 `message_display_text` 规则生成 preview。
    2) 新增并维护一个 `spaces.last_message_preview_display`（或类似字段）在翻译完成时同步更新（避免 view 层额外逻辑，但需要 migration/回填）。
    3) SQL 级 `COALESCE(jsonb_extract_path_text(...), messages.content)`（实现复杂，且 target_lang 为动态 key）。

- **翻译进行中状态（建议）**
  - MVP 是异步翻译（先显示原文→后替换译文），建议提供一个最小状态：
    - “Translating…”（例如在 message header 或 action icon 上标记）
    - “Translation failed”（已有 last_error 可展示）
  - 推荐做法：enqueue job 时写 `metadata.i18n.translation_pending[target_lang]=true`，job 完成/失败时清除并写入结果/last_error。

- **Job 幂等与去重（建议）**
  - 同一条消息可能同时被 “自动 enqueue” 与 “手动点击翻译” 触发；此外用户切换设置也可能导致短时间重复 enqueue。
  - 规则建议：
    - job 开始时先基于 `input_sha256/settings_sha256/target_lang` 判断是否已是最新结果，是则 no-op。
    - cache 层仍保留（跨消息复用、降低成本）。

- **Extractor / 输出契约的鲁棒性（建议）**
  - 目前采用 `<textarea>…</textarea>` 输出契约 + 失败时 repair 重试。
  - 建议在 Extractor 中增加可控的 fallback：
    - 优先 textarea；
    - 其次 fenced code block（只取第一个 code block 内容）；
    - 最后在满足“没有多余前后缀且占位符校验通过”的前提下接受纯文本。
  - 目的：减少“模型轻微不遵循格式”导致的硬失败。
  - 备注：已纳入 Phase 2.0（翻译服务补强）

- **Masker：Handlebars/Curly Braced Syntaxes（建议）**
  - MVP 已保护 `{{...}}`，但生态里常见 `{{#...}}...{{/...}}` block 结构与更复杂嵌套。
  - 建议增加更高优先级的 block 级 mask（先整体保护，再保护单行 token），避免翻译破坏闭合结构。
  - 备注：已纳入 Phase 2.0（翻译服务补强）

- **Provider 语言代码映射（后续外部翻译 provider 前必须）**
  - 当接入 DeepL/Google/Bing 等外部 API 时，需要 provider-specific language code 映射（尤其是 `zh-CN/zh-TW`）。
  - 建议抽象 `Translation::LanguageCodeMapper.map(provider_kind, lang_code)` 并加单测覆盖。
  - 备注：已纳入 Phase 2.0（外部 provider 落地前完成）

### Phase 0：方案落地前置（Schema + UI 最小入口）

- [x] 新增 `ConversationSettings::I18nSettings` 并挂到 `ConversationSettings::SpaceSettings`（nested schema）
- [x] 在 Conversation 右侧栏 Chat tab 增加 Language/Translation 面板（先用普通表单 patch Space）
- [x] 约定 i18n metadata 结构（Message / MessageSwipe）并写入本文档的“准规范”

验收：

- Space 能保存 `prompt_settings.i18n.mode/target_lang`

### Phase 1：Translate both MVP（先做“输出翻译 + 展示”）

- [x] `Translation::Service`（LLM provider + masker + extractor + cache 的最小闭环）
- [x] `MessageTranslationJob`：assistant 输出翻译写入 metadata，并 broadcast update
- [x] Message 渲染优先显示译文（缺失则显示原文）
- [x] 单条消息 “Translate/toggle” 按钮（先只对 assistant）
- [x] Clear translations（conversation scope）

验收：

- assistant 回复在生成完成后自动出现译文（或“翻译中”→译文）
- 点击按钮可在译文/原文间切换；Clear translations 后回到原文

### Phase 2：输入翻译（user → internal）+ PromptBuilder 内部语言一致性

- **Phase 2.0：翻译服务补强（为输入侧稳定性做准备）**
  - [x] Extractor fallback：优先 `<textarea>`，其次 fenced code block，最后在校验通过时接受纯文本（避免“轻微不遵循”导致硬失败）
  - [x] Masker 支持 Curly Braced Syntaxes block（`{{#...}}...{{/...}}`）整体保护（MVP：不保证嵌套）
  - [x] Provider language code mapper（外部翻译 provider 用）：`Translation::LanguageCodeMapper.map(provider_kind, lang_code)`（至少覆盖 `zh-CN/zh-TW`）

  - **Phase 2.0.1：翻译服务 hardening（降低格式破坏与翻译污染）**
    - [x] Masker：Handlebars block 支持嵌套（`{{#if}}...{{#if}}...{{/if}}...{{/if}}`）并确保整体作为一个 token（补测试）

- [x] RunExecutor 在 build prompt 前确保 user canonical（写入 `metadata.i18n.canonical`）
- [x] `PromptBuilding::MessageHistory` 使用 canonical（Translate both 模式下）
- [x] 增加最小语言检测（heuristic：CJK 占比），避免对英文重复翻译
- [x] Auto/Vibe in target language：新增 `auto_vibe_target_lang` 开关（默认开启），在 impersonation prompt 末尾追加 `Respond strictly in #{target_lang}.`（仅当 mode != off 且 target_lang != internal_lang 时生效）

验收：

- 用户用中文输入，最终 prompt 中 user 内容为英文；assistant 输出仍能正常翻译展示

### Phase 3：Native 模式（保持 streaming）

- [ ] PromptBuilder 注入 Language Guard（system 或 injection registry）
- [ ] UI：mode=native 时隐藏/禁用翻译 provider 相关项，保留 target_lang
- [ ] 说明：Native 不需要“自动翻译”，但 **TranslationRun 概念仍保留**（用于手动翻译按钮、或未来“翻译 prompt components”增强项）

验收：

- native 模式下，模型输出大概率为目标语言且全程 streaming

### Phase 4：Hybrid（检测 + rewrite 兜底）

- [ ] `LanguageDetector`（heuristic → 可选 cld3）
- [ ] 生成完成后检测：若输出偏离目标语言，触发 rewrite translator（写入 display translations）
- [ ] 说明：Hybrid 的 rewrite/translate fallback 本质上仍是翻译任务，因此 **继续使用 TranslationRun** 追踪每次 rewrite/translate 的结果、耗时、失败原因与修复次数

验收：

- 模型偶尔跑英文时，最终展示仍为目标语言（保格式）

### Phase 5：工程化增强（质量与可调优）

- [ ] Glossary/NTL：命中才注入 + UI 编辑（先 JSON，后表格）
- [ ] Prompt presets：strict/roleplay/repair 多套模板可编辑
- [ ] 可观测性：translation cache hit、chunks、repair 次数、失败原因写入 debug/metadata

- **Phase 5.1：外部翻译 Provider（非 LLM）**

目标：引入 “Bing / DeepL / Google / LibreTranslate / Lingva”等外部翻译能力，用于 Translate both（或后续 Hybrid），并保持与现有 `Translation::Service` 的 mask/chunk/cache/repair 机制一致。

> 备注：本阶段不要求一次性支持所有 provider；建议按 “Microsoft/Bing → DeepL → 其他” 逐个落地。

#### 5.1.0 Provider 配置与 Schema（必要前置）

- [ ] 扩展 `ConversationSettings::I18nProviderSettings.kind`：
  - 从 `llm` 扩展为：`llm | microsoft | deepl | google | libretranslate | lingva`
- [ ] 为外部 provider 增加最小必要字段（按 provider 分组显示/校验）：
  - Microsoft/Bing：`endpoint`、`api_key`、`region`（如需要）
  - DeepL：`endpoint`、`api_key`、`formality`（可选）
  - Google：`api_key`
  - LibreTranslate / Lingva：`endpoint`、`api_key`（如需要）
- [ ] 明确密钥存储策略（建议优先级）：
  1) Rails credentials / env（全局） → UI 只允许选择启用项
  2) DB（仅管理员可写） → Space 选择 provider profile
- [ ] 增加 “provider 可用性” 校验与 UI 提示（未配置 key 时禁用选项）

#### 5.1.1 Provider 适配层（统一接口）

- [ ] 定义 provider 统一接口（示例）：
  - `translate!(text:, source_lang:, target_lang:) -> [translated_text, usage_hash]`
  - 统一抛出 `Translation::ProviderError`
- [ ] `Translation::Service` 支持按 `settings.provider.kind` 选择 provider（保留现有 `LLM` 实现）
- [ ] `Translation::LanguageCodeMapper` 扩展到各 provider（至少覆盖 `zh-CN/zh-TW` 的差异）

#### 5.1.2 Microsoft/Bing Translator（推荐第一个落地）

- [ ] 新增 `Translation::Providers::Microsoft`（HTTPX 调用微软翻译接口）
- [ ] 语言代码映射：`zh-CN -> zh-Hans`、`zh-TW -> zh-Hant`（已具备 mapper；需接入）
- [ ] provider-specific chunking 默认值（遵循 ST 的经验上限；同时允许用户 override `chunking.max_chars`）
- [ ] 写入 `TranslationRun.debug.usage`（建议：`{ characters:, provider_request_id: ... }`）
- [ ] 测试：
  - adapter 单测（不打外网，stub HTTPX）
  - service 集成：mask/chunk/cache/repair 仍正确

#### 5.1.3 DeepL（可选）

- [ ] 新增 `Translation::Providers::DeepL`
- [ ] LanguageCodeMapper：补 DeepL 的 code 映射（尤其中文变体）
- [ ] 可选 formality / glossary（未来增强项）
- [ ] 测试同上

#### 5.1.4 Cache key 与可观测性（避免“串味”）

- [ ] `Translation::Cache` key 纳入：
  - `provider_kind`
  - 外部 provider 的 endpoint/profile digest（避免不同 key/endpoint 复用同一 cache）
- [ ] `TranslationRun.debug` 记录：
  - `provider_kind`、`cache_hit`、`chunks`、`warnings`、`usage`

#### 5.1.5 计费/用量统计（与 LLM token 口径并行）

- [ ] LLM provider：继续用 `TokenUsageRecorder` 记入 Space owner（已完成）
- [ ] 外部 provider：不产生 token usage（建议先只记录 `debug.usage.characters`，后续再引入 `TranslationUsageRecorder`）

验收：

- Space 能选择外部 provider 并完成一次翻译（message/swipe）
- 缓存 key 不串味（切换 provider 或 key 会 cache miss）
- 失败不会影响 ConversationRun；TranslationRun 可追踪错误码与耗时

### Phase 1.5（建议插队）：TranslationRun 追踪 + Events（可视化）

目标：让翻译像 `ConversationRun` 一样“可追踪、可诊断、可取消”。

- [x] 新增 `TranslationRun` 模型与表（并关联 `Message/MessageSwipe`）
- [x] enqueue 翻译时创建 `TranslationRun`，Job 改为基于 `translation_run_id` 执行并更新状态/进度
- [x] Clear translations / mode=off：标记相关 TranslationRun 为 canceled，并让执行中的 job 早退（保留幂等）
- [x] 事件：在状态迁移点 emit `translation_run.*`（落 `conversation_events`）
- [x] UI：在 Conversation 的 Runs/Events 面板展示 Translation events / TranslationRuns（最小可读：queued/running/succeeded/failed + 耗时 + error code）
- [x] Token usage：翻译（包括输出翻译与输入 canonicalization）所消耗的 tokens 应计入 Space owner（Playground 创建者），与 `ConversationRun` 口径一致（复用 `TokenUsageRecorder`）
- [x] 测试：状态迁移、取消、幂等、事件 payload

---

## 6. 测试与验收策略（Playground CI 口径）

- 单元测试（Minitest）：
  - Mask/Unmask（代码块、URL、Handlebars、行结构）
  - Extractor（只取 `<textarea>` 内容，拒绝夹带解释）
  - Cache key versioning（配置变化必然 miss）
- 集成测试：
  - Translate both：user canonical 写入后 PromptBuilder 输出确实为 internal=en
  - assistant 翻译 job 写入后 UI 渲染优先显示译文
- 运行：`cd playground && bin/ci`

---

## 7. 参考实现速记（本仓库 references）

### 7.1 SillyTavern：内置 translate 扩展（行为与代码）

关键点（来自代码）：

- auto mode：`none/responses/inputs/both`
- provider 的分段上限：Google/Lingva 5000、DeepLX 1500、Bing 1000（见 `chunkedTranslate` 调用）
- 单条消息 toggle：通过 `message.extra.display_text` 是否存在来决定“显示译文还是原文”
- Clear translations：删除 `extra.display_text` / `extra.reasoning_display_text`

代码位置：

- `references/SillyTavern/public/scripts/extensions/translate/index.js`
- `references/SillyTavern/public/scripts/extensions/translate/index.html`

### 7.2 RisuAI：translator 模块（工程化细节）

可借鉴点（来自代码）：

- 内存级 cache（origin/trans 双向映射）
- “不翻译的片段”按行切分保护：`{{img}}/{{raw}}/{{video}}/{{audio}}`（避免破坏嵌入语法）
- 多 provider：LLM / DeepL / DeepLX / Bergamot（本地）等
- 对 Markdown italic 的修正：避免 `* text *` 被翻坏（正则修复）

代码位置：

- `references/Risuai/src/ts/translator/translator.ts`

### 7.3 LinguaGacha：项目化工作流（规则与增量）

可借鉴点（来自 README）：

- 自动生成 glossary，保证专名一致性
- Text Preserve / Replacement（译前/译后替换规则）
- Incremental Translation（增量翻译与断点续跑思路）

参考位置：

- `references/LinguaGacha/README_EN.md`

### 7.4 AiNiee：输出契约 + 文本处理/校验

可借鉴点（来自代码与 prompt 模板）：

- 输出契约：要求译文包在 `<textarea>…</textarea>` 内（便于提取与防止夹带）
- TextProcessor：用 regex 库 + 禁翻表生成 patterns，进行译前占位/译后还原，保留空白与行结构
- TranslationChecker：术语表“原文命中才要求译文包含 dst”，禁翻表/占位符/数字序号等规则检查

参考位置：

- prompt 模板：`references/AiNiee/Resource/Prompt/Translate/common_system_en.txt`
- 提取器：`references/AiNiee/ModuleFolders/Domain/ResponseExtractor/ResponseExtractor.py`
- 文本处理：`references/AiNiee/ModuleFolders/Domain/TextProcessor/TextProcessor.py`
- 规则检查：`references/AiNiee/ModuleFolders/Service/TranslationChecker/TranslationChecker.py`
