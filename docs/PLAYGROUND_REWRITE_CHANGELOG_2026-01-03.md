# Playground 大重写变更说明（Space + Conversation Big‑Bang）

日期：2026‑01‑03（更新：2026‑01‑04）

本次改动是一次 **big‑bang** 重写：彻底移除旧的 Room/Membership/RoomRun 架构，替换为 **Space + Conversation + ConversationRun**。不提供任何向后兼容；数据库可直接 drop 后重建。

---

## 2026‑01‑04 更新：Conversation 分支 + Membership 生命周期

### 1. Conversation 分支树结构

新增字段支持 SillyTavern-style 分支（"clone chat up to a message and switch to it"）：

**conversations 表：**
- `parent_conversation_id`：父会话引用
- `root_conversation_id`：根会话引用（用于查询同一棵树的所有分支）
- `forked_from_message_id`：分支点消息
- `visibility`：可见性枚举（`shared` / `private`）

**messages 表：**
- `origin_message_id`：克隆来源消息（用于追溯 branch 中的消息来源）

**数据不变量：**
- 根会话：`root_conversation_id == id`
- 子会话：`root_conversation_id` 继承自父会话
- `forked_from_message` 必须属于 `parent_conversation`

### 2. Conversation::Forker 服务

新增 `app/services/conversation/forker.rb` 作为分支操作的唯一入口：

```ruby
Conversation::Forker.new(
  parent_conversation: conversation,
  fork_from_message: message,
  kind: "branch",
  created_by_membership: membership,
  visibility: "shared"
).call
```

行为：
- 仅允许 Playground 空间创建 branch
- 事务内创建子会话 + 克隆消息前缀 + 克隆 swipes
- 保留 `seq`、`origin_message_id`、`active_message_swipe_id` 指针

路由：`POST /conversations/:id/branch`（body: `{ message_id: xxx }`）

### 3. 非末尾消息保护（Timelines 语义）

对齐 SillyTavern Timelines 扩展的行为：

**Regenerate 非末尾消息：**
- 自动创建 branch（fork_from_message = target_message）
- 重定向到新分支
- 在新分支中执行 regenerate
- 原会话保持不变

**Swipe 非末尾消息：**
- 阻止操作
- 提示用户"需要 branch 才能切换"

### 4. Membership 生命周期锚定（Author Anchoring）

将 membership 设计为"作者锚点"：移除成员时不删除记录，保留历史消息的作者引用。

**新增字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `status` | enum | `active` / `removed` |
| `participation` | enum | `active` / `muted` / `observer` |
| `removed_at` | datetime | 移除时间 |
| `removed_by_id` | bigint | 操作者（User FK） |
| `removed_reason` | string | 移除原因 |

**Status（生命周期）：**
- `active`：活跃成员，可访问空间
- `removed`：已离开/被踢出，无法访问但消息保留

> **未来扩展**：`banned`（禁止重新加入）、`archived`（空间归档）

**Participation（参与度）：**
- `active`：完全参与，包含在 AI speaker 选择中
- `muted`：不自动选择，但可见且可手动触发
- `observer`：仅观察（未来多人空间预留）

**Scopes：**
- `active`：`status = 'active'`
- `participating`：`status = 'active' AND participation = 'active'`
- `removed`：`status = 'removed'`
- `muted`：`participation = 'muted'`

**API：**
```ruby
membership.remove!(by_user: user, reason: "Kicked by admin")
```

**展示逻辑：**
- `membership.display_name` 对 removed 成员返回 `"[Removed]"`
- 历史消息仍然显示原始作者（通过保留的 membership 记录）

### 5. 移除废弃的 `muted` 布尔字段

`muted` 布尔字段被 `participation` 枚举取代：

| 旧字段 | 新字段 |
|--------|--------|
| `muted: false` | `participation: 'active'` |
| `muted: true` | `participation: 'muted'` |

相关更新：
- `join_include_muted` → `join_include_non_participating`
- `join_exclude_muted` → `join_exclude_non_participating`
- `muted?` → `participation_muted?`
- `!muted?` → `participation_active?`

### 6. 分支 UI

**消息操作菜单：**
- 新增 "Branch from here" 按钮（仅 Playground 空间）

**会话顶部导航栏（分支会话）：**
- "Back to parent" 链接
- 显示 "Branched from message #N"

---

## 2026‑01‑04 更新：Space STI 重构

### 变更概述

将 `Space` 的 `kind` 枚举（`solo` / `multi`）重构为 **Single Table Inheritance (STI)**：

- `Spaces::Playground`：原 `solo`，单人角色扮演（一个人类 + 多个 AI 角色）
- `Spaces::Discussion`：原 `multi`，多人讨论（多个人类 + 多个 AI 角色，未来功能预留）

同时将 `owner_user_id` 重命名为 `owner_id`。

### 数据库变更

- 移除 `kind` 列，新增 `type` 列（STI 标识）
- 将 `owner_user_id` 重命名为 `owner_id`
- 移除数据库层的 check constraints，改为模型层验证

### 代码变更

**模型层：**
- 新增 `app/models/spaces/playground.rb`（单人类限制验证）
- 新增 `app/models/spaces/discussion.rb`（预留）
- `Space` 基类：移除 `kind` 枚举，新增 STI scopes（`playgrounds`、`discussions`）和类型检查方法（`playground?`、`discussion?`）
- `SpaceMembership`：`solo_space_allows_single_human_membership` → `playground_space_allows_single_human_membership`

**控制器层：**
- `SpacesController` → `PlaygroundsController`
- `Spaces::*Controller` → `Playgrounds::*Controller`
- 路由从 `/spaces` 改为 `/playgrounds`

**视图层：**
- `views/spaces/` → `views/playgrounds/`
- 所有 `space_*_path` helper 改为 `playground_*_path`
- 移除创建表单中的 `kind` 字段选择（直接创建 Playground）

### 行为变更

- Playground 空间强制执行 **单人类成员** 约束
- 分支对话（branch）仅在 Playground 空间中允许
- Discussion 空间预留用于未来多人聊天功能

---

## 目标与边界

- **正交拆分**（唯一真相）：
  - **Space**：权限 + 参与者 + 默认策略/设置（包含 prompt preset / world info 等配置入口）。
  - **Conversation**：消息时间线（timeline）。
  - **ConversationRun**：运行态执行状态机（排队/执行/取消/失败/自愈等）。
- **不做数据迁移**：旧数据不迁移，旧 schema 不保留。
- **不再出现 legacy 字段**：例如 `current_speaker_id`、`generating_status` 这类“运行态写在配置表/消息表上”的字段不再存在。

## 目录结构与代码入口

- `playground/`：当前 Rails app（新架构）
- `playground.old/`：旧实现归档（只用于参考，不保证可运行）

核心入口（按链路）：

- Prompt 构建：
  - `playground/app/services/context_builder.rb`（薄封装：负责 history cutoff + card mode 映射）
  - `playground/app/services/prompt_builder.rb`（Playground → TavernKit 的适配层）
- Run 调度：
  - `playground/app/services/conversation/run_planner.rb`
  - `playground/app/services/conversation/run_executor.rb`
  - `playground/app/jobs/conversation_run_job.rb`
  - `playground/app/jobs/conversation_run_reaper_job.rb`
- 实时与 UI：
  - `playground/app/channels/conversation_channel.rb`（conversation scoped JSON streaming）
  - Turbo Streams（消息 DOM append/replace，来自 Message 广播）

## 数据库层：从 Room 迁移到 Space/Conversation 基线

新表（核心）：

- `spaces`：空间（权限/参与者/默认策略）
- `space_memberships`：空间内身份（human / character / copilot）
- `conversations`：对话时间线（root/branch/thread）
- `messages`：消息（belongs_to conversation + space_membership，稳定排序 `seq`）
- `message_swipes`：消息的多版本（regenerate）
- `conversation_runs`：运行态执行单元（queued/running/succeeded/failed/canceled/skipped）

关键一致性/并发约束：

- `messages.seq`：
  - `(conversation_id, seq)` 唯一索引
  - 通过事务 + `conversation.with_lock` 分配 `max(seq)+1`，确保并发下确定性
- `conversation_runs`：
  - `UNIQUE(conversation_id) WHERE status='running'`
  - `UNIQUE(conversation_id) WHERE status='queued'`（单槽队列：后写覆盖 queued）

## 路由与控制器：最小 Solo UI 流程

新路由（核心，2026-01-04 更新为 playgrounds）：

- `resources :playgrounds`（`index/new/create/show/edit/update/destroy`）
  - `resources :space_memberships`（create/update/destroy：加角色、mute、排序）
  - `resources :conversations`（create root）
  - `resources :copilot_candidates`（AI 建议生成）
  - `resource :prompt_preview`（Prompt 预览）
- `resources :conversations`（show）
  - `resources :messages`（create user message）
  - `post :branch_from_message`（ST-style branching）

关键行为：

- 创建 Playground 时自动创建 owner 的 human membership（通过 `Space.create_for`）。
- Playground 约束：模型层保证 **只能有一个 human membership**（`SpaceMembership` 验证）。
- `branch_from_message`：仅允许 Playground 空间，非 Playground 返回 422。

## Prompt：全面收敛到 TavernKit（避免双份 prompt 漂移）

### 1) ContextBuilder 变成薄封装（主回复走它）

- 负责：
  - regenerate 的 history cutoff（`seq < target.seq`）
  - branch/preview 的 history cutoff（`seq <= cursor.seq`）
  - card mode 映射（swap / join_* → TavernKit join 模式）
- 实际 prompt 生成委托给 `PromptBuilder`（Playground 适配层）→ `TavernKit.build(...).to_messages`

### 2) Copilot 继续直接使用 PromptBuilder

- `playground/app/services/conversation/copilot_candidate_generator.rb` 直接走 `PromptBuilder`。
- 主回复与 copilot 共享同一 TavernKit prompt 引擎（差异仅在 speaker/user 视角与参数）。

### 3) Space.settings 的 Prompt 配置入口

- `space.settings["preset"]` 对应 `TavernKit::Preset`（system/main prompt、PHI、Author’s Note、trimming、format 等）
- `space.settings["world_info_*"]` 对应 World Info 行为与预算
- `space.settings["scenario_override"]` / `join_prefix` / `join_suffix` 等用于 group/join 相关行为

说明：

- 后端已将更多 TavernKit preset 项暴露到 schema 与 PromptBuilder 映射中；前端可按需逐步做 UI。
- 表单提交是字符串的场景（非 schema-renderer）在 controller 边界做整数归一，避免业务层出现 `.to_i` 到处散落。

相关对接追踪文档：

- `docs/SCHEMA_PACK_PROMPT_BUILDER_INTEGRATION.md`

## Run 调度：RunPlanner + RunExecutor（conversation scoped）

### Planner（写入 queued / 取消 running / debounce）

- 用户发送消息：
  - 若 `reply_order == manual`：不自动生成
  - 否则选 speaker，计算 `run_after = now + user_turn_debounce_ms`，upsert queued，然后 kick job
- regenerate：
  - 标记 running 的 `cancel_requested_at`
  - 创建 regenerate queued（debug 里记录 `target_message_id`）
- auto-mode：
  - 成功后按 `auto_mode_delay_ms` 计划 followup（受 allow_self_responses、reply_order 影响）

### Executor（claim queued → running → 生成 → 持久化）

核心原则：**无 placeholder message**（流式只更新 typing indicator；完成后一次性写入消息或 swipe）。

执行流程（简化）：

1. 事务内 claim queued → running（并检查 expected_last_message 防污染）
2. `ConversationChannel` 广播 typing start + stream chunks（JSON）
3. 调用 LLM（ActiveJob 中执行）
4. 成功后：
   - normal：创建 assistant Message（append Turbo Stream）
   - regenerate：为 target message 添加 swipe（replace Turbo Stream）
5. 标记 run succeeded/failed/canceled；必要时 kick followups

### Stale 自愈

running run 会被 reaper 检测：

- stale → 标记 failed
- 若存在 queued → 继续 kick

## 分支与线程：Conversation.kind 的语义

- `root`：主时间线
- `branch`：ST-style clone-to-point（克隆 `seq <= fork_point.seq`，保留 `seq`，克隆 swipes + active_swipe）
- `thread`：Discord-style 并行时间线（继承 space 权限，不克隆历史）

详细定义见：

- `docs/BRANCHING_AND_THREADS.md`

## 文档更新检查（本次同步修正）

- `docs/CONVERSATION_AUTO_RESPONSE.md`：移除旧的 `system_prompt` 术语，改为以 `preset.*` 为主的配置描述。
- `docs/PLAYGROUND_REWRITE_PLAN.md`：明确标记为归档历史文档，并指向本 changelog。

## 已知缺口 / 后续建议

- Space 的“高级设置 UI”：建议复用 schema pack 的 schema-renderer（类似 settings/characters/edit）渲染 `space` 全量字段，避免手写表单导致类型漂移与字段遗漏。
- `TavernKit::Preset` 的 `prompt_entries` / `instruct` / `context_template` 等更高级结构：目前未在 Playground schema 中完整暴露（可后续按需扩展）。
- Memory / RAG：schema 预留入口但默认未实现。

## 本地验证命令

Playground：

- `cd playground && bin/rails test`
- `cd playground && bin/rails zeitwerk:check`

Gem（TavernKit）：

- `bundle exec rake test`

通用：

- `ruby bin/lint-eof --fix`
