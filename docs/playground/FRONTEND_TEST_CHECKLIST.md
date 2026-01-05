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

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 5.2.1 | 代码块正确渲染（语法高亮） | 系统测试 | ✅ 可自动化 |
| 5.2.2 | 列表（有序/无序）正确渲染 | 系统测试 | ✅ 可自动化 |
| 5.2.3 | 换行正确处理 | 系统测试 | ✅ 可自动化 |
| 5.2.4 | Emoji 正常显示 | 系统测试 | ✅ 可自动化 |

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
| 8.3.1 | `reply_order = natural`：mention 某角色时更倾向选中该角色 | 系统测试 | ⚠️ 难以自动化 |
| 8.3.2 | `reply_order = list`：严格按列表顺序轮转 | 系统测试 | ✅ 可自动化 |
| 8.3.3 | `reply_order = pooled`：每个 epoch 内不重复 | 系统测试 | ✅ 可自动化 |
| 8.3.4 | `reply_order = manual`：发送 user message 不自动触发 AI | 系统测试 | ✅ 可自动化 |
| 8.3.5 | `reply_order = manual`：点 Gen/Force Talk 才触发 | 系统测试 | ✅ 可自动化 |

### 8.4 Auto Mode

| # | 测试项 | 类型 | 自动化状态 |
|---|--------|------|-----------|
| 8.4.1 | 开启 auto_mode：AI 在每次生成后继续排下一次 | 系统测试 | ✅ 可自动化 |
| 8.4.2 | 关闭 auto_mode 后：不再自动继续 | 系统测试 | ✅ 可自动化 |
| 8.4.3 | 用户开始输入时：禁用 auto_mode（可选，参照 ST） | 系统测试 | ⚠️ 待确认需求 |

---

## 9. 用户连续发多条消息与调度策略

> 这是系统的核心并发控制逻辑，需要重点测试。

### 9.1 ST-like 策略（during_generation = reject）

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

- [ ] Up：能编辑"最后一条消息"（或最后一条 user message，取决你定义）且不会干扰 textarea 输入
- [ ] Ctrl+Up：能编辑最后一条 user message
- [ ] Left/Right：只在 tail assistant 且有 swipes 时生效；textarea 有内容时不触发
- [ ] Ctrl+Enter：只 regenerate tail assistant（不要悄悄分支）
- [ ]（未实现项）Alt+Enter continue、Escape stop generation：确认不会误触/不会出现半成品入口

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

## 更新记录

- **2026-01-05**: 添加 15 分钟 Smoke 测试、全量回归测试清单（Section 14-16）
- **2026-01-05**: 初始版本，从测试清单整理
