# Phase 1 代码审计：发现与改进计划（Playground）

开始日期：2026-01-13  
对应计划：`docs/playground/PHASE1_CODE_AUDIT_PLAN.md`

## 执行记录（Evidence Log）

> 只记录“可复现”的东西：运行了什么命令、得到什么结论、关联到哪些文件/行。

- [x] `cd playground && bin/ci`（通过：rubocop / eslint / bundler-audit / brakeman / rails test / system test / seeds）
  - `eslint`：0 warnings（`no-console` 已清理）
  - `Bullet`：测试环境开启 `Bullet.raise = true`，CI 通过即代表未触发 N+1 / unused eager loading（否则会直接 fail 测试）
  - `bundler-audit`：No vulnerabilities found
  - `brakeman`：0 warnings
- [x] `cd playground && COVERAGE=1 bin/rails test`（SimpleCov 覆盖率基线）
  - 现已修复：`COVERAGE=1` 时自动关闭并行，避免 coverage 被“并行分片”破坏
  - 基线（单进程）：Line Coverage `67.58% (6386 / 9449)`（后续可用同一命令复现）

## 发现清单（Findings）

> 约定字段：
> - 严重度：Blocker / P0 / P1 / P2
> - 类型：错误处理 / 竞态 / 安全 / 性能 / 可维护性 / DX
> - 证据：文件路径 + 行号（必要时附最小复现步骤）
> - 处理：Fix now / Plan / Won't（必须说明原因）

### Blocker / P0（发布前必须修）

（暂无，待 CI 与人工审阅补充）

### P1（建议发布前修）

- **P1 / DX：SimpleCov 覆盖率在并行测试下不可信**
  - 证据：`COVERAGE=1 bin/rails test`（默认并行）输出 `Line Coverage: 1.06%`；`PARALLEL_WORKERS=0` 后为 `67.58%`
  - 影响：无法用 coverage 作为质量门槛，也会误导 Phase 1 checklist
  - 建议：
    - ✅ 已修复：`playground/test/test_helper.rb` 在 `ENV["COVERAGE"]` 下默认不启用并行（保证结果可信）
    - 可选增强：未来若需要并行 + coverage，可再加 SimpleCov collate

- **P1 / Security：Join 注册流程跳过鉴权导致“已登录用户识别失效”+ Cookie 配置不一致**
  - 证据：`playground/app/controllers/join_controller.rb`
    - `skip_before_action :require_authentication` 会导致 `Current.user` 不会被恢复，`redirect_if_logged_in` 实际不生效
    - 手工写 cookie：`cookies.signed.permanent[:session_token] = { value: session.token, httponly: true }`，与 `Authentication#authenticated_as` 的 `same_site/secure` 等选项不一致
  - 影响：
    - 已登录用户仍可访问 `/join/:code`（逻辑上应被拦截），可能造成账号/会话混乱
    - 生产环境下 session cookie 安全属性可能不一致（取决于 Rails 默认值）
  - 建议：
    - ✅ 已修复：改用 `require_unauthenticated_access` + `start_new_session_for`（统一 cookie 策略与已登录拦截）
    - 覆盖：新增 `playground/test/controllers/join_controller_test.rb`

- **P1 / Error Handling：`PresetsController#apply` 在 `turbo_stream` 分支返回 JSON**
  - 证据：`playground/app/controllers/presets_controller.rb` 中 `rescue ActiveRecord::RecordNotFound`：
    - `format.turbo_stream { render json: { error: \"Preset not found\" }, status: :not_found }`
  - 影响：Turbo Stream 请求收到 JSON，前端行为不可预期（可能静默失败/console error），也不符合其它 controller 的错误展示约定
  - ✅ 已修复：`turbo_stream` 分支改为渲染统一 toast turbo_stream

- **P1 / Error Handling：部分 `turbo_stream` 错误响应使用 `head`，导致 UI 静默失败**
  - 证据：
    - `playground/app/controllers/conversations_controller.rb`：`update/regenerate/generate/branch/toggle_auto_mode` 在错误分支返回 `head :unprocessable_entity`
    - `playground/app/controllers/conversations/checkpoints_controller.rb`：错误分支返回 `head :not_found` / `head :unprocessable_entity`
    - `playground/app/controllers/messages_controller.rb`：错误分支返回 `head :forbidden` / `head :locked`
    - `playground/app/controllers/settings/lorebooks/entries_controller.rb`：错误分支返回 `head :forbidden`
  - 影响：用户点击后无反馈（Turbo 请求失败但页面不更新），容易误以为按钮失效/卡住
  - ✅ 已修复：
    - 统一改为 `render_toast_turbo_stream(...)`（保留原 HTTP status）
    - `render_toast_turbo_stream` 增加 `X-TavernKit-Toast: 1` 响应头，前端 `message_form_controller` 在失败时检测该头以避免重复 toast

- **P1 / Reliability：toast turbo_stream partial 命名与格式不匹配（可能导致 500）**
  - 证据：`playground/app/views/shared/_toast_turbo_stream.html.erb` 在 `format.turbo_stream` 渲染时会被当成 `:turbo_stream` format 查找，触发 `ActionView::MissingTemplate`
  - ✅ 已修复：重命名为 `playground/app/views/shared/_toast_turbo_stream.turbo_stream.erb`（与使用方式一致）

### P2（可延后，但必须落盘）

- **P2 / UX：toast 系统存在“双容器 + 两套渲染路径”，导致样式不一致 & HTML toast（链接）不可用**
  - 证据：
    - Turbo Stream `show_toast` 写入 `#toast_container`（`playground/app/javascript/custom_turbo_actions.js`）
    - `toast:show` 事件写入 `#toast-container`（`playground/app/javascript/application.js`）
    - Checkpoint 的 turbo_stream 通过注入 `<script>` dispatch `toast:show`（链接会被转义）
  - 影响：同一页面可能出现两种 toast 样式；部分 toast（如 checkpoint link）不可点击
  - ✅ 已修复：
    - 统一只使用 `#toast_container` 容器
    - `toast:show` 事件改为克隆标准 toast 模板（带 `toast_controller` 动画/自动关闭）
    - `Conversations::CheckpointsController` 的 turbo_stream 改为 `show_toast`（链接用 Rails helper 生成）

- **P2 / DX：ESLint `no-console` warnings**
  - 证据：`cd playground && bun run lint`（历史）输出多处 `Unexpected console statement`
  - 影响：发布前噪音较大；真实 lint 问题容易被淹没
  - ✅ 已修复：引入 `app/javascript/logger.js`（debug/info 受 `localStorage.debug=1` 控制），并将所有 Stimulus controller 中的 `console.*` 收口到 `logger.*`；`bunx eslint app/javascript --max-warnings 0` 为 0 warnings

- **P2 / Consistency：部分注释/接口契约存在“历史遗留描述”**
  - 例：`playground/app/services/conversations/run_executor.rb` 中关于 `finalize_success!` “用于修复 loading indicator 的 broadcast_update”描述已与实现不一致
  - 影响：后续维护容易误判（尤其在并发/广播相关代码）
  - 建议：发布前顺手校正关键注释（不改行为）

## 集中重构候选（Refactor Candidates）

> 只放“能降低复杂度/竞态/重复”的重构；不做功能扩展。

- ✅ 已部分完成：提取统一 `toast_turbo_stream` / `render_toast_turbo_stream` helper（并统一到 `show_toast` / `#toast_container`）
- SimpleCov 并行覆盖率合并（或 COVERAGE 自动关闭并行），把 coverage 变成可用的质量门槛
- ✅ 已部分完成：统一“turbo_stream 错误响应约定”（把主要用户路径的 `head` 错误响应替换为 toast turbo_stream）

## ROADMAP 对齐（Phase 1：代码审计清单）

- [x] 移除所有 `# TODO` 和 `# FIXME` 注释或转为 issue（应用/测试代码中未发现；build artifacts 里可能有第三方文本）
- [x] 检查所有 Controller 的错误处理
- [x] 审查 N+1 查询（bullet gem）
- [x] 检查 ActionCable broadcast 竞态条件
- [x] 安全审计（权限检查、输入验证）
- [x] 前端 JS 代码 lint（ESLint）
- [x] CSS/Tailwind 清理未使用样式（Won't：当前 CSS 量小，且保留部分“未来可用”的样式/依赖）
- [x] 依赖安全审计（bundler-audit, brakeman）
- [x] 测试覆盖率检查
