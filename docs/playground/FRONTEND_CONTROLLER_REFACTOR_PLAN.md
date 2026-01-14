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
- **Import dropzone 复用**：`preset_import` / `character_import` / `lorebook_import` 的 drag/drop + file preview + submit state 高度重复，建议收口为 `ui/import_dropzone`。

## 约束与偏好（本轮约定）

- **拆分方式**：先拆为多个“模块文件”（不拆成多个 Stimulus controllers），避免改动 ERB targets/values 带来的风险。
- **目录组织**：使用分目录组织复用模块（例如 `playground/app/javascript/chat/*`）。
- **原则**：尽量只做“搬运/收口/命名”不改行为；每一步都跑 `cd playground && bin/ci`。

## 本轮 TODO（收口/复用）

> 目标：在 Phase 1 收尾阶段，把“重复实现 / 隐式契约 / 风格漂移”的风险进一步压低。

- [x] **继续提纯可复用模块**：优先做“跨 controller 的复用”（例如通用 DOM helper、通用 UI 模板/partial），避免重复实现回潮
  - ✅ 新增：`playground/app/javascript/ui/dom.js`（通用 `el()` / `lucide()`），并在 `run_detail_modal` 与 `clipboard` 等处复用
- [x] **低风险一致性**：把少量“仅用于清空容器”的 `innerHTML = ""` 改为 `replaceChildren()`（不改行为）
  - ✅ 迁移：`schema_renderer` / `copilot candidates`
- [x] **中收益一致性**：把剩余页面的 Empty State 逐步迁移到 `shared/_empty_state.html.erb`（必要时扩展支持多按钮/按钮类型）
  - ✅ 覆盖：`characters` / `presets` / `lorebooks` / `settings/characters` / `conversations#show`

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
- ✅ 已完成：
  - `message_actions_controller.js` 已拆到 `playground/app/javascript/chat/message_actions/*`
  - 体积：约 `476` 行 → `227` 行（保持行为一致，CI 通过）
- `chat_scroll_controller.js`：
  - 按职责拆模块：scroll/bottom/history-loader/cable-sync/observers/indicators
- ✅ 已完成：
  - `chat_scroll_controller.js` 已拆到 `playground/app/javascript/chat/scroll/*`
  - 体积：约 `394` 行 → `76` 行（保持行为一致，CI 通过）
- `run_detail_modal_controller.js`：
  - 按职责拆模块：formatters/tabs/render
- ✅ 已完成：
  - `run_detail_modal_controller.js` 已拆到 `playground/app/javascript/ui/run_detail_modal/*`
  - 体积：约 `512` 行 → `56` 行（保持行为一致，CI 通过）
- `schema_renderer_controller.js`：
  - 按职责拆模块：layout/render/visibility/targets
- ✅ 已完成：
  - `schema_renderer_controller.js` 已拆到 `playground/app/javascript/ui/schema_renderer/*`
  - 体积：约 `433` 行 → `134` 行（保持行为一致，CI 通过）

- `chat_hotkeys_controller.js`：
  - 按职责拆模块：keydown/tail/edit/actions/help-modal
- ✅ 已完成：
  - `chat_hotkeys_controller.js` 已拆到 `playground/app/javascript/chat/hotkeys/*`
  - 体积：约 `382` 行 → `48` 行（保持行为一致，CI 通过）

- `settings_form_controller.js`：
  - 按职责拆模块：autosave/patch-builder/requests/resource-sync/status-badge
- ✅ 已完成：
  - `settings_form_controller.js` 已拆到 `playground/app/javascript/ui/settings_form/*`
  - 体积：约 `353` 行 → `85` 行（保持行为一致，CI 通过）

- `llm_settings_controller.js`：
  - 按职责拆模块：api-key-visibility/requests/loading-state/models/status/form-data
- ✅ 已完成：
  - `llm_settings_controller.js` 已拆到 `playground/app/javascript/ui/llm_settings/*`
  - 体积：约 `241` 行 → `44` 行（保持行为一致，CI 通过）

- `message_form_controller.js`：
  - 按职责拆模块：bindings/cable-events/lock-state/submit/typing
- ✅ 已完成：
  - `message_form_controller.js` 已拆到 `playground/app/javascript/chat/message_form/*`
  - 体积：约 `269` 行 → `107` 行（保持行为一致，CI 通过）

- `auto_mode_toggle_controller.js`：
  - 按职责拆模块：bindings/actions/requests/ui
- ✅ 已完成：
  - `auto_mode_toggle_controller.js` 已拆到 `playground/app/javascript/chat/auto_mode/*`
  - 体积：约 `248` 行 → `63` 行（保持行为一致，CI 通过）

- `markdown_controller.js`：
  - 按职责拆模块：marked-config/visibility/fallback/output
- ✅ 已完成：
  - `markdown_controller.js` 已拆到 `playground/app/javascript/ui/markdown/*`
  - 体积：约 `247` 行 → `93` 行（保持行为一致，CI 通过）

- `preset_selector_controller.js`：
  - 按职责拆模块：modal/apply/save/requests
- ✅ 已完成：
  - `preset_selector_controller.js` 已拆到 `playground/app/javascript/ui/preset_selector/*`
  - 体积：约 `185` 行 → `73` 行（保持行为一致，CI 通过）

- `authors_note_form_controller.js`：
  - 按职责拆模块：save/requests/form-data/status/char-count
- ✅ 已完成：
  - `authors_note_form_controller.js` 已拆到 `playground/app/javascript/ui/authors_note_form/*`
  - 体积：约 `179` 行 → `50` 行（保持行为一致，CI 通过）

- `toast_controller.js`：
  - 按职责拆模块：animation/countdown/bindings
- ✅ 已完成：
  - `toast_controller.js` 已拆到 `playground/app/javascript/ui/toast/*`
  - 体积：约 `176` 行 → `49` 行（保持行为一致，CI 通过）

- `character_picker_controller.js`：
  - 按职责拆模块：bindings/frame-load/ui-sync/links
- ✅ 已完成：
  - `character_picker_controller.js` 已拆到 `playground/app/javascript/ui/character_picker/*`
  - 体积：约 `175` 行 → `70` 行（保持行为一致，CI 通过）

- `touch_swipe_controller.js`：
  - 按职责拆模块：bindings/gesture/requests
- ✅ 已完成：
  - `touch_swipe_controller.js` 已拆到 `playground/app/javascript/chat/touch_swipe/*`
  - 体积：约 `154` 行 → `67` 行（保持行为一致，CI 通过）

- `sidebar_controller.js`：
  - 按职责拆模块：storage/keyboard/tabs
- ✅ 已完成：
  - `sidebar_controller.js` 已拆到 `playground/app/javascript/ui/sidebar/*`
  - 体积：约 `139` 行 → `64` 行（保持行为一致，CI 通过）

- `runs_panel_auto_refresh_controller.js`：
  - 按职责拆模块：bindings/storage/timer/refresh（并抽通用 `ui/turbo_frame/refresh`）
- ✅ 已完成：
  - `runs_panel_auto_refresh_controller.js` 已拆到 `playground/app/javascript/ui/runs_panel_auto_refresh/*`
  - 新增：`playground/app/javascript/ui/turbo_frame/refresh.js`
  - 体积：约 `121` 行 → `35` 行（保持行为一致，CI 通过）

- `preset_import_controller.js` / `character_import_controller.js` / `lorebook_import_controller.js`：
  - 抽通用 dropzone：drag events/state/file info/dialog-close reset
- ✅ 已完成：
  - 迁移到 `playground/app/javascript/ui/import_dropzone/*`
  - 体积：约 `168` 行 → `63` 行（每个 controller，保持行为一致，CI 通过）
