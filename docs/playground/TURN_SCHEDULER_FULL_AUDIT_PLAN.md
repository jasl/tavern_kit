# TurnScheduler / Round Schema 重构全量资料与计划（激进方案）

Last updated: 2026-01-12

目标：把 TurnScheduler 的“回合（round）运行态”从 `conversations` 表中抽离成一等实体（新表），并把关键语义从 `conversation_runs.debug` 提升为结构化字段/外键。

前提：当前数据库已清空，不需要兼容 legacy 数据与迁移回填。

> 这份文档是为了“反幻觉”：先把证据（代码/文档/测试）与计划落盘，再动大刀。

## 状态（已落地）

本方案已按“激进路线”落地完成（并在 Playground 全量测试中保持全绿）。关键落点：

- Round 运行态已从 `conversations` 完全移除：
  - 新表：`conversation_rounds`、`conversation_round_participants`
  - 新外键：`conversation_runs.conversation_round_id`（nullable，`on_delete: :nullify`）
- `waiting_for_speaker` 已删除（idle 即“等待真人输入触发下一轮”）
- Round 记录保留并支持清理：保留最近 24h，每日定时清理（清理后 run 的 round 关联允许变为 `nil`）
- TurnScheduler-managed run 不再写入 `debug["round_id"]`（以 `conversation_round_id` 为唯一结构化来源）
- 对应迁移：
  - `playground/db/migrate/20260112142430_add_conversation_rounds.rb`
  - `playground/db/migrate/20260112180000_drop_conversation_round_state_columns.rb`

> 注意：下文 1) 的“现状事实”描述的是重构前状态，作为历史背景与动机保留；当前真实 schema 以 `playground/db/schema.rb` 为准。

---

## 0) 范围与非目标

### 范围

- TurnScheduler 回合状态（round state）的存储与并发语义
- `ConversationRun` 与 round 的关联方式
- UI queue bar（`GroupQueuePresenter` + ActionCable/Turbo Streams）对 round state 的读取路径

### 非目标

- 不做历史数据迁移/回填（DB 已清空）
- 不在本轮顺便重构 PromptBuilder、Message COW、Branching 等无关主题（除非被 round 重构强迫触达）

---

## 1) 现状事实（可追溯的证据点）

### 1.1 当前 round state 存储位置（conversations 表）

目前 TurnScheduler 的显式状态机落在 `Conversation` 的 DB 列上（“显式状态机”是设计原则之一）：

- `conversations.scheduling_state`：`idle | ai_generating | failed`
  - 使用点：`TurnScheduler::*` commands/queries + UI queue bar
- `conversations.current_round_id`：当前 round 的 UUID（**注意：schema comment 目前写成了“current ConversationRun UUID”，与实际用法不一致**）
  - 使用点：用于 run 乱序保护/失败恢复保护（详见 1.2）
- `conversations.current_speaker_id`：当前 speaker（membership id）
- `conversations.round_position`：0-based index
- `conversations.round_queue_ids`：bigint[]（membership ids）
- `conversations.round_spoken_ids`：bigint[]（已发言者集合）
- `conversations.group_queue_revision`：单调递增序号，用于前端忽略乱序 ActionCable queue_updated 事件

证据：
- schema：`playground/db/schema.rb`
- init migration：`playground/db/migrate/20260108045602_init_schema.rb`
- scheduler：`playground/app/services/turn_scheduler/**`
- UI：`playground/app/presenters/group_queue_presenter.rb`、`playground/app/views/messages/_group_queue.html.erb`

### 1.2 run 与 round 的绑定方式（debug["round_id"]）

TurnScheduler 创建的 run 会写入：

- `run.debug["scheduled_by"] == "turn_scheduler"`
- `run.debug["round_id"] == conversation.current_round_id`

并且后续关键路径依赖它做“陈旧消息/陈旧 run 保护”：

- `AdvanceTurn`：晚到的旧 run 消息不会破坏新 round（“queue policy”场景）
  - `TurnScheduler::Commands::AdvanceTurn#stale_run_message?`
- `HandleFailure`：只允许当前 round + 当前 speaker 的失败把 scheduler 置为 failed
  - `TurnScheduler::Commands::HandleFailure`
- `SkipCurrentSpeaker`/`RetryCurrentSpeaker`：用 `expected_round_id` 防止 stale 操作误伤新 round
  - `TurnScheduler::Commands::SkipCurrentSpeaker`
  - `TurnScheduler::Commands::RetryCurrentSpeaker`

证据：
- `playground/app/services/turn_scheduler/commands/schedule_speaker.rb`
- `playground/app/services/turn_scheduler/commands/advance_turn.rb`
- `playground/app/services/turn_scheduler/commands/handle_failure.rb`
- `playground/app/services/turn_scheduler/commands/skip_current_speaker.rb`
- `playground/app/services/turn_scheduler/commands/retry_current_speaker.rb`
- `playground/app/services/conversations/run_executor.rb`（run_skipped -> SkipCurrentSpeaker）

### 1.3 并发约束（DB 层）

`conversation_runs` 通过 partial unique index 强制单槽队列：

- 每 conversation 最多 1 个 `status=queued`
- 每 conversation 最多 1 个 `status=running`

证据：
- `playground/db/schema.rb`：`index_conversation_runs_unique_queued_per_conversation`、`index_conversation_runs_unique_running_per_conversation`

### 1.4 前端乱序保护（group_queue_revision）

`TurnScheduler::Broadcasts.queue_updated` 在每次广播前：

- `conversation.increment!(:group_queue_revision)`
- payload 带上 `group_queue_revision`

前端 `conversation_channel_controller.js` 会维护 `lastQueueRevision`，当收到旧 revision 的事件直接忽略，避免 UI 锁态闪回。

证据：
- `playground/app/services/turn_scheduler/broadcasts.rb`
- `playground/app/javascript/controllers/conversation_channel_controller.js`
- 文档：`docs/playground/FRONTEND_BEST_PRACTICES.md`（queue_updated 乱序兜底章节）

---

## 2) 我们想要的“激进改造”目标（定义清楚，避免漂移）

### 2.1 目标：round 变成一等实体（结构化 + 可约束）

把下面这些“高风险一致性字段”从 `conversations` 挪走：

- `scheduling_state`
- `current_round_id`
- `current_speaker_id`
- `round_position`
- `round_queue_ids`
- `round_spoken_ids`

并用新表表达：

- round 的生命周期（active/finished/failed）
- 当前 speaker 与队列顺序
- 哪些 participant 已发言/被跳过（为 debug/可观测性服务）

### 2.2 目标：把关键语义从 debug 提升为列/外键

把 `conversation_runs.debug["round_id"]` 升级为：

- `conversation_runs.conversation_round_id`（uuid 外键，可为空：regenerate/force_talk 等不一定属于 round）

这样可以：

- 让 stale message / stale command 的保护变成“结构化等值判断”
- 避免 debug blob 承担关键一致性语义（debug 应该是诊断，不是约束）

### 2.3 目标：回到架构原则

文档 `docs/playground/CONVERSATION_RUN.md` 一开始写的原则是：

> Keep runtime state out of Space/Conversation/Message

但现状 round state 落在 `Conversation` 上，容易让读者困惑（甚至形成文档自相矛盾）。

激进方案完成后，可以把 “runtime scheduler state” 的物理存储真正放到独立表中，
`Conversation` 回归“timeline owner”，并统一文档口径。

---

## 3) 当前仍不明确/需要你拍板的点（先讨论再动手）

1) **Round 是否需要“历史留存”？**
   - 现状：round 结束就清空列，没有历史。
   - 新方案选项：
     - A. 只保留 active round（一结束就 delete，最省空间，但 debug 断链）
     - B. 保留 round 记录并标记 finished（更利于 debug/审计，但会增长）
   - 关键约束：queue policy 允许“新 round 覆盖旧 round（旧 run 仍会晚到完成）”，因此如果 run 用外键绑定 round，
     **旧 round 记录至少要保留到相关 run/message 不再需要 stale 保护**（否则晚到消息会失去 round_id，从而无法判 stale）。
   - 我倾向：B（保留），并加一个简单的清理策略（例如按会话保留最近 N 条 / TTL），且只清理“无 active run 引用”的旧 round。

   你已选择：**B + 24h retention + 每日定时清理**。

   额外约束（你强调的点）：runs/messages 等持久化记录 **不能硬依赖 round**，清理后允许 round 关联变成 `nil`。
   这会影响 schema：`conversation_runs.conversation_round_id` 必须是 nullable，并且 FK 必须 `on_delete: :nullify`。

2) **`waiting_for_speaker` 是否仍要保留？**
   - 现状：TurnScheduler queue 只包含 `can_auto_respond?` 的成员（代码里也写了 “should always be true”），
     因此实际几乎只会出现 `ai_generating`/`failed`/`idle`。
   - 选项：
     - A. 保留（为未来“人类入队/手动轮次”留口子）
     - B. 删除（简化状态机，减少无效分支）

   你的顾虑：多真人 + 多 AI 的空间是否需要它？
   - 结论建议：**不需要**。当前语义是“真人消息是触发器，不进入 round 队列”，因此 idle 就是“等待任意真人输入”。
     未来如果要做“真人入队/超时/交接”等语义，再新增 state 会更清晰（本项目 pre-1.0 可直接 breaking）。

   你已选择：**B（删除）**。

3) **Force Talk 属于 round 吗？**
   - 现状：`ConversationsController#generate` 走 `RunPlanner.plan_force_talk!`，并不进入 round。
   - 新方案选项：
     - A. force_talk 是“独立 run”（`conversation_round_id = nil`），不影响/不依赖 round
     - B. force_talk 强制开启/覆盖 round（会改变很多现有假设）
   - 我倾向：A（保持语义稳定），但需要明确它对 TurnScheduler 的影响边界（例如产生 assistant message 是否会触发新 round）。

   你已选择：**A（独立 run）**。

4) **Skip/Retry 的“expected_round”保护要到什么程度？**
   - 现状：Skip/Retry/HandleFailure 都对 `round_id` 做等值保护。
   - 新方案：用 `run.conversation_round_id` 与 `active_round.id` 对齐。

   你已确认：**保留等值保护语义**（stale 保护继续作为 P0）。

5) **非 TurnScheduler run（`force_talk`/`regenerate`）的消息，会不会推进 active round？**
   - 现状：Message `after_create_commit` 无差别调用 `AdvanceTurn`；而 `AdvanceTurn` 的 stale 保护只在 run 带 `round_id` 时生效。
     这意味着：独立 run 产生的 assistant message 在“当前 round active”时，可能会推进队列（取决于当时是否 active）。
   - 新方案的潜在选项：
     - A. 维持现状（独立 run 的消息仍可能推进 round）
     - B. 强化隔离（独立 run 不推进 round；必要时在计划独立 run 时先 `StopRound`）
   - 结论：选择 **B（强化隔离）**，并已落地实现与测试（见下方“已落地”）。

   已落地（强隔离的两道保险）：
   - **计划阶段**：在 plan `force_talk` / `regenerate` 前，先对 conversation 执行一次 `StopRound`，取消 active round 与 queued scheduler run（避免“独立 run 覆盖队列/污染 round”）。
   - **调度阶段**：`AdvanceTurn` 在存在 active round 时，**忽略** “run 没有 `conversation_round_id`” 的 message（独立 run 的消息不会推进/标记/重算该 round）。

   对应代码与测试：
   - `playground/app/services/conversations/run_planner.rb`
   - `playground/app/services/turn_scheduler/commands/advance_turn.rb`
   - `playground/test/services/conversations/run_planner_test.rb`
   - `playground/test/services/turn_scheduler/commands/advance_turn_test.rb`

---

## 4) 拟议新 Schema（草案）

> 下面是“结构形态”，不是最终字段名；我们会在确定 3) 的决策后再落到 migration。

### 4.1 `conversation_rounds`（回合实体）

- `id`：uuid PK
- `conversation_id`：bigint FK（conversation）
- `status`：string（建议值：`active | finished | superseded | canceled`；`idle` 由“无 active round”表达）
- `scheduling_state`：string（当前实现允许：`ai_generating | failed`；仅在 `status=active` 时有意义）
- `current_position`：integer（0-based）
- （可选）`ended_reason`：string（例如 `queue_policy_superseded` / `user_stop` / `round_complete`）
- `started_at` / `finished_at`
- （可选）`trigger_message_id`：bigint（本 round 的触发消息，便于 debug）
- （可选）`metadata`：jsonb（诊断/统计用；避免承载关键一致性语义）

约束建议：
- partial unique index：同一 conversation 最多 1 个 `status='active'` round（或 `status IN ('active')`）
- check：`status in (...)`、`scheduling_state in (...)`（并可额外约束：`status='active' -> scheduling_state not null`）

### 4.2 `conversation_round_participants`（队列/参与者）

- `id`：bigint PK（或复合主键也行）
- `conversation_round_id`：uuid FK（round）
- `position`：integer（0-based，unique per round）
- `space_membership_id`：bigint FK
- `status`：string（建议值：`pending | spoken | skipped`）
- `spoken_at` / `skipped_at`
- `skip_reason`（string）
- timestamps

约束建议：
- unique index：`(conversation_round_id, position)`
- unique index：`(conversation_round_id, space_membership_id)`（防止同一成员重复入队）

### 4.3 `conversation_runs` 增加结构化关联

- 新增：`conversation_round_id`（uuid FK，可为空）
- 对 TurnScheduler 创建的 run：必须写入该字段（替代 debug round_id）
- 对 regenerate/force_talk：可为空（取决于 3) 的决策）

> 你已要求：round 清理后允许把关联置空，因此该 FK 必须是 `on_delete: :nullify`，并且代码要能处理 `conversation_round_id=nil`（只在极端/历史场景下出现）。

### 4.4 代码映射（现状字段 → 新 schema）

目标：尽量不改“上层语义”，只改“存储形态”，并让代码 review 能逐条对照。

**Conversation（读）**
- `conversation.scheduling_state`
  - 现状：读 `conversations.scheduling_state`
  - 新：若无 active round -> `"idle"`；否则读 `active_round.scheduling_state`
- `conversation.current_round_id`
  - 现状：读 `conversations.current_round_id`（round token）
  - 新：读 `active_round.id`
- `conversation.round_queue_ids`
  - 现状：读 `conversations.round_queue_ids`（bigint[]）
  - 新：读 `active_round.participants.order(:position).pluck(:space_membership_id)`
- `conversation.round_position`
  - 现状：读 `conversations.round_position`
  - 新：读 `active_round.current_position`
- `conversation.current_speaker_id`
  - 现状：读 `conversations.current_speaker_id`
  - 新：读 `active_round.participants.find_by(position: current_position)&.space_membership_id`
- `conversation.round_spoken_ids`
  - 现状：读 `conversations.round_spoken_ids`
  - 新：读 `active_round.participants.spoken.pluck(:space_membership_id)`（取决于 participants 的实现）

**TurnScheduler（写）**
- `StartRound`
  - 新：结束旧 active round（`status=superseded`）→ 创建新 round（`status=active`）→ 批量插入 participants
  - 继续：首个 speaker 仍由 `ActivatedQueue` 决定；队列 mid-round 不重算
- `ScheduleSpeaker#create_run`
  - 新：`ConversationRun.create!(conversation_round_id: active_round.id, ...)`
  - 旧：`debug["round_id"]` 逐步变成“仅诊断”或完全移除
- `AdvanceTurn#stale_run_message?`
  - 新：对比 `run.conversation_round_id` 与 `conversation.current_round_id`（active round）来判 stale
- `HandleFailure` / `SkipCurrentSpeaker` / `RetryCurrentSpeaker`
  - 新：用 `conversation_round_id` 做 expected_round 保护（替代 debug["round_id"]）

---

## 5) 测试先行：重构前需要补齐/强化的“行为固定”

目标：把我们真正关心的行为用测试钉死，避免重构时把语义改坏却不自知。

已存在且很关键的测试（先确保全绿）：
- TurnScheduler commands/queries：`playground/test/services/turn_scheduler/**`
- queue policy 的“late previous AI message”保护：`playground/test/services/turn_scheduler_input_policy_test.rb`
- Broadcast revision 单调性：`playground/test/services/turn_scheduler/broadcasts_test.rb`

我建议在开始 schema 重构前补上（目前缺口）：
- `TurnScheduler::Commands::HandleFailure` 的单元测试：
  - 仅当 run 属于当前 round + 当前 speaker + scheduled_by=turn_scheduler 时才会把 scheduler 置为 failed
  - 会 cancel queued runs，但 **保留 round state**（不清空队列/position）
  - stale round（expected round mismatch）不会误伤

（我会先提交这些测试，再开始写 migration/重构。）

---

## 6) 分阶段落地计划（建议）

> DB 已清空也建议分阶段：每阶段都有“可回退/可验证”的 checkpoint，降低大改的认知负担。

阶段 0：补测试 + 修文档自相矛盾点（本文件 + `DB_SCHEMA_AUDIT.md`）

阶段 1：引入新表/新列（rounds + participants + conversation_runs.conversation_round_id）

阶段 2：TurnScheduler 全量改为读写新表（仍保留旧列一段时间也可以，但最终会删除）

阶段 3：删除 conversations 上的 round state 列（只保留 UI 用的 `group_queue_revision` 等非关键运行态）

阶段 4：清理 debug 依赖（`debug["round_id"]` 不再是关键语义）+ 更新文档（`CONVERSATION_RUN.md` / `CONVERSATION_AUTO_RESPONSE.md` / `FRONTEND_TEST_CHECKLIST.md`）

---

## 7) 逐步执行清单（更偏工程落地）

> 这部分是“做到哪一步算完成”的 checklist，尽量避免重构中途迷路。

### 阶段 0：测试与资料（先做）

- [x] 阅读/同步：`docs/playground/DB_SCHEMA_AUDIT.md`
- [x] 阅读/同步：`docs/playground/CONVERSATION_RUN.md`（注意其中对“runtime state”口径的矛盾）
- [x] 新增并跑通：`TurnScheduler::Commands::HandleFailure` 单测
- [x] `cd playground && bin/rails test`（至少跑 TurnScheduler 相关目录）

### 阶段 1：Schema 落地（新增 round 表 + run 外键）

- [x] migration：创建 `conversation_rounds`
- [x] migration：创建 `conversation_round_participants`
- [x] migration：`conversation_runs` 增加 `conversation_round_id`（nullable FK）
- [x] 建索引/约束：
  - [x] 同 conversation 仅 1 个 active round（partial unique）
  - [x] participants：position 唯一、membership 唯一
- [x] `cd playground && bin/rails db:migrate` 后更新 `playground/db/schema.rb`

### 阶段 2：TurnScheduler 改读写新表

- [x] `StartRound`：结束旧 active round（superseded）→ 创建新 round + participants
- [x] `ScheduleSpeaker`：创建 run 时写入 `conversation_round_id`
- [x] `AdvanceTurn`：stale message 保护改为 round 外键对齐
- [x] `HandleFailure` / `SkipCurrentSpeaker` / `RetryCurrentSpeaker`：expected_round 保护改为 round 外键
- [x] `QueuePreview`：round active 时从 participants 读 upcoming（不再依赖 bigint[]）
- [x] `RoundState`：改为从 active round 读（仍保留同名读接口，方便上层代码迁移）

### 阶段 3：移除 conversations 上的 round state 列

- [x] 删除列：`scheduling_state/current_round_id/current_speaker_id/round_position/round_queue_ids/round_spoken_ids`
- [x] 保留列：`group_queue_revision`（UI 乱序保护用）
- [x] 修复所有写入点（`conversation.update!(...)` 之类）

### 阶段 4：收尾与一致性

- [x] 移除/降级 `debug["round_id"]` 为纯诊断字段（或彻底删除）
- [x] 更新文档口径：
  - [x] `docs/playground/CONVERSATION_RUN.md`
  - [x] `docs/playground/CONVERSATION_AUTO_RESPONSE.md`
  - [x] `docs/playground/FRONTEND_TEST_CHECKLIST.md`（删掉 `recalculate_queue!` 这类已不存在的描述）
- [x] `cd playground && bin/ci`
