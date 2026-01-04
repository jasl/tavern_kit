# Conversation 自动回复与调度（Run 驱动）

本文档描述 Playground 中 **Space/Conversation** 的自动回复（Auto‑Response）与调度机制（Run‑driven Scheduler）。

另见：
- `docs/SPACE_CONVERSATION_ARCHITECTURE.md`
- `docs/CONVERSATION_RUN.md`
- `docs/BRANCHING_AND_THREADS.md`

核心拆分（保持正交）：
- **Space**：权限/参与者/默认策略（reply_order、auto_mode 等）
- **Conversation**：消息时间线（messages）
- **ConversationRun**：运行态执行状态机（queued/running/…）

## 设计原则

- **不使用 placeholder message**：LLM 流式内容只写入 typing indicator（ActionCable JSON 事件），生成完成后一次性创建最终 Message（Turbo Streams DOM 更新）。
- **并发约束（单槽队列）**：每个 conversation 同时最多 1 个 `running` run，同时最多 1 个 `queued` run（后写覆盖 queued）。
- **Space 只存配置**：运行态统一收敛到 `conversation_runs`，消息时间线在 `messages`。

## 数据模型（Playground）

### Space（配置）

| 字段 | 类型 | 说明 |
|------|------|------|
| `reply_order` | enum(string) | 发言策略：`manual/natural/list/pooled` |
| `card_handling_mode` | enum(string) | 群组卡处理：`swap/append/append_disabled`（影响 PromptBuilder） |
| `allow_self_responses` | boolean | 是否允许同一 speaker 连续发言（影响 speaker 选择/auto‑mode） |
| `auto_mode_enabled` | boolean | 是否启用 AI→AI followup |
| `auto_mode_delay_ms` | integer | auto‑mode 延迟（毫秒） |
| `during_generation_user_input_policy` | enum(string) | 生成中用户输入：`reject/queue/restart` |
| `user_turn_debounce_ms` | integer | 用户消息触发 debounce（毫秒，落在 queued.run_after） |
| `group_regenerate_mode` | enum(string) | 群组重生成模式：`single_message/last_turn` |
| `settings` | jsonb | schema pack 配置（`preset.*` / `world_info_*` / `scenario_override` / `join_prefix` 等） |
| `settings_version` | integer | settings 版本号（用于迁移） |

### Conversation（消息时间线）

| 字段 | 类型 | 说明 |
|------|------|------|
| `space_id` | bigint | 所属 Space |
| `kind` | enum(string) | 对话类型：`root/branch/thread` |
| `title` | string | 标题 |
| `parent_conversation_id` | bigint? | 上游对话（`branch/thread` 需要） |
| `forked_from_message_id` | bigint? | 分支点消息（仅 `branch`；来自 `parent_conversation`） |

#### Branch vs Thread

- **branch**：分支会把 `parent_conversation` 中 `seq <= forked_from_message.seq` 的消息 **克隆** 到一个新 Conversation（保留 `seq`，并克隆 message_swipes/active_swipe）。用于“先分支，再编辑/重生成”这类 ST 风格工作流。
- **thread**：线程只是一个“挂在 parent 上的另一条时间线”（当前不自动克隆历史）。用于以后实现“同一 Space 下的并行话题/子对话”。

### SpaceMembership（空间内身份）

| 字段 | 类型 | 说明 |
|------|------|------|
| `space_id` | bigint | 所属 Space |
| `kind` | enum(string) | `human/character` |
| `user_id` | bigint? | 真人用户（`kind=human`；允许被软删除后置空） |
| `character_id` | bigint? | 角色卡（`kind=character`；允许被软删除后置空） |
| `role` | enum(string) | `owner/member/moderator` |
| `position` | integer | 排序（0-based） |
| `status` | enum(string) | 生命周期：`active/removed`（removed 表示已离开/被移除，历史消息保留） |
| `participation` | enum(string) | 参与度：`active/muted/observer`（控制 AI speaker 选择） |
| `cached_display_name` | string? | 缓存的显示名（创建时写入，确保移除后历史消息仍可读） |
| `persona` | text? | 覆盖 persona（为空时可回退到 character.personality） |
| `copilot_mode` | enum(string) | `none/full`（`full` 表示自动以"用户"身份发言） |
| `copilot_remaining_steps` | integer? | `full` 模式剩余步数（1–10） |
| `llm_provider_id` | bigint? | 生成 provider 选择（空则使用默认 provider） |
| `settings` | jsonb | 目前主要存 `llm.*`（provider-scoped generation settings） |
| `settings_version` | integer | settings 版本号（用于迁移） |

**Status vs Participation 说明：**
- `status=active`：活跃成员，可访问空间
- `status=removed`：已移除，无法访问但消息保留（作为作者锚点）
- `participation=active`：完全参与，包含在 AI speaker 选择中
- `participation=muted`：不自动选择发言，但可手动触发（Force Talk）
- `participation=observer`：仅观察（预留用于未来多人空间）

**关键 scope：**
- `active`：`status = 'active'`
- `participating`：`status = 'active' AND participation = 'active'`（用于自动 speaker 选择）

### ConversationRun（运行态）

`conversation_runs` 表记录一次“需要 AI 生成”的执行单元（Run）。

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | uuid | 主键 |
| `conversation_id` | bigint | 所属 Conversation |
| `kind` | enum(string) | `user_turn/auto_mode/regenerate/force_talk` |
| `status` | enum(string) | `queued/running/succeeded/failed/canceled/skipped` |
| `reason` | string | 触发原因（如 `user_message`、`force_talk`、`copilot_start`、`auto_mode` 等） |
| `speaker_space_membership_id` | bigint | 本次生成的 speaker（SpaceMembership） |
| `run_after` | datetime? | 计划执行时间（用于 debounce/延迟） |
| `cancel_requested_at` | datetime? | 软取消标记（restart 策略） |
| `started_at` | datetime? | 开始执行时间（进入 running 状态） |
| `finished_at` | datetime? | 完成时间（进入 succeeded/failed/canceled/skipped 状态） |
| `heartbeat_at` | datetime? | running run 心跳（stale 自愈） |
| `error` | jsonb | 错误信息（含 token usage） |
| `debug` | jsonb | 调试信息（本架构不把 trigger/expected 之类写成列；统一写入 debug） |

`debug` 常用键（按触发场景不同而存在差异）：
- `trigger`：`user_message/auto_mode/regenerate/force_talk/...`
- `user_message_id`：用户消息触发（user_turn）
- `trigger_message_id`：触发消息（auto_mode / copilot followup / continue）
- `target_message_id`：重生成目标消息（regenerate）
- `expected_last_message_id`：auto-mode 防污染（claim 时校验 conversation 最后一条 message.id）

### Message（对话日志）

| 字段 | 类型 | 说明 |
|------|------|------|
| `conversation_id` | bigint | 所属 Conversation |
| `space_membership_id` | bigint | 发送者（SpaceMembership） |
| `seq` | bigint | conversation 内的确定性顺序（唯一） |
| `role` | enum | `user/assistant/system` |
| `content` | text | 内容（生成完成后创建） |
| `conversation_run_id` | uuid? | 关联 run（本次生成/重生成） |
| `metadata` | jsonb | 调试字段（错误/参数快照等） |

## 并发与一致性保证

数据库层使用部分唯一索引强约束（见 `playground/db/migrate/20260103000004_create_conversation_runs.rb`）：

- `UNIQUE(conversation_id) WHERE status='running'`
- `UNIQUE(conversation_id) WHERE status='queued'`

因此：

- 同一 conversation 不会出现两个并发生成（最多一个 `running`）。
- queued run 是单槽队列：后来的触发会覆盖 queued 的字段（trigger_message_id/run_after 等）。

消息顺序保证：
- `messages.seq` 在 `(conversation_id, seq)` 上有唯一索引（见 `playground/db/migrate/20260103000005_create_messages.rb`）。
- 自动分配 `seq` 时，会对 `conversation` 加锁并在同一事务内取 `max(seq)+1`，确保并发下顺序确定。

## 核心组件与职责

### 1) SpeakerSelector（speaker 选择）

实现：`playground/app/services/speaker_selector.rb`

- 策略：`manual/natural/list/pooled`
- 候选人范围（自动发言）：
  - `conversation.ai_respondable_participants`（SpaceMembership；AI 角色 + full copilot user）
  - `space_memberships.participating`（`status='active' AND participation='active'`）
  - `can_auto_respond? == true`（copilot_remaining_steps 等约束）

**注意**：`participation=muted` 的成员不会被自动选择发言，但可以通过 Force Talk 手动触发。`status=removed` 的成员完全不参与后续 prompt 构建。

`pooled` 策略说明（与旧版不同）：
- 不在 settings 里存 pool；而是通过 DB 反推：
  - epoch = `conversation.last_user_message`
  - 在该 user message 之后出现过的 `assistant` 消息里的 `space_membership_id`，视为本 epoch 已发言集合
  - 当 pool 耗尽时返回 nil，停止 auto-mode（这与 ST 行为不同，见 divergences 文档）

### 2) Conversation::RunPlanner（计划/写入 queued）

实现：`playground/app/services/conversation/run_planner.rb`

把用户行为转换为 `conversation_runs`（写入 queued 或覆盖 queued），并按需触发取消（restart）。

关键入口：
- `plan_from_user_message!(conversation:, user_message:)`
  - `reply_order == "manual"`：不自动生成（返回 nil）
  - 否则：选 speaker → 计算 `run_after = now + user_turn_debounce_ms` → upsert queued → kick
- `plan_force_talk!(conversation:, speaker_space_membership_id:)`：manual 模式下显式指定 speaker
- `plan_regenerate!(conversation:, target_message:)`：软取消 running，并创建 regenerate queued
- `plan_auto_mode_followup!(conversation:, trigger_message:)`：AI→AI followup（需 `auto_mode_enabled`）
- copilot 链路：`plan_copilot_start!/plan_copilot_followup!/plan_copilot_continue!`

生成中用户输入策略：
- `reject`：在 `Conversations::MessagesController#create` 直接拒绝写入 user message（HTTP 423 / Locked）
- `restart`：写入新 user message 时取消当前 running（设置 cancel_requested_at）
- `queue`：允许写入并 upsert queued（running 结束后再执行）

### 3) Conversation::RunExecutor（执行/状态机）

实现：`playground/app/services/conversation/run_executor.rb`

执行流程（无 placeholder）：
1) claim queued（设置为 running，检查 expected_last_message 防污染）
2) `ConversationChannel.broadcast_typing_start`
3) LLM 流式 chunks → `ConversationChannel.broadcast_stream_chunk`（仅更新 typing indicator）
4) 生成完成后创建最终 Message 或为 target message 增加 swipe
5) Turbo Streams 广播最终 DOM 更新（`Message#broadcast_create` / `broadcast_update`）
6) `ConversationChannel.broadcast_typing_stop` + `broadcast_stream_complete`
7) 触发 followups（auto-mode / copilot loop）

### 4) ConversationRunReaperJob（stale 自愈）

实现：`playground/app/jobs/conversation_run_reaper_job.rb`

- running run 超时（heartbeat stale）→ 标记 failed
- 如存在 queued run → kick 继续执行

### 5) 实时通道（JSON 事件）

- `ConversationChannel`：typing/streaming（JSON）
- `CopilotChannel`：copilot candidates（JSON，按 space_membership 单播）

最终消息 DOM 更新走 Turbo Streams（`Message::Broadcasts`）。

## Append Reply Rules (Auto vs Manual)

This section documents when and how AI responses are triggered.

### Automatic Reply Triggers

| Trigger | Condition | Run Kind | Notes |
|---------|-----------|----------|-------|
| User message | `reply_order != manual` | `user_turn` | Respects debounce; speaker via SpeakerSelector |
| Auto-mode followup | `auto_mode_enabled && reply_order != manual` | `auto_mode` | AI responds to AI; uses `expected_last_message_id` |
| Copilot loop | `copilot_mode = full` | `user_turn` | Automated persona→AI→persona flow |

### Manual Reply Triggers

| Trigger | Endpoint | Run Kind | Speaker Selection |
|---------|----------|----------|-------------------|
| Generate (no speaker) | `POST /conversations/:id/generate` | `force_talk` | Random from participating AI characters (manual) or SpeakerSelector (non-manual) |
| Force Talk (with speaker) | `POST /conversations/:id/generate?speaker_id=X` | `force_talk` | Specified member (works even if muted) |
| Regenerate | `POST /conversations/:id/regenerate` | `regenerate` | Same as target message author |

### `reply_order` Semantics

| Mode | User Message → Auto Reply | Generate Button | Force Talk |
|------|---------------------------|-----------------|------------|
| `manual` | No | Yes (random active AI) | Yes (any active AI, incl. muted) |
| `natural` | Yes (mention detection + rotation) | Yes | Yes |
| `list` | Yes (strict position rotation) | Yes | Yes |
| `pooled` | Yes (each speaks once per epoch) | Yes | Yes |

### Pooled Mode Stop Condition

Unlike SillyTavern where pooled mode may have different stop semantics, TavernKit's pooled mode:
- Tracks "spoken in current epoch" by querying messages since the last user message
- Stops when all participating AI characters have spoken once
- New user message resets the epoch

This is an **intentional divergence** from ST — see `docs/spec/SILLYTAVERN_DIVERGENCES.md`.
