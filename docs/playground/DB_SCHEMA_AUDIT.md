# 数据库字段专项审计（schema.rb + 迁移）

Last updated: 2026-01-12

目标：对 `playground/db/schema.rb` 与 `playground/db/migrate/*` 做一次“字段可简化/可删”的专项审计，并把结论落盘，降低后续重构/迭代时的误判与重复劳动。

## 范围与事实边界

- 当前 Playground 只有一个初始化迁移：`playground/db/migrate/20260108045602_init_schema.rb`
  - 这意味着：**schema 的大部分字段/注释来自初始设计**，在多轮重构后容易出现“代码已变、注释未变”的漂移。
- 本审计主要覆盖 TurnScheduler/ConversationRun 相关核心表（也包含必要的上游表）：
  - `spaces`
  - `space_memberships`
  - `conversations`
  - `conversation_runs`
  - `messages`
  - `message_swipes`

## 方法（避免“幻觉”的约束）

- 以 `schema.rb` 为 DB 真实字段清单来源。
- 以 **Model 常量/enum/校验** 作为“代码当前约束”的来源。
- 对“可删/可简化”的判断必须满足至少其一：
  - 该字段在 `playground/app`（含 views/js）中无用途，且无迁移/兼容性理由保留；
  - 或者该字段明确为 legacy 且已经有迁移路径（数据回填/替换字段）；
  - 或者字段是冗余派生值，移除后不会破坏关键路径与一致性（需要额外的回归测试）。

## 关键发现

### 1) 未发现“立刻可安全删除”的 TurnScheduler 核心字段

TurnScheduler 依赖的 Conversation 状态字段（如 `current_round_id`、`round_queue_ids`、`round_position`、`current_speaker_id`、`group_queue_revision` 等）在代码与测试中都有明确用途；短期内删除任一字段都会扩大重构半径并增加一致性风险。

结论：本轮专项审计 **不做字段删除**，先把“注释/约束与代码一致性”修正到位，再考虑更大的 schema 简化（见后续建议）。

### 2) schema 注释已明显漂移（会误导后续维护）

以下列举的列 **字段本身在用**，但 schema comment 与代码枚举/语义不一致，容易导致阅读 schema.rb 时产生错误结论：

- `conversations.kind`
  - schema 注释：`root, branch`
  - 代码：`Conversation::KINDS = root, branch, thread, checkpoint`
- `conversations.status`
  - schema 注释：`ready, busy, error`
  - 代码：`Conversation::STATUSES = ready, pending, failed, archived`
- `conversations.scheduling_state`
  - schema 注释包含 `round_active`
  - 代码：`Conversation::SCHEDULING_STATES = idle, waiting_for_speaker, ai_generating, failed`
- `spaces.status`
  - schema 注释：`active, archived, deleted`
  - 代码：`Space::STATUSES = active, archived, deleting`
- `spaces.visibility`
  - schema 注释：`private, unlisted, public`
  - 代码：`Space::VISIBILITIES = private, public`
- `characters.status`
  - schema 注释：`pending, ready, error`
  - 代码：`Character::STATUSES = pending, ready, failed, deleting`
- `messages.generation_status`
  - schema 注释包含 `canceled`
  - 代码：`Message::GENERATION_STATUSES = generating, succeeded, failed`（当前未见 `canceled` 的实际使用）

结论：先通过迁移把注释修正到与代码一致，降低维护成本与误判概率。

## 已采取动作（本次修正）

- 已将 enum/comment 漂移修正合并进初始化迁移，确保“重建数据库”时一次性落地：
  - `playground/db/migrate/20260108045602_init_schema.rb`

## 后续建议（需要单独评估，暂不在本轮落地）

- **COW 内容存储的“最终收敛”**：`messages.content` / `message_swipes.content` 与 `text_content_id` 目前并存且带 legacy 语义；若未来确定完全迁移到 `text_contents`，可考虑：
  - 先做数据回填/一致性校验；
  - 再分阶段移除 legacy 列，避免线上历史数据导致的回滚困难。
- **冗余字段派生化**（高风险，需要回归与压测）：
  - 例如是否可以从 `round_queue_ids + round_position` 派生 `current_speaker_id` 来减少冗余与不一致风险；
  - 这类改动会触达 TurnScheduler/QueuePreview/UI 广播与锁语义，必须配套“多进程 + 边界条件”回归。
