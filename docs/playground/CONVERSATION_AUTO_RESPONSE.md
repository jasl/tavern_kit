# Conversation 自动回复与调度（TurnScheduler）

本文档描述 Playground 中 **Space/Conversation** 的统一回合调度机制。

另见：
- `SPACE_CONVERSATION_ARCHITECTURE.md`
- `CONVERSATION_RUN.md`
- `BRANCHING_AND_THREADS.md`
- `docs/spec/SILLYTAVERN_DIVERGENCES.md`

## 设计原则

- **单一队列**：所有可自动回复的参与者（AI 角色、Copilot full 人类）在同一个有序队列中
- **消息驱动推进**：`Message#after_create_commit` 触发回合推进
- **人类不入队**：普通人类消息是触发源，不会进入 round 队列（`conversation_round_participants`），也不会创建“人类回合”任务
- **不使用 placeholder message**：LLM 流式内容只写入 typing indicator，生成完成后一次性创建最终 Message
- **显式状态机**：调度状态存储在 round 表（`conversation_rounds`）中，而不是派生自其他数据
- **Command/Query 分离**：操作通过独立的命令对象执行，查询通过查询对象执行

## 统一调度架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    触发源 (Triggers)                              │
├─────────────────────────────────────────────────────────────────┤
│  User sends message    Auto Mode enabled    Copilot enabled     │
│  AI message created    Force Talk           Member changes      │
└───────────┬─────────────────────────────────────────────────────┘
            │
            v
┌─────────────────────────────────────────────────────────────────┐
│              Message after_create_commit                         │
│                                                                  │
│  → TurnScheduler::Commands::AdvanceTurn.call(...)               │
└───────────┬─────────────────────────────────────────────────────┘
            │
            v
┌─────────────────────────────────────────────────────────────────┐
│                    TurnScheduler                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Round Runtime State (DB)                               │    │
│  │                                                         │    │
│  │  conversation_rounds:                                   │    │
│  │    status: active | finished | superseded | canceled     │    │
│  │    scheduling_state: ai_generating | failed (active)     │    │
│  │    current_position: integer (0-based)                   │    │
│  │                                                         │    │
│  │  conversation_round_participants:                        │    │
│  │    (round_id, position) -> space_membership_id           │    │
│  │    status: pending | spoken | skipped                    │    │
│  │                                                         │    │
│  │  conversation_runs.conversation_round_id: uuid?          │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  Commands:                                                       │
│  → StartRound      开始新回合，计算队列，调度首个发言              │
│  → AdvanceTurn     消息创建后推进回合                             │
│  → ScheduleSpeaker 安排当前发言者的发言                           │
│  → SkipCurrentSpeaker 当前 speaker 变更时的自动跳过               │
│  → StopRound       停止回合并清理                                 │
│  → HandleFailure   处理调度失败                                   │
│  → RetryCurrentSpeaker 失败后重试当前 speaker（同 round）         │
│                                                                  │
│  Queries:                                                        │
│  → NextSpeaker     根据策略选择下一个发言者                        │
│  → QueuePreview    获取队列预览（用于 UI 显示）                    │
└───────────┬─────────────────────────────────────────────────────┘
            │
            v
┌─────────────────────────────────────────────────────────────────┐
│                  ScheduleSpeaker                                 │
│                                                                  │
│  AI → ConversationRun(kind: auto_response) → ConversationRunJob │
│  Copilot → ConversationRun(kind: copilot_response) → Job        │
└─────────────────────────────────────────────────────────────────┘
```

> 注：TurnScheduler 的 round queue 只包含可自动回复的成员（AI 角色 + Copilot full）。
> 普通人类消息只作为触发源，不会进入队列。

## 调度状态机

TurnScheduler 的 `TurnScheduler.state(conversation).scheduling_state` 可以是以下值之一：

| 状态 | 说明 |
|------|------|
| `idle` | 没有活跃的回合 |
| `ai_generating` | AI 正在生成响应 |
| `failed` | 调度失败 |

## 回合生命周期

### 1. 回合开始

回合在以下情况下开始：
- 用户启用 Auto Mode → `StartRound.call`
- 用户启用 Copilot → `StartRound.call`
- 用户发送消息（无活跃回合时）→ `AdvanceTurn` 内部调用 `start_round_after_message!`

### 2. 回合推进

每次消息创建都会触发 `AdvanceTurn`：

```ruby
# Message model
after_create_commit :notify_scheduler_turn_complete

def notify_scheduler_turn_complete
  return if system?
  TurnScheduler::Commands::AdvanceTurn.call(
    conversation: conversation,
    speaker_membership: space_membership
  )
end
```

`AdvanceTurn` 做以下事情：
1. 标记发言者为"已发言"
2. 递增 `conversation.turns_count`
3. 递减资源（copilot steps, auto mode rounds）
4. 移动到下一个发言者
5. 调用 `ScheduleSpeaker` 安排下一个发言

### 3. 发言调度

`ScheduleSpeaker` 根据当前发言者类型采取不同行动：

| 发言者类型 | 行动 | Run kind |
|-----------|------|----------|
| AI 角色 | 创建 Run，启动生成 | `auto_response` |
| Copilot 人类 | 创建 Run，AI 替用户发言 | `copilot_response` |

普通人类（无 Copilot）不会被 `ScheduleSpeaker` 调度；人类消息仅作为触发源驱动 `AdvanceTurn/StartRound`。

### 4. 回合结束

当队列位置超过队列长度时，回合结束。调度器会：
1. 递减 auto mode rounds（如果启用）
2. 如果 auto-scheduling 仍然启用，开始新回合
3. 否则调用 `StopRound` 清除状态

## Initiative (先攻值)

每个 `SpaceMembership` 有 `talkativeness_factor` (0.0-1.0)，决定在 turn queue 中的优先级：
- **高 talkativeness**：优先发言（类似游戏中的高先攻值）
- **低 talkativeness**：后发言
- **相同 talkativeness**：按 `position` 排序

## 数据模型

### Conversation（消息时间线）

| 字段 | 类型 | 说明 |
|------|------|------|
| `space_id` | bigint | 所属 Space |
| `auto_mode_remaining_rounds` | integer? | Auto-mode 剩余轮数（`null`=禁用，`>0`=活跃） |
| `turns_count` | integer | 已完成的 turn 总数（统计用） |
| `group_queue_revision` | bigint | UI 乱序保护（忽略过期 queue_updated 事件） |

### ConversationRound（回合运行态）

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | uuid | round ID（结构化 round token） |
| `conversation_id` | bigint | 所属 Conversation |
| `status` | string | 生命周期：active / finished / superseded / canceled |
| `scheduling_state` | string? | active 时：ai_generating / failed |
| `current_position` | integer | 当前在队列中的 position（0-based） |
| `finished_at` | datetime? | 结束时间（非 active 时） |
| `ended_reason` | string? | 结束原因（可选） |
| `trigger_message_id` | bigint? | 触发消息（可选，debug） |
| `metadata` | jsonb | 诊断元数据（避免承载关键一致性语义） |

### ConversationRoundParticipant（回合队列）

| 字段 | 类型 | 说明 |
|------|------|------|
| `conversation_round_id` | uuid | 所属 round |
| `position` | integer | 0-based position（unique per round） |
| `space_membership_id` | bigint | 成员 |
| `status` | string | pending / spoken / skipped |
| `spoken_at` | datetime? | 发言时间 |
| `skipped_at` | datetime? | 跳过时间 |
| `skip_reason` | string? | 跳过原因 |

### ConversationRun（任务记录）

使用 `kind` 字段区分类型（不再使用 STI）：

补充：TurnScheduler 创建的 run 会写入 `conversation_round_id`；独立 run（`regenerate` / `force_talk`）允许为空（清理旧 round 后也可能变为 `nil`）。

| kind | 说明 | 执行方式 |
|------|------|---------|
| `auto_response` | AI 角色自动响应 | LLM 调用 |
| `copilot_response` | AI 替人类发言（Copilot） | LLM 调用 |
| `regenerate` | 重新生成消息 | LLM 调用 |
| `force_talk` | 强制指定角色发言 | LLM 调用 |

## 核心组件

### 1) TurnScheduler

入口点：`playground/app/services/turn_scheduler.rb`

提供简洁的 API：

```ruby
TurnScheduler.start_round!(conversation)
TurnScheduler.advance_turn!(conversation, speaker_membership)
TurnScheduler.stop!(conversation)
TurnScheduler.state(conversation)  # => RoundState
TurnScheduler.next_speaker(conversation)  # => SpaceMembership
TurnScheduler.queue_preview(conversation)  # => [SpaceMembership, ...]
```

### 2) Commands (操作)

位于 `playground/app/services/turn_scheduler/commands/`

| Command | 职责 |
|---------|------|
| `StartRound` | 开始新回合，计算队列，调度首个发言 |
| `AdvanceTurn` | 消息创建后推进回合 |
| `ScheduleSpeaker` | 为当前发言者创建适当的 ConversationRun |
| `SkipCurrentSpeaker` | 当前 speaker 不再可调度时，自动跳过并继续 |
| `StopRound` | 停止回合并清理状态 |
| `HandleFailure` | 处理调度失败 |
| `RetryCurrentSpeaker` | 失败后重试当前 speaker（同 round 继续） |

### 3) Queries (查询)

位于 `playground/app/services/turn_scheduler/queries/`

| Query | 职责 |
|-------|------|
| `NextSpeaker` | 根据 reply_order 策略选择下一个发言者 |
| `QueuePreview` | 获取即将发言的成员列表（用于 UI） |

### 4) State (状态值对象)

`TurnScheduler::State::RoundState` 封装回合状态：

```ruby
state = TurnScheduler.state(conversation)
state.round_queue_ids   # => [1, 2, 3] (membership IDs)
state.round_position    # => 0
state.round_spoken_ids  # => [1]
state.current_round_id  # => "uuid"
state.current_speaker_id # => 1
```

### 5) RunPlanner (简化版)

实现：`playground/app/services/conversations/run_planner.rb`

在新架构中，RunPlanner 只负责：
- `create_scheduled_run!`：用于“显式重试/重新排队某个 speaker”（例如非 TurnScheduler failed-state 的 Retry），创建指定 kind 的 queued run 并 kick job
- `plan_force_talk!`：手动触发指定 speaker（创建 `force_talk`）
- `plan_regenerate!`：重新生成（创建 `regenerate`）
- （已移除）`plan_user_turn!`：Group `last_turn` regenerate 现在直接走 TurnScheduler 的 StartRound（ActivatedQueue 语义）

### 6) RunFollowups (简化版)

实现：`playground/app/services/conversations/run_executor/run_followups.rb`

在新架构中，RunFollowups 只负责：
- 如果有已存在的 queued run，kick 它

**已移除**（由 TurnScheduler 处理）：
- turns_count 递增 - 现在由 `AdvanceTurn` 处理
- 资源递减 - 现在由 `AdvanceTurn` 处理
- 下一轮调度 - 现在由 Message callback 触发

## Auto Mode vs Copilot

| 特性 | Auto Mode | Copilot |
|------|-----------|---------|
| 用途 | AI-to-AI 对话（人类可观察/参与） | AI 替用户发言 |
| 范围 | Conversation 级别 | SpaceMembership 级别 |
| 限制 | 1-10 轮 | 1-10 步 |
| 可用性 | 仅群聊 | Human with persona |
| 人类处理 | 普通人类不入队（仅作触发器） | 算作 AI 参与者 |

**两者互斥（规范）**：
- Auto mode：人类是 Observer（skip human turn）
- Copilot：人类被当作“可自动发言的参与者”
- 启用其一会自动关闭另一种（由 controller/前端强制）

## User Input Priority

当用户发送消息时：
1. `Messages::Creator` 取消所有 queued runs
2. 创建用户消息
3. `after_create_commit` 触发 `AdvanceTurn`
4. 调度器根据当前状态安排下一个发言

这确保用户消息始终优先，打断任何正在进行的自动对话。

## 边界情况

### 成员变化

当成员加入/离开/状态变化时：
- `SpaceMembership` 的 `after_commit` 回调会广播 queue_updated，刷新 UI 预览
- 当前 round 的 `round_queue_ids` 不会 mid-round 重算（队列已持久化）
- 若成员变更导致其不再可调度、且恰好是 current speaker：会自动跳过到下一位（见 `SkipCurrentSpeaker`）；若 run 已在 running，会先 `request_cancel` 并确保不会落 Message，再继续推进

### 并发处理

- 数据库唯一索引确保每个 conversation 最多 1 个 queued run
- `create_exclusive_queued_run!` 使用 first-one-wins 语义
- 消息创建使用 seq 冲突重试机制

### Run 被跳过时

当 `RunClaimer` 因以下原因跳过 run 时：
- `expected_last_message_mismatch`（消息已更新）
- `missing_speaker`（发言者不存在）

调度器会被通知继续调度下一个发言者，防止对话卡住。

## 可靠性机制

### 1. 错误处理分层

```
时间线
├── 0s:     Run 开始执行
│
├── 30s:    Typing Indicator 显示 Stuck Warning
│           用户可选 [Retry] [Cancel]
│
├── 失败时:  显示 Error Alert（阻塞性）
│           只有 [Retry] 选项
│           不会自动推进到下一个 turn
│
└── 10min:  Reaper 自动标记为 failed（安全网）
            仅用于无人值守的场景
```

### 2. 失败后不自动推进

当 run 失败时（LLM 错误、异常、超时等）：
- **不会** 自动调度下一个 turn
- 在输入框上方显示 **Error Alert**
- 若要继续 **同一个 round**：用户必须点击 **Retry**
- 若用户发送新的 **真人输入**：后端会先执行 **隐式 StopRound**（重置 blocked round，并关闭 Auto mode / Copilot），再按该输入开启新 round（`reply_order != manual` 时）

原因：
- 防止级联失败
- 保护对话状态完整性
- 给用户决策权

### 2.1 scheduler failed-state（`scheduling_state=failed`）

对 TurnScheduler 安排的 run（`run.debug["scheduled_by"] == "turn_scheduler"`）：
- 失败后会把当前 active round 的 `conversation_rounds.scheduling_state` 置为 `failed`，并**保留 round 状态**（不清空队列/participants）
- Retry 的语义是：**重试当前 speaker（同 round 继续）**

### 3. Stuck Warning UI

当 typing indicator 显示超过 30 秒时：
- 显示警告：「AI response seems stuck」
- 提供两个按钮：
  - **Retry**：强制重试当前任务
  - **Cancel**：取消并清除队列（需确认）

### 4. Error Alert UI

当 run 失败（而非卡住）时：
- 在输入框上方显示红色 alert
- 只提供 **Retry** 按钮（Cancel 没意义因为状态已损坏）
- 重试成功后自动隐藏

### 5. Reaper 安全网

`ConversationRunReaperJob`：
- 每个 run 启动时调度，10 分钟后执行
- 仅处理卡在 running 状态且心跳超时的 run
- 作为最后防线，正常情况下不应触发

### 6. Runs Debug Panel

在左侧边栏显示最近 15 条 runs：
- 显示 run 类型图标
- queued/running 状态的 runs 显示「Cancel」按钮
- 点击查看详细信息（包含 LLM prompt、error 等）

### 7. 错误码说明

| 错误码 | 含义 | 用户提示 |
|--------|------|----------|
| `stale_timeout` | Reaper 超时杀死 | AI response timed out |
| `no_provider_configured` | 未配置 LLM | Please add provider in Settings |
| `connection_error` | 网络连接失败 | Failed to connect to LLM |
| `http_error` | LLM API 返回错误 | LLM provider error |
| `exception` | 未知异常 | AI response failed |
