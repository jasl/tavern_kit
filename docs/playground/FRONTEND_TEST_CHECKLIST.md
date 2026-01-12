# Playground 前端功能与交互测试清单

> 本文档整理了 Playground 前端的所有关键功能点和交互测试场景。
> 测试分为三类：**自动化测试**（System Test）、**半自动化测试**（需手动配置但可脚本化验证）、**手动测试**（需人工验证）。

---

## 测试前提条件

### 自动化测试基线

在进行任何功能测试前，确保基础测试通过：

```bash
# 单元测试和集成测试
cd playground && bin/rails test

# System tests（如果有）
cd playground && bin/rails test:system

# Linting
bin/rubocop && playground/bin/rubocop
```

**期望：** 全绿。如有失败或跳过的用例，记录并优先修复。

### 手动测试登录凭证

进行手动测试时使用以下凭证登录：

- **邮箱**: `admin@example.com`
- **密码**: `password123`

### 自动化状态图例

| 标记 | 含义 |
|------|------|
| ✅ 已覆盖 | 已有测试代码覆盖 |
| ✅ 可自动化 | 可以编写自动化测试，但**尚未实现** |
| ⚠️ 难以自动化 | 技术上难以自动化（如随机性、主观判断） |
| ❌ 需手动 | 必须人工验证（如多 Tab 同步、视觉效果） |

---

## 1. 环境与基础功能

### 1.1 首次启动与认证

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 1.1.1 | 首次启动（First Run）：能创建管理员并登录成功，跳转到 Playgrounds 列表 | 系统测试 | ✅ 可自动化 |
| 1.1.2 | 未登录访问 `/conversations/:id`：被重定向到登录页 | 集成测试 | ✅ 已覆盖 |
| 1.1.3 | 登录后访问 `/conversations/:id`（无权限）：返回 404/403 | 集成测试 | ✅ 已覆盖 |

### 1.2 多标签页/多浏览器同步

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 1.2.1 | 两个 Tab 打开同一 Conversation：新消息实时同步，无重复 | 手动测试 | ❌ 需手动 |
| 1.2.2 | 两个 Tab 打开同一 Conversation：swipe 切换同步更新 | 手动测试 | ❌ 需手动 |
| 1.2.3 | 两个 Tab 打开同一 Conversation：typing 指示同步显示/消失 | 手动测试 | ❌ 需手动 |
| 1.2.4 | 两个 Tab 打开同一 Conversation：分支跳转时两边都能正确导航 | 手动测试 | ❌ 需手动 |

---

## 2. Settings → LLM Providers

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 2.1 | 新建 Provider：表单校验正确（缺 API Key 或 Base URL 有明确提示） | 系统测试 | ✅ 可自动化 |
| 2.2 | Test Connection：成功时显示成功反馈 | 系统测试 | ✅ 可自动化 |
| 2.3 | Test Connection：失败时显示可理解的错误信息 | 系统测试 | ✅ 可自动化 |
| 2.4 | Fetch Models：成功获取模型列表 | 系统测试 | ✅ 可自动化 |
| 2.5 | 设置默认 Provider 后，新建 Playground 默认使用该 Provider | 系统测试 | ✅ 可自动化 |
| 2.6 | 删除被 Space 引用的 Provider：提示需先修改配置或禁止删除 | 系统测试 | ✅ 可自动化 |

---

## 3. Settings → Characters 角色管理

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 3.1 | 创建 Character：portrait、name、description、first_mes 正确显示 | 系统测试 | ✅ 可自动化 |
| 3.2 | 导入 Character（PNG/JSON/CHARX）：导入成功，字段正确 | 集成测试 | ✅ 已覆盖 |
| 3.3 | Character pending/ready 状态切换：UI 提示正确 | 系统测试 | ✅ 可自动化 |
| 3.4 | 修改 Character 后，Space 中的 group_context 变化符合预期 | 单元测试 | ✅ 已覆盖 |

---

## 4. Playgrounds 列表与管理

### 4.1 创建与编辑

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 4.1.1 | 新建 Playground：至少选择 1 个角色才能创建 | 系统测试 | ✅ 可自动化 |
| 4.1.2 | 新建 Playground：创建后自动进入 Main conversation | 系统测试 | ✅ 可自动化 |
| 4.1.3 | 新建多角色 Playground：Space.group? 正确，显示 Group Chat UI | 系统测试 | ✅ 可自动化 |
| 4.1.4 | 编辑 Playground：reply_order 保存后立即生效 | 系统测试 | ✅ 可自动化 |
| 4.1.5 | 编辑 Playground：card_handling_mode 保存后生效 | 系统测试 | ✅ 可自动化 |
| 4.1.6 | 编辑 Playground：debounce_ms 保存后生效 | 系统测试 | ✅ 可自动化 |
| 4.1.7 | 编辑 Playground：during_generation_policy 保存后生效 | 系统测试 | ✅ 可自动化 |

### 4.2 归档与删除

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 4.2.1 | Archive Playground：归档后输入区变只读，提示正确 | 系统测试 | ✅ 可自动化 |
| 4.2.2 | Unarchive Playground：解归档后恢复正常 | 系统测试 | ✅ 可自动化 |
| 4.2.3 | 删除 Playground：历史数据清理（Space、Conversation、Message、Run、Swipe、Membership） | 单元测试 | ✅ 已覆盖 |

---

## 5. Conversation 基本聊天（单角色）

### 5.1 消息发送与显示

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 5.1.1 | 发送 user message：立即 append 到消息列表 | 系统测试 | ✅ 可自动化 |
| 5.1.2 | 发送后：AI typing 指示出现 | 系统测试 | ✅ 可自动化 |
| 5.1.3 | Streaming 过程中：内容逐步显示 | 系统测试 | ✅ 可自动化 |
| 5.1.4 | 完成后：typing 消失，assistant message 正确显示最终结果 | 系统测试 | ✅ 可自动化 |
| 5.1.5 | 刷新页面：消息仍存在（持久化验证） | 系统测试 | ✅ 可自动化 |

### 5.2 Markdown 渲染

> Markdown 内容渲染在 `.mes-text` 容器内，使用 `prose-theme` 确保主题色正确。

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 5.2.1 | 代码块正确渲染（语法高亮） | 系统测试 | ✅ 可自动化 |
| 5.2.2 | 列表（有序/无序）正确渲染 | 系统测试 | ✅ 可自动化 |
| 5.2.3 | 换行正确处理 | 系统测试 | ✅ 可自动化 |
| 5.2.4 | Emoji 正常显示 | 系统测试 | ✅ 可自动化 |
| 5.2.5 | Roleplay `<em>` 标签使用 accent 颜色 | 系统测试 | ✅ 可自动化 |
| 5.2.6 | Roleplay `<q>` 标签使用 warning 颜色 | 系统测试 | ✅ 可自动化 |

### 5.3 滚动行为

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 5.3.1 | 新消息自动滚到底部 | 系统测试 | ✅ 可自动化 |
| 5.3.2 | 用户上滑查看历史时，不会被强制拉回底部 | 系统测试 | ✅ 可自动化 |
| 5.3.3 | 滚到顶部触发历史加载（Infinite Scroll） | 系统测试 | ✅ 可自动化 |
| 5.3.4 | 历史加载顺序正确，不会重复插入 | 系统测试 | ✅ 可自动化 |

---

## 6. Regenerate & Swipe（单角色）

> 参考 SillyTavern 的 Swipe/重新生成概念：生成多版本并允许切换。

### 6.1 基本 Regenerate

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 6.1.1 | 对最后一条 assistant 点 regenerate：不新增消息（原地更新） | 系统测试 | ✅ 可自动化 |
| 6.1.2 | Regenerate 后：swipe 计数 +1 | 系统测试 | ✅ 可自动化 |
| 6.1.3 | 连点 regenerate 多次：swipe position 和 count 正确 | 系统测试 | ✅ 可自动化 |
| 6.1.4 | 连点 regenerate：按钮 disabled 状态正确（防止重复触发） | 系统测试 | ✅ 可自动化 |

### 6.2 Swipe 切换

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 6.2.1 | 左右箭头切换能回到旧版本/新版本 | 系统测试 | ✅ 可自动化 |
| 6.2.2 | 切换后刷新页面，显示的是切换到的 active 版本 | 系统测试 | ✅ 可自动化 |
| 6.2.3 | 切到旧 swipe 后发送 user message：后续上下文基于当前 active swipe | 系统测试 | ✅ 可自动化 |
| 6.2.4 | 快捷键 Left/Right 能切换（且输入框有内容时不误触） | 系统测试 | ✅ 可自动化 |

### 6.3 生成中 Regenerate

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 6.3.1 | 生成中点 regenerate：running run 被 cancel | 系统测试 | ✅ 可自动化 |
| 6.3.2 | Cancel 后：typing UI 正确 reset（不会残留半截内容） | 系统测试 | ✅ 可自动化 |

### 6.4 错误处理

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 6.4.1 | 模型报错时：错误消息显示到 chat（errored? 分支） | 系统测试 | ✅ 可自动化 |
| 6.4.2 | 错误后：typing 被清理 | 系统测试 | ✅ 可自动化 |

---

## 7. Branch（分支对话树）

> 参考 SillyTavern 的 Checkpoint/Create Branch：克隆到某条消息继续写。

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 7.1 | 在历史某条消息点 "Branch from here"：新会话创建 | 系统测试 | ✅ 可自动化 |
| 7.2 | 新分支只包含截至该消息的历史（含 swipes/active swipe） | 集成测试 | ✅ 已覆盖 |
| 7.3 | Header 显示 "Branched from message #seq" | 系统测试 | ✅ 可自动化 |
| 7.4 | 新分支里继续聊天：不影响父会话的后续消息 | 系统测试 | ✅ 可自动化 |
| 7.5 | 在分支里 regenerate/swipe：只影响分支 | 系统测试 | ✅ 可自动化 |
| 7.6 | 分支的 parent/root 字段关系正确 | 单元测试 | ✅ 已覆盖 |

---

## 8. Group Chat（多 AI 角色）

> 参考 SillyTavern Group Chat：Mute、Force Talk、Auto-mode 等。

### 8.1 基本功能

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 8.1.1 | 成员列表按 position 顺序显示 | 系统测试 | ✅ 可自动化 |
| 8.1.2 | Force Talk 下拉菜单正确显示所有 AI 成员 | 系统测试 | ✅ 可自动化 |

### 8.2 Mute 功能

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 8.2.1 | Mute 某角色后：该角色不再被 reply_order 选中 | 系统测试 | ✅ 可自动化 |
| 8.2.2 | Force Talk 仍能强制让 muted 角色说话 | 系统测试 | ✅ 可自动化 |

### 8.3 Reply Order 策略

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 8.3.1 | `reply_order = natural`（ST/Risu 对齐）：mention 优先 + talkativeness 抽样激活，**一次 user message 可能触发多个 AI 依次回复** | 系统测试 | ⚠️ 难以自动化 |
| 8.3.2 | `reply_order = list`（ST 对齐）：**一次 user message 触发所有可参与 AI**，按 position 顺序依次回复 | 系统测试 | ✅ 可自动化 |
| 8.3.3 | `reply_order = pooled`（ST 对齐）：一次 user message **只触发 1 个 AI**（随机），且 epoch 内不重复 | 系统测试 | ✅ 可自动化 |
| 8.3.4 | `reply_order = manual`：发送 user message 不自动触发 AI（需要 Gen/Force Talk 或 Auto-mode） | 系统测试 | ✅ 可自动化 |
| 8.3.5 | `reply_order = manual`：点 Gen/Force Talk 才触发；Auto-mode 会随机挑 1 个 AI 继续（ST-like） | 系统测试 | ✅ 可自动化 |

### 8.4 Auto Mode

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 8.4.1 | 开启 auto_mode：AI 在每次生成后继续排下一次 | 系统测试 | ✅ 可自动化 |
| 8.4.2 | 关闭 auto_mode 后：不再自动继续 | 系统测试 | ✅ 可自动化 |
| 8.4.3 | 用户开始输入时：禁用 auto_mode（ST-aligned behavior） | 系统测试 | ✅ 可自动化 |
| 8.4.4 | auto_mode rounds 用尽/停止后：回到“Your turn”，Group queue bar 不会卡在上一个 speaker（快响应场景尤需关注） | 手动测试 | ❌ 需手动 |

---

## 9. 用户连续发多条消息与调度策略

> 这是系统的核心并发控制逻辑，需要重点测试。

### 9.1 ST-like 策略（during_generation = reject）

> 说明：该策略已作为 **Space 默认值**（对齐 SillyTavern / RisuAI 的“生成中禁止发送，需先 Stop/Abort”行为）。

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 9.1.1 | AI 生成中再次 send：被拒绝（423/locked） | 系统测试 | ✅ 可自动化 |
| 9.1.2 | 被拒绝时：用户有明确反馈（toast/禁用输入/提示文案） | 系统测试 | ✅ 可自动化 |
| 9.1.3 | AI 完成后 send：正常触发下一次生成 | 系统测试 | ✅ 可自动化 |

### 9.2 合并用户输入策略（during_generation = queue + debounce）

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 9.2.1 | debounce 时间内连续发 2 条 user message：最终只触发 1 次 AI 回复 | 单元测试 | ✅ 已覆盖 |
| 9.2.2 | AI 回复内容涵盖两条 user message 的上下文 | 系统测试 | ⚠️ 难以自动化 |
| 9.2.3 | 连发间隔超过 debounce：会触发两次（预期行为） | 单元测试 | ✅ 已覆盖 |

### 9.3 ChatGPT-like 策略（during_generation = restart）

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 9.3.1 | AI 生成中 send 第二条：第一条 generation 被 cancel | 单元测试 | ✅ 已覆盖 |
| 9.3.2 | 最终只生成一次（基于最新上下文） | 单元测试 | ✅ 已覆盖 |
| 9.3.3 | 旧回复不会"插队覆盖"新问题 | 单元测试 | ✅ 已覆盖 |

---

## 10. 并发与边界情况

### 10.1 单槽约束（queued/running）

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 10.1.1 | 两个 Tab 几乎同时发送 user message：只会有 1 个 running run | 单元测试 | ✅ 已覆盖 |
| 10.1.2 | queued 只保留最新触发（debounce 覆盖） | 单元测试 | ✅ 已覆盖 |
| 10.1.3 | DB 使用 partial unique index 确保约束 | 单元测试 | ✅ 已覆盖 |

### 10.2 Stale Running 自愈（Reaper）

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 10.2.1 | Running 卡死后：Reaper 在超时后将 run 标为 failed/canceled | 单元测试 | ✅ 已覆盖 |
| 10.2.2 | 卡死解除后：queued 能继续执行 | 单元测试 | ✅ 已覆盖 |

### 10.3 Cancel 边界

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 10.3.1 | 生成中触发 cancel：placeholder/ephemeral UI 停住 | 系统测试 | ✅ 可自动化 |
| 10.3.2 | Cancel 后：不会留下永远 generating 的 message | 系统测试 | ✅ 可自动化 |
| 10.3.3 | Cancel 后：后续 queued run 可以继续跑 | 单元测试 | ✅ 已覆盖 |

---

## 11. Membership 移除与历史一致性

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 11.1 | 移除 AI Character 成员：历史消息仍存在可回放 | 系统测试 | ✅ 可自动化 |
| 11.2 | 移除后：display_name、portrait 不崩 | 系统测试 | ✅ 可自动化 |
| 11.3 | 移除后：Prompt 构建时不再把它当作可发言成员 | 单元测试 | ✅ 已覆盖 |
| 11.4 | 多真人场景：踢出用户后，该用户无法再访问 Space/Conversations | 系统测试 | ✅ 可自动化 |
| 11.5 | 多真人场景：其他成员仍能看到被踢用户的历史消息 | 系统测试 | ✅ 可自动化 |

---

## 12. 安全与授权

### 12.1 URL/ID 越权

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 12.1.1 | 用户 A 的 message_id，用户 B 尝试 swipe/regenerate：返回 404/403 | 集成测试 | ✅ 已覆盖 |
| 12.1.2 | 用户 A 的 conversation，用户 B 尝试访问：返回 404/403 | 集成测试 | ✅ 已覆盖 |

### 12.2 Channel 订阅越权

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 12.2.1 | 手动订阅别人的 membership_id：后端拒绝 subscribe | 单元测试 | ✅ 已覆盖 |
| 12.2.2 | 手动订阅别人的 conversation_id：后端拒绝 subscribe | 单元测试 | ✅ 已覆盖 |

### 12.3 广播 Scope

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 12.3.1 | 多人房间：A 的 copilot candidate 不会被 B 收到 | 单元测试 | ✅ 已覆盖 |
| 12.3.2 | 多人房间：A 的 copilot disabled 不会被 B 收到 | 单元测试 | ✅ 已覆盖 |

---

## 13. Turbo Streams 使用一致性

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 13.1 | regenerate/swipe 使用 Turbo Streams 的 replace/update | 代码审查 | ✅ 人工审查 |
| 13.2 | 不使用 append 导致顺序/重复问题 | 代码审查 | ✅ 人工审查 |
| 13.3 | 延迟调度使用 ActiveJob `set(wait_until:)` / `set(wait:)` | 代码审查 | ✅ 人工审查 |
| 13.4 | 同一 target 多次 `turbo_stream.replace`：不会出现旧 UI 覆盖新 UI（需要 DB revision + `turbo:before-stream-render` 兜底） | 代码审查 | ✅ 人工审查 |

---

## 14. 15 分钟 Smoke 测试（每次大改后必做）

> 快速验证核心链路：能正常聊、能生成、流式/广播没炸、regenerate/swipe 可用、不会乱序。

### 14.1 基础导航与数据准备

- [ ] 能登录/进入首页（`/`），能看到 Playground 列表（`/playgrounds`）
- [ ] Settings 里至少有 1 个 LLM Provider（`/settings/llm_providers`）并测试成功（不要求真发请求，但至少能保存）
- [ ] Settings 里至少有 2 个 Character（`/settings/characters`）

### 14.2 创建 2 个 Playground：Solo 与 Group

- [ ] 创建 Solo Playground（只选 1 个 Character）→ 自动创建 Root Conversation → 进入聊天页正常渲染
- [ ] 创建 Group Playground（选 2 个 Character）→ 进入聊天页，Members 列表出现 2 个 AI

### 14.3 聊天核心链路（Solo）

- [ ] 发送 1 条 user message → 触发 AI 回复 → typing indicator 正常出现/消失 → 最终 assistant message 出现在列表末尾
- [ ] 点击 assistant message 的 Regenerate → **原地生成 swipe**（message 不新增一条）→ swipe 导航显示 `1/2`
- [ ] 点击 swipe Left/Right → 内容切换正确，边界不会越界（左到头/右到头不会再变化）
- [ ] 复制按钮（copy）能复制到剪贴板（至少不报错）
- [ ] eye 按钮切换"excluded_from_prompt"能即时反映（UI/tooltip/样式变化），并且刷新页面仍保持

### 14.4 分支/Checkpoint（Solo）

- [ ] 对一条"非尾部 user message"点击 Branch（git-branch）→ 跳转到新 conversation → breadcrumb/branches panel 能看到树结构
- [ ] 在 branch conversation 继续聊天，root conversation 不会被污染（回到 root 看历史没变）
- [ ] 点击某条 message 的 Checkpoint → 出现 toast（含跳转链接）→ 点链接进入 checkpoint conversation

### 14.5 Debug / Prompt Preview

- [ ] 右侧 Runs 面板能看到最近 runs，点开 run detail modal 不报错，能看到 trigger/usage（如果有）/prompt snapshot（如果打开了）
- [ ] 点击 Preview（Prompt Preview Modal）能正常打开并展示内容（至少有 messages 列表/JSON），关闭正常

---

## 15. 全量回归测试清单

> 建议本地逐条执行，确保所有功能正常工作。

### 15.1 Playgrounds 列表页 `/playgrounds`

- [ ] 新建 playground：名称为空时能自动生成（如 "Playground #123"）
- [ ] 编辑 playground：Reply order / Card handling / Allow self responses / Auto mode / Debounce 等保存后刷新仍一致
- [ ] Policy Presets：
  - [ ] 切到 "SillyTavern Classic" → UI 上对应字段值发生变化（reject + 0ms 等）
  - [ ] 切到 "Smart Turn Merge" → queue + debounce(800ms)
  - [ ] 切到 "ChatGPT-like" → restart + 0ms
- [ ] 删除 playground：状态变 deleting 后行为符合预期（你现在没做真正删除也 OK，但别 500）

### 15.2 Playground 详情页 `/playgrounds/:id`

- [ ] Add AI Character：能添加、能 mute/unmute、能 remove（remove 后历史不崩，刷新后不显示）
- [ ] Conversations 列表：New conversation 能创建、能进入聊天页

### 15.3 SpaceMembership 编辑页 `/playgrounds/:id/space_memberships/:id/edit`

- [ ] 基础字段保存（display_name、position、participation、persona 等）
- [ ] LLM provider 选择后：
  - [ ] schema settings 表单渲染不报错
  - [ ] settings_form 自动保存状态正确（Unsaved → Saving → Saved）
  - [ ] 模拟 409（两标签页同时改）时：会自动刷新/重试，不会把 UI 卡死
- [ ] Copilot：
  - [ ] copilot mode 切到 suggest：回到聊天页有候选建议卡片
  - [ ] 切到 full：聊天页 toggle 正常，step 限制生效（用完后会自动禁用并提示）

### 15.4 Conversation 聊天页 `/conversations/:id`

#### 渲染与滚动

- [ ] 左右 sidebar 开关（按钮 + `[` / `]`）正确，localStorage 记忆正确
- [ ] 消息多于 50 条时，向上滚动触发加载更多：不跳屏、不重复、不乱序
- [ ] Turbo streams 到来时（AI 回复/编辑/删除/切 swipes）：不会出现 duplicate message（你做了 dedup，这里要确认）
- [ ] Turbo streams 同一 target 的 replace（例如 group queue bar）：快响应下不会乱序覆盖；Auto-mode 用尽/停止后能回到“Your turn”

#### 消息动作与权限

- [ ] 编辑 tail user message：inline editor 打开/保存/取消都正常
- [ ] 编辑非 tail user message：Edit 按钮应隐藏/禁用（或引导分支）
- [ ] 删除 tail message：删除成功，若存在 queued run，会被 cancel（不会再回复）
- [ ] 删除非 tail message：应被禁止（422/提示），且 UI 不出现误导按钮

#### Group chat 专项

- [ ] reply_order = natural：多轮对话中 speaker 轮换符合预期（特别是 allow_self_responses=false 时不会连续同一人）
- [ ] reply_order = list：严格按 position 顺序说话
- [ ] reply_order = pooled：随机但只在可参与者中
- [ ] group_regenerate_mode = last_turn：点击 Regenerate 会清掉"最后一轮的所有 assistant 消息"再重新生成（顺序正确）

#### Prompt Preview

- [ ] card_handling_mode = swap/append/append_disabled 切换后，用 preview 能观察到 prompt messages 变化（至少"参与者/非参与者"策略正确）

### 15.5 Hotkeys

> SillyTavern-style chat hotkeys implementation. Reference: `chat_hotkeys_controller.js`
>
> **重要约束**: 编辑快捷键只在 tail 消息属于当前用户时生效（服务端只允许编辑 tail 消息）

- [ ] `Up`：textarea 为空且 focus 时，仅当 tail 是当前用户发送的消息时才触发编辑
- [ ] `Up`：当 tail 是 AI 回复时，按 Up 不触发任何操作（不会导致页面刷新或消息内容丢失）
- [ ] `Ctrl+Up`：textarea 为空且 focus 时，仅当 tail 是当前用户的 role=user 消息时才触发编辑
- [ ] `Left/Right`：tail assistant 消息有 swipes 时切换版本；textarea 有内容时不触发
- [ ] `Ctrl+Enter`：当 tail 是 assistant 时 regenerate（在原位生成新 swipe）
- [ ] `Escape`：优先关闭打开的 inline edit；无编辑时 stop 正在进行的 generation
- [ ] 所有快捷键在 IME 输入法组合时不触发（`event.isComposing` 保护）
- [ ] 快捷键不干扰其他 input/textarea 的正常输入（除了绑定的 message textarea）

---

## 16. 简化 Smoke 测试（10 分钟快速版）

> 最小化验证"能正常聊、能生成、流式/广播没炸、regenerate/swipe 可用、不会乱序"。

### 基本聊天链路

- [ ] `bin/dev` 启动
- [ ] 创建房间/对话
- [ ] 发送一条 user 消息
- [ ] 观察 assistant 回复产生（只出现一次，无重复）
- [ ] 刷新页面后消息仍在

### 三策略快速测试

- [ ] `queue` 策略：第二条消息被排队，当前生成不被污染
- [ ] `restart` 策略：当前生成被取消，最终只回答最新上下文
- [ ] `reject` 策略：返回 423/locked 并提示用户

### Auto Mode

- [ ] 开启 auto_mode，触发生成，观察是否按 delay 继续下一轮
- [ ] delay 期间插入 user 消息，自动连发被抑制

### Regenerate

- [ ] 对最后一条 assistant 点 regenerate
- [ ] 确认同一条 message 位置不变（不 append 到末尾）
- [ ] 生成完成后可继续正常聊天

### Swipes

- [ ] 连续 regenerate 2-3 次（产生多个 swipe）
- [ ] 左右箭头切换版本
- [ ] 切到旧版本后刷新，显示正确版本

---

## 附录：自动化测试实现指南

### System Test 技术栈

```ruby
# playground/test/application_system_test_case.rb
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]
end
```

### Mock LLM 服务

项目已有 Mock LLM 控制器用于测试：

```
playground/test/controllers/mock_llm/v1/
├── chat_completions_controller_test.rb
└── models_controller_test.rb
```

### 关键测试助手

```ruby
# TurboTestHelper - Turbo Streams 断言
assert_turbo_stream_broadcasts(stream_name, count: 1, &block)
assert_no_turbo_stream_broadcasts(stream_name, &block)
assert_turbo_stream(action:, target:)
```

### 推荐的 System Test 文件结构

```
playground/test/system/
├── authentication_test.rb      # 1.1 认证相关
├── llm_providers_test.rb       # 2.x Provider 管理
├── characters_test.rb          # 3.x 角色管理
├── playgrounds_test.rb         # 4.x Playground 管理
├── conversation_chat_test.rb   # 5.x 基本聊天
├── regenerate_swipe_test.rb    # 6.x Regenerate & Swipe
├── branching_test.rb           # 7.x 分支
├── group_chat_test.rb          # 8.x Group Chat
└── membership_test.rb          # 11.x Membership
```

---

## 17. 时序/竞态专项测试

> 这些测试需要手动操作多个标签页或使用 Rails console 模拟特定状态。

### 17.1 Multi-tab + Regenerate Skipped

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 17.1.1 | Tab A 打开会话，确保最后一条是 assistant | 手动测试 | ❌ 需手动 |
| 17.1.2 | Tab A 点 regenerate（触发 queued regenerate run，含 expected_last_message_id） | 手动测试 | ❌ 需手动 |
| 17.1.3 | Tab B 立刻发送一条 user message（让 tail 变化） | 手动测试 | ❌ 需手动 |
| 17.1.4 | 预期：regenerate run 进入 `skipped(expected_last_message_mismatch)` | 手动测试 | ❌ 需手动 |
| 17.1.5 | 预期：两个 tab 都收到 `run_skipped` toast（warning） | 手动测试 | ❌ 需手动 |
| 17.1.6 | 预期：不应产生新 swipe / 不应插入新消息 | 手动测试 | ❌ 需手动 |

### 17.2 Multi-tab + Queue + Debounce（合并用户连续发言）

**设置前提：**
- `during_generation_user_input_policy = queue`
- `user_turn_debounce_ms = 800`（或适当值）

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 17.2.1 | 在 500ms 内连续发送两条 user message | 手动测试 | ❌ 需手动 |
| 17.2.2 | 预期：只产生 **一次** AI 回复（一次 run） | 手动测试 | ❌ 需手动 |
| 17.2.3 | 预期：回复内容能看到两条用户消息上下文 | 手动测试 | ⚠️ 难以自动化 |

### 17.3 Restart 策略：生成中追加用户消息会 Cancel

**设置前提：** `during_generation_user_input_policy = restart`

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 17.3.1 | 发送一条 user message，让 AI 开始生成（typing 出现） | 手动测试 | ❌ 需手动 |
| 17.3.2 | 在生成中发送第二条 user message | 手动测试 | ❌ 需手动 |
| 17.3.3 | 预期：前一个 run 被 cancel（toast：Stopped/Cancelled） | 手动测试 | ❌ 需手动 |
| 17.3.4 | 预期：新 run 以最新上下文重新生成 | 手动测试 | ❌ 需手动 |
| 17.3.5 | 预期：不会出现两条 assistant 同时生成 | 手动测试 | ❌ 需手动 |

### 17.4 Fork Point 保护（必测）

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 17.4.1 | 从某条 message M branch 出子会话 | 手动测试 | ❌ 需手动 |
| 17.4.2 | 回到 parent，尝试删除 M | 手动测试 | ❌ 需手动 |
| 17.4.3 | 预期：**不会 500**，返回 422 | 手动测试 | ❌ 需手动 |
| 17.4.4 | 预期：toast 提示"该消息已被分支引用，无法修改" | 手动测试 | ❌ 需手动 |
| 17.4.5 | Group last_turn regenerate 会删到 M 时：自动创建 branch 并在新 branch 执行 regenerate | 手动测试 | ❌ 需手动 |

### 17.5 Stale Run 的 UI 收敛

> 需用 Rails console 或直接改 DB 模拟 stale 状态。

**模拟方法：**

```ruby
# 找到一个 running 状态的 run
run = ConversationRun.running.last
# 人为设置 heartbeat_at 为 3 分钟前，使其变成 stale
run.update_column(:heartbeat_at, 3.minutes.ago)
```

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 17.5.1 | 让某个 run 处于 running，heartbeat_at 人为改成 3 分钟前 | 手动测试 | ❌ 需手动 |
| 17.5.2 | 再触发一个 queued run（或等待 ReaperJob） | 手动测试 | ❌ 需手动 |
| 17.5.3 | 预期：stale run 被标 failed | 手动测试 | ❌ 需手动 |
| 17.5.4 | 预期：UI typing 立即被 `stream_complete` 清理（不需等 60s） | 手动测试 | ❌ 需手动 |
| 17.5.5 | 预期：toast 提示"Generation timed out. Please try again." | 手动测试 | ❌ 需手动 |

### 17.6 Multi-tab Non-tail Edit/Delete 提示

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 17.6.1 | Tab A 打开会话，鼠标悬浮在最后一条 user message 上（编辑/删除按钮可见） | 手动测试 | ❌ 需手动 |
| 17.6.2 | Tab B 发送一条新的 user message（原 Tab A 的 tail 不再是 tail） | 手动测试 | ❌ 需手动 |
| 17.6.3 | Tab A 点击编辑/删除按钮 | 手动测试 | ❌ 需手动 |
| 17.6.4 | 预期：Tab A 显示 warning toast "Cannot edit/delete non-last message. Use Branch to modify history." | 手动测试 | ❌ 需手动 |
| 17.6.5 | 预期：无需刷新即可理解发生了什么 | 手动测试 | ❌ 需手动 |

---

## 18. Conversation Lorebooks（Chat Lore）

> SillyTavern 的 "Chat Lore" 功能：为单个对话附加专属 Lorebook。

### 18.1 基本功能

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 18.1.1 | 左侧栏 Lorebooks 面板能看到 "Conversation Lorebooks" 区域 | 系统测试 | ✅ 可自动化 |
| 18.1.2 | 从下拉菜单选择 Lorebook 并点击 Attach：成功附加到对话 | 系统测试 | ✅ 可自动化 |
| 18.1.3 | 附加后列表显示 Lorebook 名称和条目数量 | 系统测试 | ✅ 可自动化 |
| 18.1.4 | 点击 Detach 按钮：确认弹窗后移除 Lorebook | 系统测试 | ✅ 可自动化 |

### 18.2 启用/禁用切换

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 18.2.1 | 点击 eye 图标：切换 Lorebook 启用/禁用状态 | 系统测试 | ✅ 可自动化 |
| 18.2.2 | 禁用状态时图标变灰（eye-off） | 系统测试 | ✅ 可自动化 |
| 18.2.3 | 禁用的 Lorebook 不参与 prompt 构建 | 单元测试 | ✅ 已覆盖 |

### 18.3 优先级排序

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 18.3.1 | 拖拽 handle 能重新排序 Lorebook | 系统测试 | ✅ 可自动化 |
| 18.3.2 | 排序后刷新页面：顺序保持 | 系统测试 | ✅ 可自动化 |
| 18.3.3 | 排序顺序影响 prompt 中 lore entries 的优先级 | 单元测试 | ✅ 已覆盖 |

### 18.4 边界情况

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 18.4.1 | 无 Lorebook 时显示 "Create First Lorebook" 链接 | 系统测试 | ✅ 可自动化 |
| 18.4.2 | 所有 Lorebook 都已附加时显示提示 | 系统测试 | ✅ 可自动化 |
| 18.4.3 | 同一个 Lorebook 不能重复附加 | 系统测试 | ✅ 可自动化 |

---

## 19. SillyTavern 消息布局

> 消息使用全宽布局（`.mes` 类），替代了 DaisyUI chat 组件。

### 19.1 消息结构

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 19.1.1 | 消息显示头像（`.mes-avatar-wrapper`） | 系统测试 | ✅ 可自动化 |
| 19.1.2 | 消息头部显示发送者名称（`.mes-name`） | 系统测试 | ✅ 可自动化 |
| 19.1.3 | 消息头部显示时间戳（`.mes-timestamp`） | 系统测试 | ✅ 可自动化 |
| 19.1.4 | 消息头部显示 role badge（user/assistant/system） | 系统测试 | ✅ 可自动化 |
| 19.1.5 | 消息正文在 `.mes-text` 容器内渲染 | 系统测试 | ✅ 可自动化 |

### 19.2 消息操作

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 19.2.1 | 操作按钮组（`.mes-actions`）默认隐藏 | 系统测试 | ✅ 可自动化 |
| 19.2.2 | 悬浮消息时操作按钮组显示 | 系统测试 | ✅ 可自动化 |
| 19.2.3 | Swipe 导航（`.mes-swipe-nav`）在有多个 swipe 时显示 | 系统测试 | ✅ 可自动化 |
| 19.2.4 | Swipe 计数器（`.mes-swipe-counter`）显示正确位置 | 系统测试 | ✅ 可自动化 |

### 19.3 状态样式

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 19.3.1 | 被排除的消息（`.mes.excluded`）显示半透明 | 系统测试 | ✅ 可自动化 |
| 19.3.2 | 被排除的消息显示 "Excluded" badge | 系统测试 | ✅ 可自动化 |
| 19.3.3 | 错误状态消息（`.mes.errored`）显示错误样式 | 系统测试 | ✅ 可自动化 |
| 19.3.4 | 错误消息显示错误图标和错误信息 | 系统测试 | ✅ 可自动化 |

### 19.4 生成状态

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 19.4.1 | `generating` 状态消息显示 loading dots | 系统测试 | ✅ 可自动化 |
| 19.4.2 | `succeeded` 状态消息正常显示内容 | 系统测试 | ✅ 可自动化 |
| 19.4.3 | `failed` 状态消息显示错误信息 | 系统测试 | ✅ 可自动化 |

### 19.5 Typing Indicator

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 19.5.1 | Typing indicator 使用 `.mes` 布局 | 系统测试 | ✅ 可自动化 |
| 19.5.2 | Typing indicator 显示发言者头像和名称 | 系统测试 | ✅ 可自动化 |
| 19.5.3 | Typing indicator 显示 "typing" badge | 系统测试 | ✅ 可自动化 |
| 19.5.4 | 流式内容实时更新到 typing indicator | 系统测试 | ✅ 可自动化 |
| 19.5.5 | 生成完成后 typing indicator 消失 | 系统测试 | ✅ 可自动化 |

---

## 20. Error Handling and Retry

> 生成失败时的错误处理和重试机制。

### 20.1 错误状态显示

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 20.1.1 | LLM API 错误时显示 toast 通知（`run_failed` 事件） | 系统测试 | ✅ 可自动化 |
| 20.1.2 | 失败的消息显示错误样式（`.mes.errored`） | 系统测试 | ✅ 可自动化 |
| 20.1.3 | 失败的消息显示错误图标和错误信息 | 系统测试 | ✅ 可自动化 |
| 20.1.4 | 超时的 run 被 ReaperJob 清理后显示超时 toast | 系统测试 | ✅ 可自动化 |

### 20.2 重试机制

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 20.2.1 | 失败的消息显示 Retry 按钮 | 系统测试 | ✅ 可自动化 |
| 20.2.2 | 点击 Retry 按钮触发 regenerate 请求 | 系统测试 | ✅ 可自动化 |
| 20.2.3 | Retry 成功后消息内容更新，错误状态清除 | 系统测试 | ✅ 可自动化 |
| 20.2.4 | Retry 失败后仍显示错误状态和 Retry 按钮 | 系统测试 | ✅ 可自动化 |

### 20.3 Stop Generation

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 20.3.1 | `Escape` 键可以停止正在进行的 generation | 系统测试 | ✅ 可自动化 |
| 20.3.2 | Stop 后 typing indicator 立即消失 | 系统测试 | ✅ 可自动化 |
| 20.3.3 | Stop 后显示 "Stopped" toast 通知 | 系统测试 | ✅ 可自动化 |
| 20.3.4 | Stop 后可以正常发送新消息或 regenerate | 系统测试 | ✅ 可自动化 |
| 20.3.5 | 无 inline edit 打开时 `Escape` 才触发 stop | 系统测试 | ✅ 可自动化 |
| 20.3.6 | 有 inline edit 打开时 `Escape` 优先关闭编辑 | 系统测试 | ✅ 可自动化 |

---

## 21. Conversation Export

> 导出对话为 JSONL（可重新导入）或 TXT（人类可读）格式。
>
> **实现文件:**
> - `app/controllers/conversations_controller.rb` - `export` action
> - `app/services/conversations/exporter.rb` - JSONL/TXT 格式化逻辑
> - `app/views/conversations/_left_sidebar.html.erb` - UI 导出按钮

### 21.1 基本导出功能

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 21.1.1 | 左侧栏 Stats 面板显示 "Export Conversation" 区域 | 系统测试 | ✅ 可自动化 |
| 21.1.2 | 点击 JSONL 按钮触发下载 | 系统测试 | ✅ 可自动化 |
| 21.1.3 | 点击 TXT 按钮触发下载 | 系统测试 | ✅ 可自动化 |
| 21.1.4 | 下载的文件名包含对话标题和时间戳 | 系统测试 | ✅ 可自动化 |

### 21.2 JSONL 格式内容

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 21.2.1 | 第一行是 metadata header（包含 conversation info 和 space settings） | 单元测试 | ✅ 已覆盖 |
| 21.2.2 | 每条消息占一行 JSON | 单元测试 | ✅ 已覆盖 |
| 21.2.3 | 消息包含所有 swipes | 单元测试 | ✅ 已覆盖 |
| 21.2.4 | 消息包含 role、content、excluded_from_prompt 等字段 | 单元测试 | ✅ 已覆盖 |
| 21.2.5 | 消息包含 speaker 信息（display_name, kind, character_id, user_id） | 单元测试 | ✅ 已覆盖 |

### 21.3 TXT 格式内容

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 21.3.1 | 文件头部包含对话标题和时间信息 | 单元测试 | ✅ 已覆盖 |
| 21.3.2 | 每条消息显示时间戳、发送者名称、角色 | 单元测试 | ✅ 已覆盖 |
| 21.3.3 | 被排除的消息显示 [EXCLUDED] 标记 | 单元测试 | ✅ 已覆盖 |
| 21.3.4 | 有多个 swipe 的消息显示 swipe 信息 | 单元测试 | ✅ 已覆盖 |

---

## 22. Hotkeys Help Modal

> 显示可用键盘快捷键的帮助模态框。
>
> **实现文件:**
> - `app/javascript/controllers/chat_hotkeys_controller.js` - `?` 键触发
> - `app/views/shared/_js_templates.html.erb` - 模态框模板
> - `app/views/messages/_form.html.erb` - 帮助按钮

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 22.1 | 消息输入区域显示帮助按钮（keyboard + help-circle 图标） | 系统测试 | ✅ 可自动化 |
| 22.2 | 点击帮助按钮打开 hotkeys 模态框 | 系统测试 | ✅ 可自动化 |
| 22.3 | 模态框显示所有 Chat 快捷键（Up, Ctrl+Up, Left/Right, Ctrl+Enter, Escape） | 系统测试 | ✅ 可自动化 |
| 22.4 | 模态框显示 Navigation 快捷键（[, ]） | 系统测试 | ✅ 可自动化 |
| 22.5 | 模态框显示注意事项（swipe 条件、tail-only 规则） | 系统测试 | ✅ 可自动化 |
| 22.6 | 点击关闭按钮或背景关闭模态框 | 系统测试 | ✅ 可自动化 |

---

## 23. Mobile Touch Swipe Gestures

> 触摸滑动手势用于在移动设备上切换 swipe 版本。
>
> **实现文件:**
> - `app/javascript/controllers/touch_swipe_controller.js` - 触摸事件处理
> - `app/views/messages/_message.html.erb` - 绑定 touch-swipe controller

### 23.1 手势检测

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 23.1.1 | 向左滑动触发 swipe left | 手动测试 | ❌ 需手动 |
| 23.1.2 | 向右滑动触发 swipe right | 手动测试 | ❌ 需手动 |
| 23.1.3 | 垂直滑动不触发 swipe（正常滚动） | 手动测试 | ❌ 需手动 |
| 23.1.4 | 斜向滑动以水平分量为主时触发 swipe | 手动测试 | ❌ 需手动 |

### 23.2 条件限制

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 23.2.1 | 只在 assistant 消息上触发 | 手动测试 | ❌ 需手动 |
| 23.2.2 | 只在有多个 swipe 的消息上触发 | 手动测试 | ❌ 需手动 |
| 23.2.3 | 滑动距离小于阈值不触发（50px） | 手动测试 | ❌ 需手动 |
| 23.2.4 | 滑动时间超过阈值不触发（500ms） | 手动测试 | ❌ 需手动 |

---

## 24. Auto-mode Round Limits (群聊自动对话)

> Conversation 级别的 AI-to-AI 对话功能，带轮数限制以防止费用失控。
> 与 SillyTavern 的全局无限制行为不同（详见 `docs/spec/SILLYTAVERN_DIVERGENCES.md`）。
>
> **实现文件:**
> - `app/models/conversation.rb` - `auto_mode_remaining_rounds`, 调度状态字段
> - `app/controllers/conversations_controller.rb` - `toggle_auto_mode` action
> - `app/views/messages/_group_queue.html.erb` - Auto mode 切换按钮
> - `app/javascript/controllers/auto_mode_toggle_controller.js` - 前端交互
> - `app/services/turn_scheduler.rb` - 统一调度器入口
> - `app/services/turn_scheduler/commands/` - 调度命令（StartRound, AdvanceTurn 等）

### 24.1 基本功能

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 24.1.1 | 群聊工具栏显示 Auto mode 切换按钮 | 系统测试 | ✅ 可自动化 |
| 24.1.2 | 点击 Play 按钮启动 auto-mode（默认 4 轮） | 系统测试 | ✅ 可自动化 |
| 24.1.3 | 启动后立即触发第一个 AI 响应（不需要用户先发消息） | 系统测试 | ✅ 可自动化 |
| 24.1.4 | 按钮显示剩余轮数 | 系统测试 | ✅ 可自动化 |
| 24.1.5 | 点击 Pause 按钮停止 auto-mode | 系统测试 | ✅ 可自动化 |
| 24.1.6 | 轮数耗尽时自动禁用（按钮状态更新） | 系统测试 | ✅ 可自动化 |
| 24.1.7 | 启动/停止时显示 Toast 通知 | 系统测试 | ✅ 可自动化 |

### 24.2 轮数递减

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 24.2.1 | 每次 AI 响应后 remaining_rounds 递减 | 单元测试 | ✅ 已覆盖 |
| 24.2.2 | 轮数达到 0 时设置为 nil（禁用） | 单元测试 | ✅ 已覆盖 |
| 24.2.3 | WebSocket 广播轮数变化 | 集成测试 | ✅ 可自动化 |
| 24.2.4 | UI 实时更新轮数显示 | 系统测试 | ✅ 可自动化 |

### 24.3 限制条件

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 24.3.1 | 单聊（非群聊）不显示 Auto mode 按钮 | 系统测试 | ✅ 可自动化 |
| 24.3.2 | manual reply_order 模式下 auto-mode 不触发 followup | 单元测试 | ✅ 已覆盖 |
| 24.3.3 | 轮数限制在 1-10 范围内 | 单元测试 | ✅ 已覆盖 |
| 24.3.4 | 超出范围的轮数被 clamp 到有效范围 | 单元测试 | ✅ 已覆盖 |

### 24.4 并发安全

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 24.4.1 | 原子递减（使用 SQL UPDATE WHERE > 0） | 单元测试 | ✅ 已覆盖 |
| 24.4.2 | 多个并发请求不会导致 remaining_rounds 负数 | 集成测试 | ✅ 可自动化 |

---

## 25. User Input Priority (用户输入优先级)

> 用户输入时自动禁用 Copilot/Auto mode，提交时取消所有排队的 AI 生成，
> 确保用户消息永远优先，防止竞态条件导致的重复消息。
>
> **实现文件:**
> - `app/javascript/controllers/message_form_controller.js` - `handleInput` 方法分发事件
> - `app/javascript/controllers/copilot_controller.js` - 监听 `user:typing:disable-copilot`
> - `app/javascript/controllers/auto_mode_toggle_controller.js` - 监听 `user:typing:disable-auto-mode`
> - `app/services/messages/creator.rb` - 提交时取消排队的 runs
> - `app/models/conversation.rb` - `cancel_all_queued_runs!` 方法

### 25.1 输入时禁用模式（软锁定行为）

> **设计原则**: Copilot/Auto mode 是"软锁定"，用户可以输入来自动禁用它们。
> 只有 Reject Policy + AI Generating 是"硬锁定"（用户必须等待）。
> 参见: `docs/spec/SILLYTAVERN_DIVERGENCES.md` "Input locking behavior"

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 25.1.1 | 用户在输入框输入时，Copilot mode 自动禁用 | 系统测试 | ✅ 可自动化 |
| 25.1.2 | 用户在输入框输入时，Auto mode 自动禁用 | 系统测试 | ✅ 可自动化 |
| 25.1.3 | 禁用时显示 Toast 通知 "... - you are typing" | 系统测试 | ✅ 可自动化 |
| 25.1.4 | 空输入不触发禁用（只有实际内容才触发） | 系统测试 | ✅ 可自动化 |
| 25.1.5 | Copilot 开启时：textarea 和 Send 按钮保持可用（软锁定） | 系统测试 | ✅ 可自动化 |
| 25.1.6 | Copilot 开启时：Vibe 按钮禁用 | 系统测试 | ✅ 可自动化 |
| 25.1.7 | Copilot 开启时：placeholder 显示 "Copilot is active. Type here to take over..." | 系统测试 | ✅ 可自动化 |
| 25.1.8 | Reject + AI Generating：textarea 和 Send 按钮禁用（硬锁定） | 系统测试 | ✅ 可自动化 |
| 25.1.9 | Reject + AI Generating：placeholder 显示 "Waiting for AI response..." | 系统测试 | ✅ 可自动化 |

### 25.2 提交时取消排队

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 25.2.1 | 用户发送消息时，所有 queued runs 被 canceled | 单元测试 | ✅ 可自动化 |
| 25.2.2 | 取消的 run 记录 `canceled_by: user_message_submitted` | 单元测试 | ✅ 可自动化 |
| 25.2.3 | 用户消息成功创建后，正常规划 AI 响应 | 集成测试 | ✅ 可自动化 |
| 25.2.4 | running 状态的 run 不被取消（只取消 queued） | 单元测试 | ✅ 可自动化 |

### 25.3 竞态条件防护

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 25.3.1 | Auto mode 运行中用户发言，不会出现两条消息 | 集成测试 | ✅ 可自动化 |
| 25.3.2 | Copilot mode 运行中用户发言，不会出现两条消息 | 集成测试 | ✅ 可自动化 |
| 25.3.3 | 用户消息始终是对话中的权威"下一条消息" | 集成测试 | ✅ 可自动化 |

---

## 26. Unified Turn Scheduler (统一调度器)

> TurnScheduler 是所有回合调度的单一入口。
> 使用消息驱动推进：每个 Message `after_create_commit` 触发 `AdvanceTurn` 命令。
> 所有可自动回复的参与者（AI 角色、Copilot full 人类）在同一个队列中；普通人类不入队（只作为触发源）。
>
> **实现文件:**
> - `app/services/turn_scheduler.rb` - 统一调度器入口
> - `app/services/turn_scheduler/commands/` - 命令对象（StartRound, AdvanceTurn, ScheduleSpeaker 等）
> - `app/services/turn_scheduler/queries/` - 查询对象（NextSpeaker, QueuePreview）
> - `app/services/turn_scheduler/state/` - 状态值对象（RoundState）
> - `app/models/message.rb` - `after_create_commit :notify_scheduler_turn_complete`
> - `app/models/space_membership.rb` - 环境变化通知回调
> - `app/models/conversation_round.rb` - round runtime state 实体
> - `app/models/conversation_round_participant.rb` - round 队列条目（有序）

### 26.1 Turn Queue

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 26.1.1 | `TurnScheduler.state.round_queue_ids` 由 `conversation_round_participants` 持久化本轮激活队列（对齐 ST/Risu 语义，避免随机策略中途重算） | 单元测试 | ✅ 可自动化 |
| 26.1.2 | `reply_order=list`：`round_queue_ids` 包含所有可参与 AI，按 membership position 顺序 | 单元测试 | ✅ 可自动化 |
| 26.1.3 | `reply_order=pooled`：一次 user message 只激活 1 个 AI（`round_queue_ids.size == 1`） | 单元测试 | ✅ 可自动化 |
| 26.1.4 | `reply_order=natural`：mention 优先 + talkativeness 抽样激活（可能多人），并写入 `round_queue_ids` | 单元测试 | ✅ 可自动化 |
| 26.1.5 | round active 时 Queue UI 使用持久化队列（不再仅依赖预测 preview），刷新页面后仍一致 | 系统测试 | ✅ 可自动化 |

### 26.2 Message-Driven Turn Advancement

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 26.2.1 | 消息创建后 after_create_commit 调用 advance_turn! | 单元测试 | ✅ 可自动化 |
| 26.2.2 | system 消息不触发 advance_turn! | 单元测试 | ✅ 可自动化 |
| 26.2.3 | advance_turn! 标记发言者为已发言 | 单元测试 | ✅ 可自动化 |
| 26.2.4 | advance_turn! 递增 turns_count | 单元测试 | ✅ 可自动化 |
| 26.2.5 | advance_turn! 递减 speaker 资源（copilot steps/auto rounds） | 单元测试 | ✅ 可自动化 |
| 26.2.6 | 无活跃回合时，用户消息自动开始新回合 | 集成测试 | ✅ 可自动化 |

### 26.3 Human Skip in Auto Mode

> ❌ 已移除：TurnScheduler 不再调度纯人类（不创建 `human_turn` / timeout 机制）

### 26.4 Environment Changes

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 26.4.1 | 新成员加入/启用 Copilot 时广播 queue_updated（UI 预览更新） | 集成测试 | ✅ 可自动化 |
| 26.4.2 | 成员被 mute/removed 导致不可调度时：若为 current speaker 自动 Skip（避免卡住） | 集成测试 | ✅ 可自动化 |
| 26.4.3 | Copilot 模式切换时广播 queue_updated（UI 预览更新） | 集成测试 | ✅ 可自动化 |
| 26.4.4 | mid-round 不重算队列：不可调度成员在推进时被 skipped（保留 spoken/skipped 记录） | 单元测试 | ✅ 可自动化 |

### 26.5 Auto Mode 与 Copilot Mode 互斥

> Auto Mode 和 Copilot Mode 是互斥的。启用其中一个会自动禁用另一个。
> 这是为了防止调度冲突和费用失控。

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 26.5.1 | 启用 Auto mode 时自动禁用所有 Copilot mode | 集成测试 | ✅ 可自动化 |
| 26.5.2 | 启用 Copilot 时自动禁用 Auto mode | 集成测试 | ✅ 可自动化 |
| 26.5.3 | 先启用 Auto mode 再启用 Copilot：Auto mode 被禁用，Copilot 激活 | 系统测试 | ✅ 可自动化 |
| 26.5.4 | 先启用 Copilot 再启用 Auto mode：Copilot 被禁用，Auto mode 激活 | 系统测试 | ✅ 可自动化 |
| 26.5.5 | 禁用 Auto mode 后，Copilot 按钮 UI 正确更新为非激活状态 | 系统测试 | ✅ 可自动化 |
| 26.5.6 | 禁用 Copilot 后，Auto mode 按钮 UI 正确更新为非激活状态 | 系统测试 | ✅ 可自动化 |
| 26.5.7 | Copilot 步数耗尽后，Copilot 按钮 UI 变为非激活，textarea 解锁 | 系统测试 | ✅ 可自动化 |
| 26.5.8 | Auto mode 轮数耗尽后，Auto mode 按钮 UI 变为非激活 | 系统测试 | ✅ 可自动化 |
| 26.5.9 | 快速多次点击 Auto mode 按钮不会导致竞态条件（防抖保护） | 系统测试 | ✅ 可自动化 |
| 26.5.10 | 快速多次点击 Copilot 按钮不会导致竞态条件（防抖保护） | 系统测试 | ✅ 可自动化 |
| 26.5.11 | 先开 Copilot 后快速多次点击 Auto mode：两者不会同时激活 | 系统测试 | ✅ 可自动化 |

### 26.6 Copilot 在调度中的行为

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 26.6.1 | Copilot user 被视为 auto-respondable 加入调度 | 集成测试 | ✅ 可自动化 |
| 26.6.2 | Copilot 步数耗尽后不再被调度 | 集成测试 | ✅ 可自动化 |
| 26.6.3 | 启用 Copilot full（persona）后：该用户 membership 变为可调度，下一轮会创建 `copilot_response` run | 集成测试 | ✅ 可自动化 |
| 26.6.4 | 新加入的 Copilot 成员延迟到下一轮加入队列 | 集成测试 | ✅ 可自动化 |

### 26.7 Round Management

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 26.7.1 | start_round! 创建新的 round_id | 单元测试 | ✅ 可自动化 |
| 26.7.2 | 回合完成后检查 auto_scheduling_enabled? 决定是否开始新回合 | 单元测试 | ✅ 可自动化 |
| 26.7.3 | clear! 清空队列状态 | 单元测试 | ✅ 可自动化 |
| 26.7.4 | 用户发送消息时 clear! 被调用（重置调度） | 集成测试 | ✅ 可自动化 |
| 26.7.5 | Auto mode 轮数耗尽后调度器停止新回合 | 集成测试 | ✅ 可自动化 |

### 26.8 Run Skip Handling

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 26.8.1 | Run 被 skip (expected_last_message_mismatch) 时通知调度器继续 | 集成测试 | ✅ 可自动化 |
| 26.8.2 | Run 被 skip (missing_speaker) 时通知调度器继续 | 集成测试 | ✅ 可自动化 |
| 26.8.3 | Regenerate run 被 skip 时不触发调度器通知 | 单元测试 | ✅ 可自动化 |
| 26.8.4 | Skip 后 schedule_current_turn! 正确调度下一个发言者 | 集成测试 | ✅ 可自动化 |

---

## 27. ConversationRun kind and Reliability（kind enum + 可靠性）

> ConversationRun 使用 `kind` enum（不使用 STI）区分类型，
> 并提供卡住检测（health + reaper）和手动恢复 API。
>
> **实现文件:**
> - `app/models/conversation_run.rb` - `kind/status` enum + stale 检测 + 状态转换
> - `app/jobs/conversation_run_job.rb` - 执行 queued run
> - `app/jobs/conversation_run_reaper_job.rb` - 10 分钟安全网（running run stale）
> - `app/services/conversations/health_checker.rb` - 前端轮询健康检查（stuck/failed/idle_unexpected）
> - `app/controllers/conversations_controller.rb` - `cancel_stuck_run` / `retry_stuck_run` / `health`

### 27.1 Kind Types

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 27.1.1 | `auto_response` run 正确创建并执行 | 单元测试 | ✅ 可自动化 |
| 27.1.2 | `copilot_response` run 正确创建并执行 | 单元测试 | ✅ 可自动化 |
| 27.1.3 | Regenerate run 正确添加 swipe | 单元测试 | ✅ 可自动化 |
| 27.1.4 | ForceTalk run 忽略回合顺序直接发言 | 单元测试 | ✅ 可自动化 |

### 27.2 Stale Runs Cleanup

> **注意**: `StaleRunsCleanupJob` 已移除（太激进），改为使用用户可控的 UI 警告和 10 分钟的 Reaper 安全网。

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 27.3.2 | ConversationRunReaperJob 在 10 分钟后执行 | 单元测试 | ✅ 可自动化 |
| 27.3.3 | Reaper 只处理 heartbeat 超时的 running run | 单元测试 | ✅ 可自动化 |
| 27.3.4 | heartbeat! 方法正确更新 heartbeat_at | 单元测试 | ✅ 可自动化 |

### 27.4 Manual Recovery

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 27.4.1 | cancel_stuck_run API 取消活跃的 run | 系统测试 | ✅ 可自动化 |
| 27.4.2 | 取消后重置调度状态 | 单元测试 | ✅ 可自动化 |
| 27.4.3 | 取消后显示 Toast 提示 | 系统测试 | ✅ 可自动化 |
| 27.4.4 | 无活跃 run 时返回提示消息 | 系统测试 | ✅ 可自动化 |
| 27.4.5 | can_cancel? 方法正确判断可取消状态 | 单元测试 | ✅ 可自动化 |

### 27.5 Stuck Run Warning UI

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 27.5.1 | 打字指示器显示超过 30s 后显示警告 | 系统测试 | ✅ 可自动化 |
| 27.5.2 | 收到 stream_chunk 后隐藏警告 | 系统测试 | ✅ 可自动化 |
| 27.5.3 | 警告包含 Retry 和 Cancel 两个按钮 | 系统测试 | ✅ 可自动化 |
| 27.5.4 | 点击 Retry 按钮调用 retry_stuck_run API | 系统测试 | ✅ 可自动化 |
| 27.5.5 | 点击 Cancel 按钮显示确认对话框 | 系统测试 | ✅ 可自动化 |
| 27.5.6 | 确认后调用 cancel_stuck_run API | 系统测试 | ✅ 可自动化 |
| 27.5.7 | 取消成功后隐藏打字指示器和警告 | 系统测试 | ✅ 可自动化 |

### 27.6 Debug Panel Updates

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 27.6.1 | Run 列表显示 type badge（AutoTurn、CopilotTurn 等） | 系统测试 | ✅ 可自动化 |
| 27.6.2 | Filter toggle 控制 HumanTurn 可见性 | 系统测试 | ✅ 可自动化 |
| 27.6.3 | 活跃 run 显示 Cancel 按钮 | 系统测试 | ✅ 可自动化 |
| 27.6.4 | run_detail_data 包含 type 和 type_label | 单元测试 | ✅ 可自动化 |

### 27.7 Error Alert UI (失败后不自动推进)

> Run 失败后（LLM 错误、异常、超时等），不会自动推进到下一个 turn。
> 而是在输入框上方显示错误提示，用户必须点击 Retry 才能继续。

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 27.7.1 | Run 失败后显示 Error Alert（红色警告条） | 系统测试 | ✅ 可自动化 |
| 27.7.2 | Error Alert 只有 Retry 按钮（无 Cancel） | 系统测试 | ✅ 可自动化 |
| 27.7.3 | 失败后不自动调度下一个 turn | 集成测试 | ✅ 可自动化 |
| 27.7.4 | 点击 Retry 调用 retry_stuck_run API | 系统测试 | ✅ 可自动化 |
| 27.7.5 | Retry 成功后显示 typing indicator | 系统测试 | ✅ 可自动化 |
| 27.7.6 | Retry 成功后隐藏 Error Alert | 系统测试 | ✅ 可自动化 |
| 27.7.7 | 新消息出现后自动隐藏 Error Alert | 系统测试 | ✅ 可自动化 |
| 27.7.8 | 不同错误码显示不同提示消息 | 单元测试 | ✅ 可自动化 |

**错误码测试用例:**

```ruby
# 测试不同错误类型的提示消息
error_codes = {
  "stale_timeout" => "AI response timed out",
  "no_provider_configured" => "No LLM provider configured",
  "connection_error" => "Failed to connect to LLM",
  "http_error" => "LLM provider error",
  "unknown" => "AI response failed"
}
```

### 27.8 Serial Execution Guarantee (串行执行保证)

> 确保同一 Conversation 内同时只有一个 ConversationRunJob 执行。

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 27.8.1 | RunPlanner.kick! 检查是否有 running run | 单元测试 | ✅ 可自动化 |
| 27.8.2 | 已有 running run 时不调度新 job | 单元测试 | ✅ 可自动化 |
| 27.8.3 | RunFollowups 在 run 完成后 force kick 等待的 run | 集成测试 | ✅ 可自动化 |
| 27.8.4 | force: true 参数绕过 running 检查 | 单元测试 | ✅ 可自动化 |

---

## 更新记录

- **2026-01-11**: 添加 Auto Mode 与 Copilot Mode 互斥测试（Section 26.5），重组 Copilot 调度行为测试（Section 26.6）
- **2026-01-11**: 添加 Error Alert UI 和失败后不自动推进测试（Section 27.7）
- **2026-01-11**: 添加串行执行保证测试（Section 27.8）
- **2026-01-11**: 更新 Stuck Warning UI 测试（添加 Retry 按钮和确认对话框）（Section 27.5）
- **2026-01-11**: 移除 StaleRunsCleanupJob，更新为 10 分钟 Reaper 安全网（Section 27.3）
- **2026-01-11**: 添加 ConversationRun STI 重构和可靠性测试（Section 27）
- **2026-01-11**: 修复 Copilot 在 Auto Mode 中启用时的冲突处理，添加 Run Skip 通知调度器（Section 26.6, 26.8）
- **2026-01-11**: 重构 Unified Conversation Scheduler 为消息驱动设计（Section 26）
- **2026-01-10**: 添加 User Input Priority 测试（Section 25）
- **2026-01-10**: 重构 Auto-mode 为 Conversation 级别带轮数限制（Section 24），替换原 "Disable Auto-mode on Typing" 测试
- **2026-01-10**: 添加 Conversation Export 测试（Section 21）、Hotkeys Help Modal 测试（Section 22）、Mobile Touch Swipe 测试（Section 23）
- **2026-01-10**: 添加 Error Handling and Retry 测试（Section 20）、更新 Hotkeys 测试（Section 15.5）
- **2026-01-10**: 添加 Conversation Lorebooks 测试（Section 18）、SillyTavern 消息布局测试（Section 19）
- **2026-01-10**: 更新 Markdown 渲染测试添加 roleplay 样式检查（Section 5.2）
- **2026-01-05**: 添加时序/竞态专项测试（Section 17）
- **2026-01-05**: 添加 15 分钟 Smoke 测试、全量回归测试清单（Section 14-16）
- **2026-01-05**: 初始版本，从测试清单整理
