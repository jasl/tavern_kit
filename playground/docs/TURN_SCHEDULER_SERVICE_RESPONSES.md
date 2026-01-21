# TurnScheduler ServiceResponse 约定（GitLab 风格）

本项目在服务层统一采用 GitLab 风格的 service 约定（预 1.0，允许破坏性改动，因此不保留旧入口）：

- `TurnScheduler::Commands::*`：对外提供 `.execute(...)`，返回结构化 `ServiceResponse`
- `TurnScheduler::Queries::*`：对外提供 `.execute(...)`，返回结构化查询结果（Array/Struct/Model 等）

`ServiceResponse` 定义在 `app/services/service_response.rb`。

## 统一字段

- `status`: `:success` / `:error`
- `reason`: `Symbol`（稳定枚举，供 UI 分支、debug panel 展示、统计分桶）
- `payload`: `Hash`（结构化数据，避免解析日志）

## 已迁移的命令与 reason 约定

> 说明：以下 reason 代表“服务层语义”，并不直接等同于 `conversation_events.reason`。
> 事件流建议仍以 `event_name` 为主，`reason` 作为二级维度。

### `TurnScheduler::Commands::AdvanceTurn.execute`

常见 `reason`：

- `:missing_speaker_membership`：调用缺少 speaker context
- `:ignored_stale_run_message`：消息来自旧 round/run，忽略
- `:noop_failed_state`：round 处于 `failed`，不自动推进
- `:ignored_independent_run_message`：消息来自独立 run（例如 regenerate），忽略
- `:noop_idle_no_trigger`：idle 且不满足 start round 条件
- `:round_started` / `:round_not_started`
- `:advanced_paused`：paused 状态下推进 position（不 schedule 下一位）
- `:advanced`：正常推进

`payload`：至少包含 `advanced: true/false`。

### `TurnScheduler::Commands::StartRound.execute`

- `:no_eligible_speakers`：无可调度 speaker
- `:round_started`：成功启动 round

`payload`：包含 `started: true/false`，成功时包含 `round_id`、`speaker_id`、`queue_size`。

### `TurnScheduler::Commands::PauseRound.execute`

- `:no_active_round`
- `:noop_failed_round`：failed round 不进入 paused
- `:already_paused`
- `:paused`

`payload`：包含 `paused: true/false`，可能包含 `round_id`。

### `TurnScheduler::Commands::ResumeRound.execute`

- `:no_active_round`
- `:noop_not_paused`
- `:blocked_active_run`：存在 active run，避免把 round 状态切到 `ai_generating` 但无法 schedule
- `:blocked_queue_slot`：run 队列被占用（queued slot taken）
- `:resumed`
- `:round_complete`：已无可调度 speaker，完成 round（可选启动新 round）

`payload`：包含 `resumed: true/false`，可能包含 `started_new_round`。

### `TurnScheduler::Commands::SkipCurrentSpeaker.execute`

- `:no_active_round`
- `:missing_speaker_id`
- `:noop_not_current_speaker`
- `:stale_round`
- `:blocked_running_run`：当前 speaker 正在 running 且未选择 cancel
- `:advanced`

`payload`：包含 `advanced: true/false`，可能包含 `round_id`、`speaker_id`。

### `TurnScheduler::Commands::HandleFailure.execute`

- `:no_active_round`
- `:missing_run`（`status=:error`）
- `:noop_not_scheduler_run`
- `:noop_not_current_speaker`
- `:noop_missing_round_id`
- `:noop_stale_round`
- `:handled`

`payload`：包含 `handled: true/false`，成功时包含 `round_id`、`run_id`、`disabled_auto_memberships_count`。

## UI 使用建议

1. 先用 `payload` 的布尔字段作为“是否成功”的单一判断（例如 `payload[:paused]`）。
2. 仅在提示文案/调试 UI 中使用 `reason` 做解释（不要影响原本的执行分支）。
