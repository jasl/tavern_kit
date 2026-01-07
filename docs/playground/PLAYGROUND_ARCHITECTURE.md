# Playground Architecture

本文档描述 Playground 的核心架构设计，包括数据模型、服务层、实时通信和前端架构。

另见：
- `CONVERSATION_RUN.md`：Run 状态机与调度
- `CONVERSATION_AUTO_RESPONSE.md`：自动回复与调度机制
- `BRANCHING_AND_THREADS.md`：分支与线程
- `SPACE_CONVERSATION_ARCHITECTURE.md`：Space/Conversation 架构详解
- `SCHEMA_PACK_PROMPT_BUILDER_INTEGRATION.md`：Schema Pack 与 PromptBuilder 对接

---

## 核心设计原则

### 正交拆分（Orthogonal Separation）

三层架构各司其职，避免职责混淆：

| 层 | 职责 | 不存储 |
|---|------|--------|
| **Space** | 权限、参与者、默认策略/设置 | 运行态 |
| **Conversation** | 消息时间线（timeline） | 运行态 |
| **ConversationRun** | 运行态执行状态机 | 配置 |

### 无 Placeholder Message

- 流式内容只更新 typing indicator（ActionCable JSON 事件）
- 生成完成后一次性创建最终 Message（Turbo Streams DOM 更新）
- 避免 broadcast race condition

### 异步 IO 强制约束

- 除 "Test Connection" 外，所有 `LLMClient` 调用必须在 `ActiveJob` 中执行
- 禁止在 Controller/Model 中直接调用 LLM API 阻塞请求

---

## 数据模型

### Space（STI）

空间是权限和配置的容器，使用 Single Table Inheritance：

- `Spaces::Playground`：单人角色扮演（一个人类 + 多个 AI 角色）
- `Spaces::Discussion`：多人讨论（预留）

```ruby
# 核心字段
spaces:
  - type: STI 类型（Spaces::Playground / Spaces::Discussion）
  - owner_id: 所有者 User
  - name: 空间名称
  - status: active / archived / deleting
  - reply_order: manual / natural / list / pooled
  - card_handling_mode: swap / append / append_disabled
  - allow_self_responses: 是否允许同一 speaker 连续发言
  - auto_mode_enabled: AI→AI followup
  - auto_mode_delay_ms: followup 延迟
  - during_generation_user_input_policy: reject / queue / restart
  - user_turn_debounce_ms: 用户消息 debounce
  - group_regenerate_mode: single_message / last_turn
  - prompt_settings: jsonb（preset / world_info / scenario_override 等）
  - settings_version: 乐观锁版本号
```

### SpaceMembership

空间内身份，设计为 **Author Anchor**（作者锚点）：移除成员时不删除记录，保留历史消息的作者引用。

```ruby
# 核心字段
space_memberships:
  - space_id: 所属 Space
  - kind: human / character
  - user_id: 真人用户（kind=human）
  - character_id: 角色卡（kind=character）
  - role: owner / member / moderator
  - position: 排序（0-based）
  - status: active / removed（生命周期）
  - participation: active / muted / observer（参与度）
  - copilot_mode: none / full
  - copilot_remaining_steps: full 模式剩余步数（1-10）
  - llm_provider_id: LLM Provider 覆盖
  - settings: jsonb（llm.* 配置）
  - settings_version: 乐观锁版本号
  - cached_display_name: 缓存显示名
  - persona: 覆盖 persona
  - removed_at / removed_by_id / removed_reason: 移除追踪
```

**关键 Scopes：**
- `active`：`status = 'active'`
- `participating`：`status = 'active' AND participation = 'active'`
- `removed`：`status = 'removed'`

### Conversation

消息时间线，支持树结构（branching）：

```ruby
# 核心字段
conversations:
  - space_id: 所属 Space
  - kind: root / branch / thread
  - title: 标题
  - visibility: shared / private
  - parent_conversation_id: 父会话
  - root_conversation_id: 根会话
  - forked_from_message_id: 分支点消息
```

**树结构规则：**
- 根会话：`root_conversation_id == id`
- 子会话：`root_conversation_id` 继承自父会话
- `forked_from_message` 必须属于 `parent_conversation`

### Message + MessageSwipe

消息由 `SpaceMembership` 创作（非直接关联 User/Character）：

```ruby
# messages
messages:
  - conversation_id: 所属 Conversation
  - space_membership_id: 发送者身份
  - seq: conversation 内确定性顺序（唯一）
  - role: user / assistant / system
  - content: 内容（活跃 swipe 内容的缓存）
  - active_message_swipe_id: 当前活跃 swipe
  - message_swipes_count: swipe 数量
  - conversation_run_id: 关联的生成 run
  - origin_message_id: 克隆来源（branch 时）
  - metadata: jsonb 调试信息

# message_swipes
message_swipes:
  - message_id: 所属 Message
  - position: 版本位置（0-based）
  - content: 内容
  - metadata: jsonb
  - conversation_run_id: 生成此 swipe 的 run
```

### ConversationRun

运行态执行单元，详见 `CONVERSATION_RUN.md`：

```ruby
# conversation_runs
conversation_runs:
  - id: uuid 主键
  - conversation_id: 所属 Conversation
  - kind: user_turn / auto_mode / regenerate / force_talk
  - status: queued / running / succeeded / failed / canceled / skipped
  - reason: 触发原因
  - speaker_space_membership_id: 本次生成的 speaker
  - run_after: 计划执行时间（debounce）
  - cancel_requested_at: 软取消标记
  - started_at / finished_at: 执行时间
  - heartbeat_at: running 心跳（stale 检测）
  - error / debug: jsonb 诊断信息
```

**并发约束（DB 层唯一索引）：**
- 每 conversation 最多 1 个 `running` run
- 每 conversation 最多 1 个 `queued` run（单槽队列）

### Character

角色卡持久化模型，支持 CCv2/CCv3 格式：

```ruby
# characters
characters:
  - name / nickname / personality: 展示字段
  - data: jsonb（V2/V3 完整数据）
  - spec_version: 2 或 3
  - file_sha256: 导入去重
  - status: pending / ready / failed / deleting
  - tags / supported_languages: 数组字段
```

---

## 服务层架构

### Prompt 构建

```
ContextBuilder（薄封装）
    ↓
PromptBuilder（Playground → TavernKit 适配层）
    ↓
TavernKit.build(...).to_messages
```

- `ContextBuilder`：负责 history cutoff、card mode 映射
- `PromptBuilder`：编排器，负责组装 `TavernKit.build` 参数
- `PromptBuilding::*`：拆分后的规则章节（preset/world-info/authors-note/群聊卡片合并/历史适配等）
- `Space.prompt_settings`：空间级 prompt 配置入口（preset/world_info/scenario_override 等）

#### Prompt History（窗口语义）

- Playground 中的历史消息是 **为 TavernKit 提供的 data source**，而不是“全量消息容器”。
  - `PromptBuilding::MessageHistory` 负责把 `Message` 关系适配为 `TavernKit::ChatHistory::Base`（可遍历、可计数、只读）。
- 默认行为：`PromptBuilder` 会在构建 history relation 时**先过滤** `excluded_from_prompt = true`，再应用默认窗口：
  - 默认窗口：最近 **200 条**（按消息数）included messages（略多于常见 prompt 需要，降低 DB/内存成本）。
  - 该窗口控制完全由 Playground 负责；TavernKit 只消费一个 windowed history。
- 覆盖行为：可以通过 `PromptBuilder.new(..., history_scope:)` 显式传入自定义范围：
  - 若 scope **带显式 limit**：尊重调用方的 limit（不再额外套默认窗口）。
  - 若 scope **不带 limit**：仍会套用默认窗口（最近 200 条），避免“无意全量”导致 DB 压力。

### Run 调度

```
Conversations::RunPlanner（计划 queued run）
    ↓
ConversationRunJob（ActiveJob 入口）
    ↓
Conversations::RunExecutor（执行 run）
    ↓
SpeakerSelector（选择 speaker）
```

- `RunPlanner`：处理 debounce、policy、copilot、auto-mode
- `RunExecutor`：claim → stream → persist → followup
- `SpeakerSelector`：manual / natural / list / pooled 策略

### 分支操作

```ruby
Conversations::Forker.new(
  parent_conversation: conversation,
  fork_from_message: message,
  kind: "branch",
  title: "My Branch",
  visibility: "shared"
).call
```

- 仅 Playground 空间允许 branch
- 事务内克隆消息前缀 + swipes
- 保留 `seq`、`origin_message_id`

### 控制器-服务层职责分离

控制器应保持精简，仅负责以下职责：

1. **资源查询** - 从数据库加载模型
2. **鉴权** - 检查用户权限（Authorization concern）
3. **调用服务** - 将业务逻辑委托给服务层
4. **渲染响应** - 根据结果返回适当的 HTTP 响应

**服务层承担所有业务逻辑**：

- 策略检查（如 copilot 模式、生成锁定）
- 数据验证和持久化
- 副作用（广播、触发后续任务）
- 复杂的业务规则

#### 服务模式：Result 对象

使用 `Data.define` 创建不可变的 Result 对象：

```ruby
# app/services/messages/creator.rb
class Messages::Creator
  Result = Data.define(:success?, :message, :error, :error_code)

  def initialize(conversation:, membership:, content:)
    @conversation = conversation
    @membership = membership
    @content = content
  end

  def call
    return copilot_blocked_result if copilot_blocks_manual_input?
    return generation_locked_result if reject_policy_blocks?

    message = build_message
    if message.save
      message.broadcast_create
      plan_ai_response!(message)
      success_result(message)
    else
      validation_error_result(message)
    end
  end

  private

  def success_result(message)
    Result.new(success?: true, message: message, error: nil, error_code: nil)
  end

  def copilot_blocked_result
    Result.new(success?: false, message: nil, error: "...", error_code: :copilot_blocked)
  end
  # ...
end
```

#### 控制器使用服务

```ruby
# app/controllers/messages_controller.rb
def create
  @membership = @space.space_memberships.active.find_by(user_id: Current.user.id, kind: "human")
  return head :forbidden unless @membership

  result = Messages::Creator.new(
    conversation: @conversation,
    membership: @membership,
    content: message_params[:content]
  ).call

  respond_to_create_result(result)
end

private

def respond_to_create_result(result)
  if result.success?
    @message = result.message
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to conversation_url(@conversation, anchor: helpers.dom_id(@message)) }
    end
  else
    case result.error_code
    when :copilot_blocked
      respond_to { |f| f.turbo_stream { head :forbidden }; f.html { redirect_to ..., alert: ... } }
    when :generation_locked
      respond_to { |f| f.turbo_stream { head :locked }; f.html { redirect_to ..., alert: ... } }
    else
      # validation error handling
    end
  end
end
```

#### 服务命名约定

| 动作 | 服务名 | 示例 |
|------|--------|------|
| 创建资源 | `Domain::Creator` | `Messages::Creator` |
| 删除资源 | `Domain::Destroyer` | `Messages::Destroyer` |
| 更新资源 | `Domain::Updater` | `Settings::Updater` |
| 复杂操作 | `Domain::动词` | `Conversations::Forker` |
| 纯类方法 | `Domain::动词er` | `Conversations::RunPlanner` |

#### 服务目录结构

```
app/services/
├── messages/
│   ├── creator.rb
│   ├── destroyer.rb
│   └── swipes/
│       ├── adder.rb
│       ├── initial_swipe_ensurer.rb
│       └── selector.rb
├── conversation/
│   ├── run_executor.rb
│   ├── run_executor/
│   │   ├── run_claimer.rb
│   │   ├── run_followups.rb
│   │   ├── copilot_user_finder.rb
│   │   ├── run_generation.rb
│   │   └── run_persistence.rb
│   ├── run_planner.rb
│   └── run_planner/
│       ├── auto_mode_planner.rb
│       └── copilot_planner.rb
├── conversations/
│   └── first_messages_creator.rb
├── prompt_building/
│   ├── preset_resolver.rb
│   ├── authors_note_resolver.rb
│   └── ...
├── conversation_settings/
│   ├── field_enumerator.rb
│   └── storage_applier.rb
├── space_memberships/
│   └── settings_patch.rb
└── ...
```

---

## 实时通信架构

### 通道分离

| 通道 | 职责 | 事件类型 |
|------|------|----------|
| `ConversationChannel` | 临时状态（typing/streaming） | JSON 事件 |
| `Turbo::StreamsChannel` | 持久 DOM 变更 | Turbo Streams |
| `CopilotChannel` | Copilot 候选回复（按 membership 单播） | JSON 事件 |

### 流式生成流程

```
1. broadcast_typing_start（显示 typing indicator）
2. stream_chunk → typing indicator 更新内容
3. LLM 完成 → 创建 Message（原子操作）
4. Turbo Stream append（DOM 更新）
5. broadcast_typing_stop
```

**核心原则：**
- 流式内容在 typing indicator 中显示（ephemeral）
- Message 在内容完全就绪后才创建（persistent）
- 避免 placeholder message 的 race condition

---

## 前端架构

### Stimulus 控制器

| 控制器 | 职责 |
|--------|------|
| `conversation_channel_controller` | ActionCable 订阅、事件分发 |
| `chat_scroll_controller` | Intersection Observer 加载历史消息 |
| `chat_hotkeys_controller` | 聊天热键（Swipe/Regenerate/Edit） |
| `message_form_controller` | 消息输入表单 |
| `message_actions_controller` | 消息操作（编辑/删除/再生成） |
| `copilot_controller` | Copilot 候选回复生成 |
| `schema_renderer_controller` | Schema-driven 设置布局 |
| `settings_form_controller` | 设置自动保存（debounce 300ms） |
| `prompt_preview_controller` | Prompt 预览面板 |
| `markdown_controller` | Markdown 渲染 |

### Settings Schema Pack

设置 UI 由 JSON Schema 驱动：

```
app/settings_schemas/* (manifest + root + defs + providers)
                ↓
SettingsSchemaPack.bundle → GET /schemas/settings
                ↓
ConversationSettings::FieldEnumerator → server 渲染 leaf fields
                ↓
schema_renderer_controller.js → layout + visibleWhen + group/order
                ↓
settings_form_controller.js → debounce PATCH
```

**Schema 扩展：**
- `x-storage`：字段存储位置映射
- `x-ui.group / order / quick`：UI 布局
- `x-ui.visibleWhen`：条件显示（provider gating）

---

## 路由结构

```ruby
# 主要路由
resources :playgrounds do
  resources :space_memberships
  resources :conversations, only: [:create]
  resources :copilot_candidates, only: [:create]
  resource :prompt_preview, only: [:create]
end

resources :conversations, only: [:show, :edit, :update, :destroy] do
  resources :messages, only: [:index, :create, :update, :destroy]
  post :branch
  post :regenerate
  post :generate
end

namespace :settings do
  resources :characters
  resources :llm_providers
end

namespace :schemas do
  resource :settings, only: [:show]
end
```

---

## 文件结构

```
playground/app/
├── channels/
│   ├── conversation_channel.rb
│   └── copilot_channel.rb
├── controllers/
│   ├── conversations_controller.rb
│   ├── messages_controller.rb
│   ├── playgrounds_controller.rb
│   ├── space_memberships_controller.rb
│   ├── playgrounds/
│   │   ├── copilot_candidates_controller.rb
│   │   └── prompt_previews_controller.rb
│   ├── conversations/
│   │   └── messages/swipes_controller.rb
│   └── settings/
│       ├── characters_controller.rb
│       └── llm_providers_controller.rb
├── models/
│   ├── space.rb
│   ├── spaces/playground.rb
│   ├── spaces/discussion.rb
│   ├── space_membership.rb
│   ├── conversation.rb
│   ├── conversation_run.rb
│   ├── message.rb
│   ├── message_swipe.rb
│   ├── character.rb
│   ├── llm_provider.rb
│   └── ...
├── services/
│   ├── context_builder.rb
│   ├── prompt_builder.rb
│   ├── speaker_selector.rb
│   ├── conversation/
│   │   ├── run_planner.rb
│   │   ├── run_planner/
│   │   │   └── ...
│   │   ├── run_executor.rb
│   │   ├── run_executor/
│   │   │   └── ...
│   │   ├── forker.rb
│   │   └── copilot_candidate_generator.rb
│   ├── messages/
│   │   └── swipes/
│   │       └── ...
│   ├── prompt_building/
│   │   └── ...
│   ├── character_import/
│   │   └── ...
│   ├── character_export/
│   │   └── ...
│   └── conversation_settings/
│       ├── field_enumerator.rb
│       └── storage_applier.rb
├── jobs/
│   ├── conversation_run_job.rb
│   ├── conversation_run_reaper_job.rb
│   ├── character_import_job.rb
│   └── character_delete_job.rb
└── javascript/controllers/
    ├── conversation_channel_controller.js
    ├── chat_scroll_controller.js
    ├── chat_hotkeys_controller.js
    ├── copilot_controller.js
    ├── schema_renderer_controller.js
    ├── settings_form_controller.js
    └── ...
```

---

## 最佳实践

### 1. 实时通信：避免 Broadcast Race Condition

**核心原则：**
- 分离 ephemeral（typing/streaming）与 persistent（message）状态
- 消息原子创建（不使用 placeholder）
- 统一 JSON 通道（同一 conversation 的事件走同一 channel）
- typing indicator 作为 streaming 容器

**检查清单：**
- [ ] ephemeral 与 persistent 状态是否分离？
- [ ] Message 是否在内容就绪后才创建？
- [ ] 同一 conversation 的 JSON 事件是否统一通道？
- [ ] 前端是否使用 typing indicator 显示流式内容？

### 2. Namespaced ApplicationController 模式

为 namespace 创建专用基类，所有该 namespace 下的控制器继承自这个基类：

```ruby
# app/controllers/playgrounds/application_controller.rb
module Playgrounds
  class ApplicationController < ::ApplicationController
    include TrackedSpaceVisit  # 加载 @space，验证权限
  end
end

# app/controllers/playgrounds/copilot_candidates_controller.rb
class Playgrounds::CopilotCandidatesController < Playgrounds::ApplicationController
  # @space 已加载并验证权限
end
```

**已有 Namespace 基类：**
| Namespace | 基类 | 主要职责 |
|-----------|------|---------|
| `Playgrounds` | `playgrounds/application_controller.rb` | 加载 `@space`，验证空间访问权限 |
| `Conversations` | `conversations/application_controller.rb` | 加载 `@conversation`，验证访问权限 |
| `Settings` | `settings/application_controller.rb` | 验证管理员权限 |

### 3. Typing Indicator 动态样式

在 `broadcast_typing` 时携带完整样式信息，前端根据这些信息动态更新：

```ruby
def broadcast_typing(conversation, membership:, active:)
  broadcast_to(conversation, {
    type: active ? "typing_start" : "typing_stop",
    membership_id: membership.id,
    name: membership.display_name,
    is_user: membership.user?,
    avatar_url: membership_avatar_url(membership),
    bubble_class: typing_bubble_class(membership),
  })
end
```

---

## 已知限制与 TODO

| ID | 内容 | 优先级 |
|----|------|--------|
| TD-1 | Lorebooks / Presets tab 真实内容 | P3 |
| TD-2 | RAG / 知识库（schema 已预留但默认禁用） | P2 |
| TD-3 | Memory（summary / vector memory；schema 已预留） | P2 |
| TD-4 | PWA 支持 | P3 |

---

## 本地验证命令

```bash
# Playground 全量 CI gate（rubocop / audits / tests / seeds）
cd playground && bin/ci

# 重建本地 DB（primary/queue/cable/test）并重新 seeds（允许 drop & recreate）
cd playground && bin/setup --skip-server --reset

# Playground Rails 测试
cd playground && bin/rails test

# Zeitwerk 检查
cd playground && bin/rails zeitwerk:check

# TavernKit Gem 测试
bundle exec rake test

# Lint 检查
ruby bin/lint-eof --fix
bin/rubocop -A
playground/bin/rubocop -A
```
