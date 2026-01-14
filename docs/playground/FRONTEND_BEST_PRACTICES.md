# Playground 前端开发最佳实践

本文档整理了 Playground 前端开发的约定和最佳实践，旨在提高代码可维护性和一致性。

---

## 1. HTML 模板模式

### 问题

在 JavaScript 中直接拼接 HTML 字符串会导致以下问题：

- **可维护性差**：HTML 与 JS 逻辑混杂
- **无 I18n 支持**：嵌入的文本无法使用 Rails 的 `t()` 辅助方法
- **重复代码**：多个控制器各自实现 `escapeHtml()` 方法
- **样式不一致**：例如 toast 位置在不同控制器中可能不同

### 解决方案

使用 HTML `<template>` 元素，将模板定义在视图层，JavaScript 只负责克隆和填充数据。

#### 模板文件位置

```
playground/app/views/shared/_js_templates.html.erb
```

此文件在 `layouts/base.html.erb` 中被渲染，确保所有页面都能访问这些模板。

#### 模板结构示例

```erb
<%# Toast 通知模板 %>
<template id="toast_template">
  <div class="alert shadow-lg">
    <span data-toast-message></span>
  </div>
</template>

<%# 标签芯片模板 %>
<template id="tag_chip_template">
  <span class="badge badge-sm badge-primary gap-1" data-tags-input-target="tag">
    <span data-tag-text></span>
    <button type="button" class="hover:text-error" data-action="tags-input#remove">&times;</button>
  </span>
</template>
```

#### JavaScript 使用方式

```javascript
// 获取模板
const template = document.getElementById("toast_template")
if (!template) {
  console.warn("[toast] Template not found")
  return
}

// 克隆模板
const toast = template.content.cloneNode(true).firstElementChild

// 使用 textContent 填充数据（自动转义，防止 XSS）
toast.querySelector("[data-toast-message]").textContent = message

// 添加到容器
container.appendChild(toast)
```

> 备注：toast 容器 `#toast_container` 预渲染在 `playground/app/views/layouts/base.html.erb`。

### 何时使用模板模式

| 场景 | 推荐方案 |
|------|----------|
| 重复创建的简单 UI 元素（toast、标签、列表项） | ✅ 使用 `<template>` |
| 复杂的动态表单 | ⚠️ 考虑 Turbo Frames 或服务端渲染 |
| Markdown 渲染等内容处理 | ❌ 保持现有 JS 实现 |
| 服务端已返回 HTML 的场景 | ❌ 直接使用返回的 HTML |

### 例外情况

以下场景保持现有实现：

- `markdown_controller.js`：Markdown 到 HTML 的转换是合法的 JS 操作
- `run_detail_modal_controller.js`：已改为纯 DOM 渲染（不拼 HTML 字符串）；如未来内容继续膨胀可再考虑 Turbo Frame 懒加载
- `llm_settings_controller.js`：连接状态使用 `alert_box_template` + `renderAlertBox()`（不拼 HTML 字符串）；如未来状态继续变复杂再考虑 Turbo Streams
- `prompt_preview_controller.js`：服务端返回预渲染的 HTML（错误渲染使用 `alert_box_template`）

---

## 2. Toast 通知标准化

### 全局事件模式

所有 toast 通知都应通过全局 `toast:show` 事件触发，而不是各控制器自行创建 DOM 元素。

```javascript
// ✅ 正确方式
showToast(message, type = "info") {
  window.dispatchEvent(new CustomEvent("toast:show", {
    detail: { message, type, duration: 3000 },
    bubbles: true,
    cancelable: true
  }))
}

// ❌ 错误方式：直接创建 DOM
showToast(message, type = "info") {
  const toast = document.createElement("div")
  toast.className = "alert ..."
  // ...
}
```

### 事件参数

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `message` | string | 必填 | 显示的消息文本 |
| `type` | string | `"info"` | 类型：`info`、`success`、`warning`、`error` |
| `duration` | number | `5000` | 自动消失时间（毫秒） |

### 事件处理器

全局事件处理器位于 `playground/app/javascript/application.js`，负责：

1. 获取 `toast_template` 模板
2. 克隆并填充数据
3. 添加到 `toast_container`
4. 处理自动消失动画

---

## 3. XSS 防护

### 使用 textContent 而非 innerHTML

当动态插入用户提供的内容时，优先使用 `textContent`：

```javascript
// ✅ 安全：自动转义
element.querySelector("[data-message]").textContent = userInput

// ❌ 危险：可能导致 XSS
element.innerHTML = `<span>${userInput}</span>`
```

### escapeHtml 方法

如果必须使用 `innerHTML`（如需要嵌入格式化标签），使用 `escapeHtml` 辅助方法：

```javascript
escapeHtml(text) {
  const div = document.createElement("div")
  div.textContent = text
  return div.innerHTML
}

// 使用
element.innerHTML = `<strong>${this.escapeHtml(userInput)}</strong>`
```

**注意**：采用模板模式后，大多数场景不再需要 `escapeHtml`，因为 `textContent` 已自动处理转义。

---

## 4. Stimulus 控制器约定

### 目标命名

使用清晰的语义化命名：

```javascript
static targets = [
  "content",      // 主内容区域
  "textarea",     // 文本输入
  "submitBtn",    // 提交按钮
  "branchCta",    // 分支 CTA 按钮
  "branchBtn"     // 实际的分支表单按钮
]
```

### 值（Values）声明

```javascript
static values = {
  messageId: Number,
  editing: { type: Boolean, default: false },
  url: String
}
```

### 事件处理

对于需要跨控制器通信的场景，使用自定义事件：

```javascript
// 触发
this.dispatch("updated", { detail: { id: this.idValue } })

// 或全局事件
window.dispatchEvent(new CustomEvent("toast:show", { detail: { message: "Done" } }))
```

---

## 5. CSS 类约定

### SillyTavern 消息布局

消息使用 SillyTavern 风格的全宽布局（定义在 `application.tailwind.css`）：

```html
<!-- 消息容器 -->
<div class="mes">
  <div class="mes-avatar-wrapper">
    <img class="avatar" src="..." alt="..." />
  </div>
  <div class="mes-block">
    <div class="mes-header">
      <span class="mes-name">角色名</span>
      <time class="mes-timestamp">时间戳</time>
    </div>
    <div class="mes-text">
      <!-- Markdown 渲染内容 -->
    </div>
    <div class="mes-footer">
      <div class="mes-swipe-nav">...</div>
      <div class="mes-actions">...</div>
    </div>
  </div>
</div>
```

| 类名 | 用途 |
|------|------|
| `.mes` | 消息容器（flex row） |
| `.mes-avatar-wrapper` | 头像容器 |
| `.mes-block` | 内容块（flex-1） |
| `.mes-header` | 头部：名称、徽章、时间戳 |
| `.mes-name` | 发送者名称 |
| `.mes-timestamp` | 时间戳 |
| `.mes-text` | 消息正文（Markdown 渲染） |
| `.mes-footer` | 底部：swipe 导航、操作按钮 |
| `.mes-swipe-nav` | Swipe 切换导航 |
| `.mes-swipe-counter` | Swipe 位置计数器 |
| `.mes-actions` | 操作按钮组（hover 显示） |

**状态类：**

| 类名 | 效果 |
|------|------|
| `.mes.excluded` | 半透明，表示从 prompt 排除 |
| `.mes.errored` | 错误样式 |

**Roleplay 排版（自动应用于 `.mes-text` 内）：**

| HTML 元素 | 样式 | 用途 |
|-----------|------|------|
| `<em>` / `<i>` | accent 颜色、斜体 | 动作/内心描写 |
| `<q>` | warning 颜色 | 对话引用 |
| `<u>` | secondary 颜色、下划线 | 强调文本 |

### daisyUI 组件

其他 UI 组件优先使用 daisyUI 组件类：

```html
<!-- Toast -->
<div class="toast toast-end toast-top z-50">
  <div class="alert alert-success shadow-lg">
    <span>消息内容</span>
  </div>
</div>

<!-- 按钮 -->
<button class="btn btn-ghost btn-xs btn-square">
  <span class="icon-[lucide--edit] size-3"></span>
</button>
```

### 图标

使用 Iconify 图标集：

```html
<span class="icon-[lucide--git-branch] size-3"></span>
<span class="icon-[lucide--check] size-4"></span>
```

### Typography 主题

Markdown 内容使用 `.prose-theme` 类确保颜色跟随 DaisyUI 主题：

```html
<div class="prose prose-sm prose-theme max-w-none">
  <!-- Markdown 渲染内容 -->
</div>
```

---

## 6. 前后端状态收敛（Turbo Stream 作为真相）

### 核心原则

- **HTTP Turbo Stream = 真相（Source of Truth）**：所有“会改变 UI 状态”的操作，都应在响应里返回 Turbo Streams 来更新 UI（包括错误场景），避免只靠 ActionCable。
- **ActionCable = best-effort 加速层**：用于流式预览、typing indicator、跨用户同步等；断线时允许降级，但不应导致 UI 永久漂移。

### 服务端约定（Rails）

- 对 `format.turbo_stream`：
  - ✅ 成功/失败都返回 Turbo Stream（不要 `head :unprocessable_entity` 让前端静默失败）
  - ✅ toast 用 `render_toast_turbo_stream(...)`（自动设置 `X-TavernKit-Toast: 1`，用于前端去重）
  - ✅ 需要“状态收敛”的 endpoint（如 `stop_round/skip_turn/cancel_stuck_run/retry_failed_run`）应返回：
    - `group_queue` 的 `replace`（当 `@space.group?`）+ toast
    - 语义化的 HTTP status（前端用 `response.ok` 分支）
- 对 “双来源更新（HTTP + ActionCable）”的组件：
  - 必须带 **单调递增** 的 `render_seq`（例如 `group_queue_revision`），客户端应忽略旧更新（见 `group_queue_controller.js` 的 `turbo:before-stream-render` guard）。

### 前端约定（Stimulus）

- 使用 `fetchTurboStream()`（`playground/app/javascript/turbo_fetch.js`）：
  - ✅ **即使非 2xx** 也会渲染 Turbo Stream body（保证错误 UI 可见）
  - ✅ 用 `response.ok` 判断是否成功（不要假设“有 turbo_stream 就一定成功”）
- toast fallback（避免重复提示）：
  - 若 `!response.ok` 且 `toastAlreadyShown === false`，才触发客户端 toast（`toast:show`）
  - 服务端已 toast 时会设置 `X-TavernKit-Toast: 1`，前端必须尊重该去重信号
- busy/disabled：
  - 对按钮类操作，采用“**全局 request lock** + 点击即 disable + 失败回滚”的模式，防止重复点击和 Turbo replace 后的状态丢失
  - 统一使用 `playground/app/javascript/request_helpers.js`（收口锁/禁用/toast/CSRF/JSON fetch）避免各 controller 自己维护 `processingStates` / `csrfToken` / toast dispatch
  - 底层请求统一用 `@rails/request.js` 生成（CSRF/Accept/JSON/headers），但 Turbo Stream 的“**非 2xx 也渲染**”仍由 `fetchTurboStream()` 保持（避免 `FetchRequest.perform()` 的 status gate）
- DOM helpers：
  - 统一使用 `playground/app/javascript/dom_helpers.js`（如 `escapeHtml` / `copyTextToClipboard`），避免每个 controller 自己实现转义/剪贴板 fallback
  - 避免 `alert()`（用 toast 保持 UX 一致）

---

## 7. 快捷键处理

### Tail-Only 原则

对于修改对话时间线的操作（编辑、删除、重新生成、滑动），只能在尾部消息上执行：

```javascript
// 获取尾部消息
getTailMessageElement() {
  const container = this.getMessagesContainer()
  if (!container) return null
  return container.querySelector(".mes:last-child")
}

// 检查是否可以操作
canRegenerateTail() {
  const tail = this.getTailMessageElement()
  if (!tail) return false
  return tail.dataset.messageRole === "assistant"
}
```

### 条件拦截

只有在操作可执行时才 `preventDefault()`：

```javascript
// ✅ 正确：条件满足时才拦截
if (this.canSwipeTail()) {
  event.preventDefault()
  this.swipeTailAssistant(direction)
}

// ❌ 错误：无条件拦截
event.preventDefault()
this.swipeLastAssistant(direction)
```

---

## 8. 文件组织

### 模板文件

```
playground/app/views/shared/_js_templates.html.erb
```

### 控制器文件

```
playground/app/javascript/controllers/
├── application.js          # 全局事件处理器
├── message_actions_controller.js
├── chat_hotkeys_controller.js
├── copilot_controller.js
└── ...
```

### 添加新模板

1. 在 `_js_templates.html.erb` 中添加 `<template>` 元素
2. 使用 `data-*` 属性标记需要填充的位置
3. 在控制器中通过 `document.getElementById()` 获取模板
4. 使用 `template.content.cloneNode(true)` 克隆
5. 使用 `textContent` 填充用户数据

---

## 9. 互斥状态与竞态条件处理

### 问题场景

当两个功能互斥（如 Auto Mode 和 Copilot Mode 不能同时启用）时，快速点击会导致竞态条件：

```
用户点击 Copilot → 乐观更新 UI（绿色）→ 发送请求 A
用户快速点击 Auto mode → 乐观更新 UI（绿色）→ 发送请求 B
请求 A 成功返回 → 前端认为 Copilot 仍然启用
请求 B 在服务端禁用了 Copilot → 但前端不知道
```

### 解决方案

#### 1. 使用全局 Map 保存处理状态

Turbo Stream 替换 DOM 时会重新初始化 Stimulus 控制器，**实例变量会丢失**。使用模块级全局 Map 保存状态：

```javascript
// ❌ 错误：实例变量在 Turbo Stream 替换后丢失
export default class extends Controller {
  isProcessing = false  // 替换后重置为 false
  
  async toggle() {
    if (this.isProcessing) return  // 无法防止快速点击
    this.isProcessing = true
    // ...
  }
}

// ✅ 正确：使用全局 Map，key 为唯一标识（如 URL）
const processingStates = new Map()

export default class extends Controller {
  static values = { url: String }
  
  get isProcessing() {
    return processingStates.get(this.urlValue) || false
  }
  
  set isProcessing(value) {
    if (value) {
      processingStates.set(this.urlValue, true)
    } else {
      processingStates.delete(this.urlValue)
    }
  }
  
  async toggle() {
    if (this.isProcessing) return  // 即使控制器被替换也有效
    this.isProcessing = true
    try {
      // ... 发送请求
    } finally {
      this.isProcessing = false
    }
  }
}
```

#### 2. 服务端通过 ActionCable 广播状态变更

当服务端因互斥逻辑改变了另一个功能的状态时，**必须主动广播通知前端**：

```ruby
# ❌ 错误：只更新数据库，前端不知道状态变了
def disable_all_copilot_modes!
  memberships.where.not(copilot_mode: "none").update_all(copilot_mode: "none")
end

# ✅ 正确：更新后广播通知前端
def disable_all_copilot_modes!
  memberships.where.not(copilot_mode: "none").find_each do |membership|
    membership.update!(copilot_mode: "none", copilot_remaining_steps: 0)
    # 广播给前端，让对应的控制器更新 UI
    Message::Broadcasts.broadcast_copilot_disabled(membership, reason: "auto_mode_enabled")
  end
end
```

前端控制器监听 ActionCable 事件：

```javascript
handleCopilotDisabled(data) {
  if (data.membership_id === this.membershipIdValue) {
    this.fullValue = false
    this.updateUIForMode()  // 重置按钮状态
    this.showToast(`Copilot disabled (${data.reason})`, "info")
  }
}
```

#### 3. 在 connect() 中同步 UI 状态

Turbo Stream 替换后控制器重新初始化，应在 `connect()` 中根据服务端渲染的 `data-*-value` 属性同步 UI：

```javascript
connect() {
  // ... 订阅 channel、绑定事件
  
  // 关键：同步 UI 状态，确保与 data-*-value 一致
  this.updateUIForMode()
}
```

#### 4. 避免前端覆盖服务端渲染的默认值

```javascript
// ❌ 错误：在 UI 更新方法中硬编码默认值
updateUIForMode() {
  if (!enabled) {
    this.stepsCounterTarget.textContent = "0"  // 覆盖了服务端渲染的 "4"
  }
}

// ✅ 正确：让服务端控制默认值，前端只在激活时更新
updateUIForMode() {
  if (enabled) {
    // 仅在激活时更新 UI，禁用时保留服务端渲染的值
  }
}
```

#### 5. 刷新缓存关联后再渲染 Turbo Stream

Rails 关联可能被缓存，在 Turbo Stream 渲染前需要刷新：

```ruby
def toggle_auto_mode
  disable_all_copilot_modes!  # 更新了 memberships
  
  # ✅ 关键：刷新缓存，确保 Turbo Stream 渲染看到最新状态
  @space.reload
  @space.space_memberships.reload
  
  respond_to do |format|
    format.turbo_stream  # 现在渲染会使用最新的 membership 状态
  end
end
```

#### 6. Turbo Stream `replace` 乱序（Out-of-order update）兜底

**问题现象：**

- 同一个 DOM target（例如 `dom_id(conversation, :group_queue)`）会在短时间内收到多次 `turbo_stream.replace`
- 在“快响应”（例如 mock LLM 几百 ms）或“多进程广播”（web + job）场景下，**到达顺序可能与生成顺序不同**
- 结果是：**旧的 replace 反而最后覆盖了新的 UI**，出现“当前发言人卡在上一个”“Auto mode 结束后还显示上一个角色”等肉眼可见的问题

**错误做法：用 wall-clock time 当序号**

- `Time.current.to_f` / `Process.clock_gettime` 在多进程之间不保证可比（存在 clock skew）
- 旧 update 可能带着更大的 timestamp，导致你错误地保留旧 UI 或丢弃新 UI

**推荐方案：DB 单调递增 revision + 前端拦截过期 replace**

1) **服务端：在被 replace 的 root 元素上输出单调序号**

```erb
<div id="<%= dom_id(conversation, :group_queue) %>"
     data-group-queue-render-seq-value="<%= render_seq %>">
  ...
</div>
```

其中 `render_seq` 必须来自 DB 的单调递增字段（例如 `conversations.group_queue_revision`），并且每次广播前 `increment!`。

2) **前端：在 `turbo:before-stream-render` 中丢弃过期 replace**

```javascript
document.addEventListener("turbo:before-stream-render", (event) => {
  const stream = event.target
  if (!stream || stream.tagName !== "TURBO-STREAM") return
  if (stream.getAttribute("action") !== "replace") return

  const targetId = stream.getAttribute("target")
  const current = targetId ? document.getElementById(targetId) : null
  if (!current) return

  const currentSeqRaw = current.getAttribute("data-group-queue-render-seq-value")
  if (!currentSeqRaw) return

  const incoming = stream.querySelector("template")?.content?.firstElementChild
  const incomingSeqRaw = incoming?.getAttribute("data-group-queue-render-seq-value")

  const currentSeq = Number(currentSeqRaw)
  const incomingSeq = Number(incomingSeqRaw)

  if (Number.isFinite(currentSeq) && Number.isFinite(incomingSeq) && incomingSeq <= currentSeq) {
    event.preventDefault()
  }
})
```

3) **减少“同一 target 多源广播”**

- 尽量把对同一 UI target 的 replace 广播收敛到少数几个“边界点”（例如 scheduler 状态变更、run finalize 之后）
- 避免在“中间态”广播 UI（例如 message commit 时 run 仍是 running），否则 UI 可能长期停留在旧状态

#### 7. ActionCable `conversation_queue_updated` 乱序兜底（scheduling_state）

**问题现象：**

- 多进程/多实例部署中，同一 `conversation` 的 ActionCable JSON 事件可能 **后发先至**
- 如果前端直接使用 `conversation_queue_updated.scheduling_state` 更新输入锁态等 UI，旧事件会把 UI 回滚到旧状态（例如锁态闪回/抖动）

**推荐方案：DB 单调递增 revision + 前端丢弃 stale 事件**

- 服务端：每次 `TurnScheduler::Broadcasts.queue_updated` 都 `increment!` 一个 DB 单调递增字段（复用 `conversations.group_queue_revision`），并把该值随 payload 下发为 `group_queue_revision`
- 前端：维护 `lastQueueRevision`，当收到 `group_queue_revision <= lastQueueRevision` 时直接忽略该事件

这样可以让群聊/单聊共用同一套乱序防护机制：群聊用 revision 保护 Turbo `replace`，同时也保护 ActionCable JSON；单聊虽然不渲染 group queue bar，但仍能用 revision 防止输入锁态被 stale 事件回滚。

### 检查清单

实现互斥功能时，确保：

- [ ] 使用全局 Map 而非实例变量保存 `isProcessing` 状态
- [ ] 服务端改变互斥状态后通过 ActionCable 广播
- [ ] 前端控制器在 `connect()` 中调用 `updateUIForMode()` 同步状态
- [ ] 避免在前端硬编码覆盖服务端渲染的默认值
- [ ] Turbo Stream 渲染前刷新可能被缓存的关联
- [ ] 添加 `try/finally` 确保 `isProcessing` 在异常时也能重置
- [ ] 对同一 target 多次 `turbo_stream.replace` 的场景：有 DB revision + `turbo:before-stream-render` 兜底，避免乱序覆盖

---

## 更新日志

| 日期 | 更新内容 |
|------|----------|
| 2026-01-11 | 添加互斥状态与竞态条件处理（Turbo Stream + 全局状态 + ActionCable）；补充 Turbo Stream `replace` 乱序兜底（DB revision + before-stream-render guard） |
| 2026-01-10 | 添加 SillyTavern 消息布局文档、prose-theme 说明 |
| 2026-01-05 | 初始版本：模板模式、toast 标准化、XSS 防护 |
