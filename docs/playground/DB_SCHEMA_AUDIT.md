# 数据库字段专项审计（schema.rb + 迁移）

Last updated: 2026-01-12

目标：对 `playground/db/schema.rb` 与 `playground/db/migrate/*` 做一次“字段可简化/可删”的专项审计，并把结论落盘，降低后续重构/迭代时的误判与重复劳动。

⚠️ 重要前提更新：目前数据库已清空，因此我们不需要做兼容性/回填/保守迁移；可以选择“激进但更干净”的 schema 重构路线。

建议：本文件现在只保留“审计结论 + 指向重构计划”的作用；更详细的资料与计划请看：
- `docs/playground/TURN_SCHEDULER_FULL_AUDIT_PLAN.md`

## 范围与事实边界

- 当前 Playground 以初始化迁移为基线：`playground/db/migrate/20260108045602_init_schema.rb`
  - 后续可能会添加少量迁移（例如 round schema 抽离、清理 job 配套字段等）。
  - 风险：**schema 的字段/注释来自初始设计**，在多轮重构后容易出现“代码已变、注释未变”的漂移，因此需要配套“资料落盘 + 测试固定行为”。
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
  - 或者该字段明确为历史兼容字段，且已经有迁移路径（数据回填/替换字段）；
  - 或者字段是冗余派生值，移除后不会破坏关键路径与一致性（需要额外的回归测试）。

## 关键发现

### 1) Round 运行态已按“激进方案”完成重构

在 DB 已清空前提下，我们已选择并落地了“激进但更干净”的路线：

- `conversations` 不再承载 round runtime state 列（已删除旧列）
- round runtime state 变成一等实体：`conversation_rounds` + `conversation_round_participants`
- `conversation_runs` 用结构化外键绑定 round：`conversation_runs.conversation_round_id`（nullable，`on_delete: :nullify`）

### 2) 清理策略：保留最近 24h + 每日定时清理

为了控制 `conversation_rounds` 增长，我们已落地：

- Round 记录保留但可清理（保留最近 24 小时）
- 每日定时执行清理 job
- 清理后允许持久化记录（runs/messages）与 round 解绑（FK nullify）

## 已采取动作（本次修正）

- 已落地 round schema 与代码改造（并通过 Playground 全量测试验证）：
  - 新表/新外键：`playground/db/migrate/20260112142430_add_conversation_rounds.rb`
  - 删除旧列：`playground/db/migrate/20260112180000_drop_conversation_round_state_columns.rb`
  - 清理 job：`playground/app/jobs/conversation_round_cleanup_job.rb` + `playground/config/recurring.yml`

## 后续建议（需要单独评估，暂不在本轮落地）

- 文档口径对齐：`CONVERSATION_AUTO_RESPONSE.md` / `CONVERSATION_RUN.md` / `FRONTEND_TEST_CHECKLIST.md`
