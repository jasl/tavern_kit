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
<template id="toast-template">
  <div class="alert shadow-lg">
    <span data-toast-message></span>
  </div>
</template>

<%# Toast 容器（预渲染，始终存在）%>
<div id="toast-container" class="toast toast-end toast-top z-50"></div>

<%# 标签芯片模板 %>
<template id="tag-chip-template">
  <span class="badge badge-sm badge-primary gap-1" data-tags-input-target="tag">
    <span data-tag-text></span>
    <button type="button" class="hover:text-error" data-action="tags-input#remove">&times;</button>
  </span>
</template>
```

#### JavaScript 使用方式

```javascript
// 获取模板
const template = document.getElementById("toast-template")
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
- `run_detail_modal_controller.js`：模态框内容模板过大，考虑使用 Turbo Frame 懒加载
- `llm_settings_controller.js`：连接状态 UI 较复杂，可考虑 Turbo Streams
- `prompt_preview_controller.js`：服务端返回预渲染的 HTML

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

1. 获取 `toast-template` 模板
2. 克隆并填充数据
3. 添加到 `toast-container`
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

## 6. 快捷键处理

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

## 7. 文件组织

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

## 更新日志

| 日期 | 更新内容 |
|------|----------|
| 2026-01-10 | 添加 SillyTavern 消息布局文档、prose-theme 说明 |
| 2026-01-05 | 初始版本：模板模式、toast 标准化、XSS 防护 |
