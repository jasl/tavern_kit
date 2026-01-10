# Conversation 自动回复与调度（Unified Turn Scheduler）

本文档描述 Playground 中 **Space/Conversation** 的统一回合调度机制。

另见：
- `SPACE_CONVERSATION_ARCHITECTURE.md`
- `CONVERSATION_RUN.md`
- `BRANCHING_AND_THREADS.md`
- `docs/spec/SILLYTAVERN_DIVERGENCES.md`

## 设计原则

- **单一队列**：所有参与者（AI 角色、Copilot 人类、普通人类）在同一个有序队列中
- **消息驱动推进**：`Message#after_create_commit` 触发回合推进
- **自然人类阻塞**：调度器等待人类消息创建，不需要特殊处理
- **Auto Mode 跳过**：延迟任务在 auto mode 中跳过未响应的人类
- **不使用 placeholder message**：LLM 流式内容只写入 typing indicator，生成完成后一次性创建最终 Message

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
│  → ConversationScheduler.advance_turn!(speaker_membership)       │
└───────────┬─────────────────────────────────────────────────────┘
            │
            v
┌─────────────────────────────────────────────────────────────────┐
│                ConversationScheduler                             │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Turn Queue State (stored in conversation.turn_queue_state)│  │
│  │  {                                                       │    │
│  │    "queue": [member_id1, member_id2, ...],              │    │
│  │    "position": 0,                                        │    │
│  │    "spoken": [member_id1],                               │    │
│  │    "round_id": "uuid"                                    │    │
│  │  }                                                       │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                  │
│  → advance_turn!        Mark spoken, move position, schedule    │
│  → start_round!         Calculate queue, reset state            │
│  → schedule_current_turn!                                        │
│  → recalculate_queue!   Mid-round adjustment                    │
└───────────┬─────────────────────────────────────────────────────┘
            │
            v
┌─────────────────────────────────────────────────────────────────┐
│                  schedule_current_turn!                          │
│                                                                  │
│  AI → ConversationRun::AutoTurn → ConversationRunJob            │
│  Copilot → ConversationRun::CopilotTurn → ConversationRunJob    │
│  Human + Auto → ConversationRun::HumanTurn + HumanTurnTimeoutJob│
│  Human only → wait for message                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 回合生命周期

### 1. 回合开始

回合在以下情况下开始：
- 用户启用 Auto Mode → `start_round!`
- 用户启用 Copilot → `start_round!`
- 用户发送消息（无活跃回合时）→ `start_round_after_message!`

### 2. 回合推进

每次消息创建都会触发 `advance_turn!`：

```ruby
# Message model
after_create_commit :notify_scheduler_turn_complete

def notify_scheduler_turn_complete
  return if system?
  ConversationScheduler.new(conversation).advance_turn!(space_membership)
end
```

`advance_turn!` 做以下事情：
1. 标记发言者为"已发言"
2. 递增 `conversation.turns_count`
3. 递减资源（copilot steps, auto mode rounds）
4. 移动到下一个发言者
5. 调用 `schedule_current_turn!` 安排下一个发言

### 3. 发言调度

`schedule_current_turn!` 根据当前发言者类型采取不同行动：

| 发言者类型 | 行动 | Run 类型 |
|-----------|------|---------|
| AI 角色 | 创建 Run，启动生成 | `ConversationRun::AutoTurn` |
| Copilot 人类 | 创建 Run，AI 替用户发言 | `ConversationRun::CopilotTurn` |
| 普通人类 + Auto Mode | 创建 HumanTurn run + 超时任务 | `ConversationRun::HumanTurn` |
| 普通人类（无 Auto） | 等待用户发送消息 | 无 |

### 4. 回合结束

当队列位置超过队列长度时，回合结束。调度器会：
1. 递减 auto mode rounds（如果启用）
2. 如果 auto-scheduling 仍然启用，开始新回合
3. 否则清除队列状态

## Initiative (先攻值)

每个 `SpaceMembership` 有 `talkativeness_factor` (0.0-1.0)，决定在 turn queue 中的优先级：
- **高 talkativeness**：优先发言（类似游戏中的高先攻值）
- **低 talkativeness**：后发言
- **相同 talkativeness**：按 `position` 排序

## 数据模型

### Conversation（消息时间线 + 调度状态）

| 字段 | 类型 | 说明 |
|------|------|------|
| `space_id` | bigint | 所属 Space |
| `auto_mode_remaining_rounds` | integer? | Auto-mode 剩余轮数（`null`=禁用，`>0`=活跃） |
| `turns_count` | integer | 已完成的 turn 总数（统计用） |
| `turn_queue_state` | jsonb | 调度器队列状态 |

### turn_queue_state 结构

```json
{
  "queue": [1, 2, 3],      // 有序的 membership IDs
  "position": 0,            // 当前发言者索引
  "spoken": [1],            // 本回合已发言的 membership IDs
  "round_id": "uuid"        // 回合唯一标识符
}
```

## 核心组件

### 1) ConversationScheduler

实现：`playground/app/services/conversation_scheduler.rb`

关键方法：
- `start_round!`：开始新回合，计算队列，调度首个发言
- `advance_turn!(speaker_membership)`：消息创建后推进回合
- `schedule_current_turn!`：安排当前发言者的发言
- `skip_human_if_eligible!(membership_id, round_id)`：跳过未响应的人类
- `recalculate_queue!`：环境变化时重新计算队列
- `clear!`：清除队列状态

### 2) ConversationRun STI (Single Table Inheritance)

所有 turn/task 类型都继承自 `ConversationRun` 基类：

| 类型 | 说明 | 执行方式 |
|------|------|---------|
| `ConversationRun::AutoTurn` | AI 角色自动响应 | LLM 调用 |
| `ConversationRun::CopilotTurn` | AI 替人类发言（Copilot） | LLM 调用 |
| `ConversationRun::HumanTurn` | 人类发言占位（Auto Mode） | 等待超时或用户输入 |
| `ConversationRun::Regenerate` | 重新生成消息 | LLM 调用 |
| `ConversationRun::ForceTalk` | 强制指定角色发言 | LLM 调用 |

**优势**：
- 统一的任务追踪和调试界面
- 每种类型可有独立逻辑
- HumanTurn 自然集成到队列中

### 3) HumanTurnTimeoutJob

实现：`playground/app/jobs/human_turn_timeout_job.rb`

当 auto mode 启用且轮到人类发言时，调度器会：
1. 创建 `ConversationRun::HumanTurn` run（status: queued）
2. 调度 `HumanTurnTimeoutJob`（延迟 = delay + 10s）
3. 如果人类在此期间发送消息，HumanTurn 被标记为 succeeded
4. 如果超时，任务将 HumanTurn 标记为 skipped，推进到下一个发言者

### 4) StaleRunsCleanupJob

实现：`playground/app/jobs/stale_runs_cleanup_job.rb`

定期检查并清理卡住的 runs：
- 检测 `running` 状态超过 30 秒无 heartbeat 的 runs
- 标记为 failed，通知调度器继续
- 配置在 `config/recurring.yml`（每分钟运行）

### 5) RunPlanner (简化版)

实现：`playground/app/services/conversations/run_planner.rb`

在新架构中，RunPlanner 只负责：
- `create_scheduled_run!`：被 ConversationScheduler 调用，创建指定 STI 类型的 run
- `plan_force_talk!`：手动触发指定 speaker（创建 `ForceTalk`）
- `plan_regenerate!`：重新生成（创建 `Regenerate`）
- `plan_user_turn!`：用于删除-重新生成场景（创建 `AutoTurn`）

**已移除**：
- `plan_from_user_message!` - 现在由 Message callback + Scheduler 处理
- `plan_auto_mode_start!` - 现在由 `start_round!` 处理
- `plan_copilot_start!` - 现在由 `start_round!` 处理

### 6) RunFollowups (简化版)

实现：`playground/app/services/conversations/run_executor/run_followups.rb`

在新架构中，RunFollowups 只负责：
- 如果有已存在的 queued run，kick 它

**已移除**：
- turns_count 递增 - 现在由 `advance_turn!` 处理
- 资源递减 - 现在由 `advance_turn!` 处理
- 下一轮调度 - 现在由 Message callback 触发

## Auto Mode vs Copilot

| 特性 | Auto Mode | Copilot |
|------|-----------|---------|
| 用途 | AI-to-AI 对话（人类可观察/参与） | AI 替用户发言 |
| 范围 | Conversation 级别 | SpaceMembership 级别 |
| 限制 | 1-10 轮 | 1-10 步 |
| 可用性 | 仅群聊 | Human with persona |
| 人类处理 | 延迟跳过 | 算作 AI 参与者 |

**两者可同时启用**：
- Copilot user 被视为 AI participant，自动发言
- 普通人类在 auto mode 中会被延迟跳过

## User Input Priority

当用户发送消息时：
1. `Messages::Creator` 清除调度器队列状态
2. 取消所有 queued runs
3. 创建用户消息
4. `after_create_commit` 触发 `advance_turn!`
5. 调度器开始新回合，安排 AI 响应

这确保用户消息始终优先，打断任何正在进行的自动对话。

## 边界情况

### 成员变化

当成员加入/离开/状态变化时：
- `SpaceMembership` 的 `after_commit` 回调调用 `scheduler.recalculate!`
- `recalculate_queue!` 重新计算队列，保留已发言记录
- 如果当前发言者被移除，移到下一个发言者

### 并发处理

- 数据库唯一索引确保每个 conversation 最多 1 个 queued run
- `create_exclusive_queued_run!` 使用 first-one-wins 语义
- 消息创建使用 seq 冲突重试机制

### Auto Mode 中的人类跳过

- 创建 `ConversationRun::HumanTurn` 来追踪人类回合
- 跳过延迟 = `space.auto_mode_delay_ms` + 10 秒
- 如果人类发送消息，HumanTurn 被标记为 succeeded
- 如果超时，HumanTurn 被标记为 skipped，推进到下一个发言者
- 所有状态变化都在 Runs Panel 中可见

### Copilot 在 Auto Mode 中启用

当 Auto Mode 运行时，人类启用 Copilot：
1. **当前发言者启用**：取消 HumanTurn（如果存在），立即创建 `CopilotTurn`
2. **非当前发言者启用**：等到轮到该成员时才创建 run
3. **新加入的 Copilot 成员**：延迟到下一轮才加入队列（避免冲突）

### Run 被跳过时

当 `RunClaimer` 因以下原因跳过 run 时：
- `expected_last_message_mismatch`（消息已更新）
- `missing_speaker`（发言者不存在）

调度器会被通知继续调度下一个发言者（`schedule_current_turn!`），防止对话卡住。

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
- 用户必须点击 **Retry** 才能继续

原因：
- 防止级联失败
- 保护对话状态完整性
- 给用户决策权

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

**注意**：`StaleRunsCleanupJob` 已禁用（太激进）

### 6. Runs Debug Panel

在左侧边栏显示最近 15 条 runs：
- 支持按类型过滤（隐藏 HumanTurn）
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
