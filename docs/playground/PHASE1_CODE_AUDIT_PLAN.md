# Phase 1 发布前代码审计计划书（Playground）

执行日期：2026-01-13  
目标版本：Playground `v0.1.0`（Public Beta 前的 Phase 1 收尾）

## 目标

在不“凭感觉改代码”的前提下，用**可复现证据**（命令输出/文件定位/测试用例）完成一次发布前审计与集中整改，确保：

- 发布质量：错误可控、权限可靠、实时通信稳定、核心路径可回归
- 无遗留问题：高风险问题必须清零，中风险问题给出明确改进计划
- 可持续性：风格一致、设计一致、模块职责正交，减少“代码幻觉/漂移”

## 范围（Scope）

### 重点（Phase 1 Checklist 对齐）

- Controller 错误处理一致性与健壮性
- ActionCable/Turbo Streams 广播竞态与幂等性
- 安全审计：权限检查、输入验证、会话/CSRF、ActionCable 鉴权
- 测试覆盖率：生成基线、识别盲区、补关键回归

### 扩展（发布前质量门槛）

- 依赖安全：`bundler-audit`、`brakeman`
- 代码风格：`rubocop`、`eslint`
- N+1 查询与明显性能陷阱（Bullet/预加载策略）
- 高耦合/重复逻辑的集中重构（只做高价值、低风险）

### 不做（Non-goals）

- 新功能开发（除非属于修复的必要前置）
- 大规模 API 兼容层（该仓库 pre-1.0，允许破坏性改动，但仍以“发布稳定”为先）

## 审计方法（Evidence-driven）

为避免“读太多代码产生幻觉”，本审计以 **“先索引→再验证→再落盘→再改代码”** 的流程执行。

### 0）建立索引（已完成）

- 仓库规模：`774` tracked files；约 `127,362` 行（Ruby 约 `81,623` 行）
- Playground 控制面：`36` 个 Controller；`4` 个 Channel（含 ApplicationCable）
- Broadcast 热点：`Message#broadcast_*`、`Turbo::StreamsChannel.broadcast_*`、`ConversationChannel.broadcast_*`
- TODO/FIXME：代码中未发现（仅文档中存在 checklist/说明）

### 1）自动化基线（CI Gate）

以 `playground/bin/ci` 为“单一真相”，跑完整套：

- Ruby style：`playground/bin/rubocop`
- JS style：`cd playground && bun run lint`
- 安全：`playground/bin/bundler-audit`、`playground/bin/brakeman --exit-on-warn`
- 测试：`cd playground && bin/rails test`、`bin/rails test:system`、`db:seed:replant`

结果已通过 CI gate 并落盘到代码；可参考 `docs/playground/ROADMAP.md` 的 Phase 1「代码审计清单」以及 git log。

### 2）主题审阅（人工 + 工具）

#### A. Controller 错误处理（必做）

检查点：

- `respond_to` 覆盖：`turbo_stream/html/json` 的状态码与反馈一致性
- `ActiveRecord::RecordNotFound` / 授权失败的处理：是否符合“不泄露资源存在性”的策略
- 服务层返回错误的映射：错误码→HTTP status→UI 反馈（toast/alert）
- `rescue_from` 规则：是否集中、是否会误吞异常

输出：列出不一致点/潜在 500、给出统一的约定（pattern）与修复方案。

#### B. ActionCable 广播竞态（必做）

以项目既定原则为准（见 `AGENT.md` 与 `docs/playground/PLAYGROUND_ARCHITECTURE.md`）：

- JSON 事件（typing/stream chunk）走 `ConversationChannel`
- DOM 变更（append/replace/remove）走 Turbo Streams
- **禁止 placeholder message + broadcast_update 跟 broadcast_create 竞态**

检查点：

- 所有 `broadcast_update` / `broadcast_remove` 的调用点是否可能早于 create/append
- Job/Service 中是否存在跨事务广播（commit 前广播导致 UI 读到旧数据）
- “重复事件”是否幂等（多 tab、多用户、断线重连）

#### C. 安全审计（必做）

检查点：

- 鉴权：Controller scopes（`accessible_to`）、`Authorization` concern、管理员路径（Settings）
- 输入：`strong_parameters`、`params.fetch/require` 默认值、危险字段（`api_key` 等）的处理
- Session/Cookie：`httponly/samesite/secure`、会话固定、防止越权切换
- ActionCable：Connection 鉴权、Channel 订阅授权、广播数据不泄露敏感信息
- XSS/HTML 注入：Turbo/partials 输出、富文本/markdown（如有）
- SSRF/开放重定向：外部 URL、`redirect_back` 使用位置

#### D. 测试覆盖率（必做）

基线生成：

- `cd playground && COVERAGE=1 bin/rails test`
- 输出 SimpleCov 报告（不提交到 git）

关注：

- Controllers/Services/Jobs/Channels 的关键路径覆盖
- 回归测试优先：权限、调度、消息创建/删除/分支、广播触发点

### 3）落盘与整改策略

- 所有发现已在整改期落盘并合入代码；后续新增问题建议记录到 `docs/playground/BACKLOGS.md`（或 issue）
- 按严重度分层：
  - **P0/Blocker**：发布前必须修复并加回归测试
  - **P1**：优先修复；若需延期必须写清楚风险与后续里程碑
  - **P2**：可记录为 phase 2/issue，但要标注触发条件与建议方案
- 集中重构原则：只做“减少复杂度/减少竞态/减少重复”的重构；避免功能漂移

## 交付物（Deliverables）

- `docs/playground/PHASE1_CODE_AUDIT_PLAN.md`（本文档）
- `docs/playground/ROADMAP.md`：Phase 1「代码审计清单」更新勾选状态与链接
- `docs/playground/BACKLOGS.md`：后续发现的改进项（如有）
