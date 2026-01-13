# Frontend Controller Refactor Plan (Phase 1 polish)

目标：**先提纯可复用模块**（复用/一致性优先），再逐步把大体积 Stimulus controller 变薄，最终让实现更正交、可维护、可测试。

## 当前结论（落盘）

### 1) 大体积 controller（优先级从高到低）

> 体积不等于坏，但体积越大越容易出现“重复实现 / 隐式契约 / 行为漂移”。

- `playground/app/javascript/controllers/conversation_channel_controller.js`（typing indicator / stuck detection / idle alert / health check / duplicate-prevention / cable 连接事件）
- `playground/app/javascript/controllers/copilot_controller.js`（channel subscription / keyboard shortcuts / candidates list / mode toggle / state sync）
- `playground/app/javascript/controllers/message_actions_controller.js`（tail-only 规则 / list registry + MutationObserver / copy / edit-mode 键盘 / debug modal）

### 2) 复用优先的提纯点（横切面）

- **Chat DOM 访问与 tail 语义**：messages list / tail message / message dataset 读取在多个 controller 内分散，建议先收口为 `chat/dom`。
- **ActionCable subscription 封装**：`cable.subscribeTo` 的错误处理、unsubscribe、通用参数校验在多个 controller 重复，建议收口为 `chat/cable`（或 `realtime/subscription`）。
- **Window event 常量/dispatch**：`cable:*`、`scheduling:*`、`user:typing:disable-*`、`auto-mode:disabled` 等字符串常量分散，建议收口为 `chat/events`（并统一 helper，降低拼写风险）。
- **模板克隆（可选）**：`copilot` / `tags_input` 都在用 `<template>.content.cloneNode`，如后续增加更多模板，考虑抽 `ui/template`（非必须）。

## 约束与偏好（本轮约定）

- **拆分方式**：先拆为多个“模块文件”（不拆成多个 Stimulus controllers），避免改动 ERB targets/values 带来的风险。
- **目录组织**：使用分目录组织复用模块（例如 `playground/app/javascript/chat/*`）。
- **原则**：尽量只做“搬运/收口/命名”不改行为；每一步都跑 `cd playground && bin/ci`。

## 分步执行计划（1 → 3）

### Step 1：提纯 `chat/dom`

- ✅ 已完成：
  - 新增：`playground/app/javascript/chat/dom.js`
  - 迁移：`playground/app/javascript/controllers/chat_hotkeys_controller.js`

- 新增：`playground/app/javascript/chat/dom.js`
  - `findMessagesList(root, conversationId?)`
  - `findTailMessage(list)`
  - （可选）`readMessageMeta(el)`：统一 role/has_swipes/message_id/participant_id 读取
- 迁移：优先迁移 `chat_hotkeys_controller.js` 的 tail 查找与 dataset 读取（对外行为不变）。

### Step 2：提纯 `chat/events`

- ✅ 已完成：
  - 新增：`playground/app/javascript/chat/events.js`
  - 迁移：`conversation_channel` / `message_form` / `chat_scroll` / `auto_mode_toggle` / `copilot` 等 controllers

- 新增：`playground/app/javascript/chat/events.js`
  - 导出事件名常量 + 小型 `dispatchChatEvent(...)` helper
- 迁移：先改 `conversation_channel_controller.js`（dispatch）与 `message_form_controller.js`（listen/dispatch）作为示范，再逐步覆盖其他。

### Step 3：提纯 `chat/cable`（订阅封装）

- ✅ 已完成：
  - 新增：`playground/app/javascript/chat/cable_subscription.js`
  - 迁移：`conversation_channel_controller.js` / `copilot_controller.js`

- 新增：`playground/app/javascript/chat/cable_subscription.js`
  - `subscribeTo(channelParams, { received, connected, disconnected, rejected })`
  - 统一 try/catch + unsubscribe + “缺少 id/value 时的早退策略”
- 迁移：先迁移 `copilot_controller.js` 与 `conversation_channel_controller.js` 的 subscription 部分，保持行为一致。

## 后续：逐步变薄大 controller（不改 UI 结构）

- `conversation_channel_controller.js`：
  - 按职责拆模块：typing/stuck/idle/health/duplicate-prevention/scheduling-events
- ✅ 已完成：
  - `conversation_channel_controller.js` 已拆到 `playground/app/javascript/chat/conversation_channel/*`
  - 体积：约 `836` 行 → `423` 行（保持行为一致，CI 通过）
- `copilot_controller.js`：
  - 按职责拆模块：subscription/keyboard/candidates/mode-toggle/ui-sync
- ✅ 已完成：
  - `copilot_controller.js` 已拆到 `playground/app/javascript/chat/copilot/*`
  - 体积：约 `648` 行 → `293` 行（保持行为一致，CI 通过）
- `message_actions_controller.js`：
  - 按职责拆模块：tail-detection/list-registry/copy/edit-keys/debug-modal
