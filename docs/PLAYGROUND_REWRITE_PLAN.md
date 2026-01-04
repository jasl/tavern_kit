# Playground 重写方案（历史文档 / 已归档）

> NOTE (2026-01-03): 本文档写于 Space + Conversation 架构替换之前，现已归档。  
> 当前实现的“实际变更说明”见：`docs/PLAYGROUND_REWRITE_CHANGELOG_2026-01-03.md`。  
> 下文中出现的旧 Room/Membership/room_runs 术语仅用于历史参考，请勿按其实现细节做新开发。

## 概述

本文档详细描述将 Playground 按照 Campfire 风格彻底重写的方案。我们将借鉴 Campfire 的产品交互、代码风格和架构模式，同时保留 Playground 的 LLM 集成能力和调试特性。

## 自动回复与调度（现状：Run-driven）

Playground 的自动回复/调度已升级为 **Run 驱动（conversation_runs）**：

- `Space` 管权限/参与者/默认值，不存运行态
- `Conversation` 管消息时间线，不存运行态
- 运行态全部落在 `conversation_runs`（queued/running/succeeded/failed/canceled/skipped）
- 自动回复/调度机制的唯一可信文档：`docs/CONVERSATION_AUTO_RESPONSE.md`

### 目标

1. **学习并采用 Campfire 最佳实践**
   - Rails full-stack 开发模式
   - Turbo + Stimulus 驱动的实时交互
   - 简洁高效的代码风格

2. **保留 Playground 核心价值**
   - LLM Playground 定位
   - 完整的 LLM Provider 集成
   - TailwindCSS + DaisyUI 样式框架
   - 角色卡和 TavernKit 集成

3. **差异化功能**
   - 多对话支持（vs Campfire 单一聊天室）
   - AI 用户与真实用户的区分
   - 角色卡绑定的自动聊天功能

---

## 第一部分：Campfire 架构分析

### 1.1 数据模型

Campfire 的核心数据模型：

```
Users (用户)
├── member (普通成员)
├── administrator (管理员)
└── bot (机器人)
Rooms (聊天室)
├── Open (开放房间)
├── Closed (私密房间)
└── Direct (私信)
Memberships (用户-房间关联)
Messages (消息)
Settings (全局设置，键值对存储)
```

**关键特性：**
- 使用 Setting 模型存储全局配置
- 用户通过 `has_secure_password` 认证
- 房间通过 Membership 进行访问控制
- 消息使用 ActionText 支持富文本

### 1.2 认证系统

Campfire 实现了完整的自托管认证：

```ruby
# 核心组件
- Session 模型 (存储会话 token)
- Authentication concern (处理登录状态)
- SessionsController (登录/登出)
- FirstRunsController (首次启动向导)
```

**特性：**
- 基于 Session 模型的认证（非 Devise）
- QR 码跨设备登录
- 邀请链接加入

### 1.3 实时通信

```ruby
# ActionCable 架构
RoomChannel
├── subscribed (订阅房间)
└── stream_for @room

# 广播机制
Message::Broadcasts
├── broadcast_create (追加消息)
└── broadcast_remove (删除消息)
```

### 1.4 前端架构

Campfire 使用 importmap + Stimulus 的轻量级前端：

```
app/javascript/
├── application.js          # 入口
├── controllers/             # Stimulus 控制器
│   ├── messages_controller.js
│   ├── composer_controller.js
│   └── ...
├── helpers/                 # DOM/导航工具
├── models/                  # 业务模型
│   ├── client_message.js
│   ├── file_uploader.js
│   └── scroll_manager.js
└── initializers/            # 初始化逻辑
```

### 1.5 代码风格要点

**Ruby:**
- 使用 concerns 组织模型复杂度
- 简洁的控制器方法
- 大量使用 before_action
- enum 定义状态

**ERB:**
- 使用 `content_for` 组织布局
- 局部视图（partials）细粒度划分
- Turbo Frame/Stream 集成

**JavaScript:**
- Stimulus 控制器保持单一职责
- 使用 outlets 连接控制器
- 模型类封装业务逻辑

---

## 第二部分：新 Playground 架构设计

### 2.1 数据模型设计

```
Setting (全局设置，键值对存储)
├── key (唯一键名)
└── value (值，支持任意类型)

User (真人用户)
├── name
├── email (可选，本地用户可为空)
├── password_digest
├── role: [member, moderator, administrator]
├── avatar
└── status: [active, inactive]

Room (聊天室 - 不使用STI，统一的Direct Room模式)
├── name, creator_id
├── status: [active, archived, deleting]（替代原有的 Rooms::Closed 概念；`archived` 软归档/只读/可逆，`deleting` 异步删除中）
├── reply_order: [natural, list, manual, pooled] (发言顺序)
├── card_handling_mode: [swap, append, append_disabled] (群组卡处理)
├── allow_self_responses, auto_mode_enabled, auto_mode_delay_ms
├── during_generation_user_input_policy: [reject, queue, restart]
├── user_turn_debounce_ms
├── settings (jsonb)
└── timestamps

Membership (用户/角色在聊天室的身份，per room)
├── room_id
├── user_id (optional，真人用户)
├── character_id (optional，AI 角色；user+character 表示"真人+persona"而不是独立 AI 角色成员)
├── llm_provider_id (optional，覆盖全局 Provider)
├── moderator (boolean，预留字段，暂不使用)
├── persona (optional，自定义 persona，如关联 character 且为空则使用 character 的值)
├── position (在聊天室中的排序位置)
├── copilot_mode: [none, full]（仅在 user_id + character_id 同时存在时有效；full 模式必须禁用/拒绝手动 user 消息；候选条数由前端请求参数 `candidate_count` 传入，1..4，默认 1，不落库）
├── copilot_remaining_steps (int, nullable；full copilot 时范围 1..10（默认 5）；成功生成消耗 1，耗尽自动关闭）
├── involvement: [invisible, nothing, mentions, everything]
├── settings (jsonb，membership 级别设置，如 LLM 参数覆写)
├── settings_version (int，JSON Patch 并发控制版本号)
└── unread_at

Character (角色，从 CharacterCard 导入后的持久化模型)
├── name, nickname, personality (常见展示/检索字段)
├── data (jsonb，V2/V3 完整数据)
├── portrait (ActiveStorage，肖像图 400x600)
├── tags, supported_languages (数组字段)
├── spec_version, file_sha256, status
└── timestamps

CharacterAsset (角色资源元数据)
├── character_id
├── blob_id (ActiveStorage blob)
├── kind (icon, emotion, background, user_icon, etc.)
├── name (unique by character_id + name)
├── ext, content_sha256
└── timestamps

Message (消息)
├── room_id
├── membership_id (发送者身份)
├── content (纯文本)
├── role: [user, assistant, system]
├── room_run_id (uuid, nullable，关联一次生成 run)
├── metadata (jsonb，LLM 参数快照 / error / generating 标记等)
└── timestamps

LLMProvider (保留现有)
├── name (显示名，唯一)
├── identification (API 格式标识：openai, openai_compatible, gemini, deepseek, anthropic, qwen, xai)
├── base_url
├── api_key (加密)
├── model
├── streamable
└── last_tested_at (最后测试时间)
```

### 2.2 路由设计

```ruby
Rails.application.routes.draw do
  # 首次运行向导
  resource :first_run, only: [:show, :create]
  
  # 认证
  resource :session, only: [:new, :create, :destroy]
  
  # 用户管理
  resources :users, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
    scope module: :users do
      resource :profile, only: [:show, :update]
      resource :avatar, only: [:update, :destroy]
    end
  end
  
  # 聊天室（核心功能）
  resources :rooms do
    resources :messages, only: [:index, :create, :show, :edit, :update, :destroy] do
      member do
        get :inline_edit
      end
      # Swipe 切换（room-scoped 确保权限控制）
      resource :swipe, only: [:create], controller: "rooms/messages/swipes"
    end
    member do
      post :regenerate  # 重新生成 AI 消息（创建新 Swipe 版本并设为活跃）
    end
    scope module: :rooms do
      resource :settings, only: [:show, :update]
      resources :memberships, only: [:index, :create, :update, :destroy]
    end
  end
  
  # 角色（公有只读）
  # - `/characters`：只读浏览/查看
  # - `/characters/:id/portrait`：肖像图
  resources :characters, only: [:index, :show] do
    member do
      get :portrait
    end
  end

  # 设置管理（需要管理员权限）
  namespace :settings do
    # 角色管理（导入/编辑/删除在 settings 下）
    # 注：目前公有 `/characters` 不承载导入/编辑/删除逻辑。
    resources :characters, except: [:new]
    resources :llm_providers do
      member do
        post :activate
        post :test
        post :fetch_models
      end
    end
  end
  
  # PWA
  get "manifest" => "pwa#manifest", as: :pwa_manifest
  get "service-worker" => "pwa#service_worker", as: :pwa_service_worker
  
  # 根路由
  root "welcome#index"
end
```

### 2.3 前端架构

保留 Bun + jsbundling 的现有架构，但采用 Campfire 的组织风格：

```
app/javascript/
├── application.js
├── controllers/
│   ├── application.js
│   ├── messages_controller.js      # 消息列表管理
│   ├── composer_controller.js      # 消息输入
│   ├── stream_controller.js        # SSE 流式响应
│   ├── sidebar_controller.js       # 侧边栏
│   ├── room_controller.js  # 聊天室管理
│   ├── auto_submit_controller.js   # 表单自动提交
│   ├── upload_preview_controller.js
│   └── ...
├── helpers/
│   ├── dom_helpers.js
│   ├── scroll_helpers.js
│   └── turbo_helpers.js
├── models/
│   ├── message_formatter.js
│   ├── scroll_manager.js
│   └── stream_handler.js
└── channels/
    └── room_channel.js
```

---

## 第三部分：实施计划

### Phase 0: 准备工作（Day 1） ✅ 已完成

#### 0.1 清理现有代码

- [x] 备份 `playground/` 到 `playground.old/`
- [x] 删除现有的 views、controllers、models（保留配置）
- [x] 保留 `LLMProvider`、`Setting` 模型和 `LLMClient` 服务
- [x] 保留 Tailwind/DaisyUI 配置

#### 0.2 添加依赖

- [x] `bcrypt` - 密码加密
- [x] `image_processing` - 图片处理
- [x] `geared_pagination` - 分页
- [x] `web-push` - PWA 推送通知（额外添加）

```ruby
# Gemfile 已添加
gem "bcrypt", "~> 3.1.7"
gem "image_processing", "~> 1.2"
gem "geared_pagination"
gem "web-push"
```

**清理后的目录结构：**
```
playground/app/
├── controllers/
│   ├── application_controller.rb
│   └── concerns/
├── javascript/controllers/
│   ├── application.js
│   ├── index.js
│   └── theme_controller.js
├── models/
│   ├── application_record.rb
│   ├── llm_provider.rb      ← 保留
│   └── setting.rb           ← 保留
├── services/
│   ├── character_loader.rb  ← 临时保留，Phase 2 后由 CharacterImport 模块替代
│   └── llm_client.rb        ← 保留
└── views/layouts/
    └── application.html.erb ← 已重置
```

---

### Phase 1: 核心框架（Day 2-3） ✅ 已完成

#### 1.1 认证系统和全局设置

**数据库迁移：**
```ruby
# 创建 settings 表 (键值对存储全局配置)
create_table :settings do |t|
  t.string :key, null: false, index: { unique: true }
  t.text :value
  t.timestamps
end

# 创建 users 表
create_table :users do |t|
  t.string :name, null: false
  t.string :email
  t.string :password_digest
  t.string :role, default: "member", null: false   # member, moderator, administrator
  t.string :status, default: "active", null: false # active, inactive
  t.timestamps
end

# 创建 sessions 表
create_table :sessions do |t|
  t.references :user, null: false, foreign_key: true
  t.string :token, null: false
  t.string :user_agent
  t.string :ip_address
  t.timestamps
end
add_index :sessions, :token, unique: true
```

**核心文件：**
- `app/models/setting.rb` - 全局配置键值对存储
- `app/models/user.rb` - 用户模型 (role 使用 string enum)
- `app/models/session.rb` - 会话模型
- `app/controllers/concerns/authentication.rb`
- `app/controllers/sessions_controller.rb`
- `app/controllers/first_runs_controller.rb`
- `app/models/first_run.rb` - 首次运行服务对象

#### 1.2 首次运行向导

参考 Campfire 的 `FirstRun` 模式：
- 检查是否已初始化 (`Setting.get("site.initialized")`)
- 创建管理员用户
- 初始化默认设置

**视图：**
- `app/views/first_runs/show.html.erb` - 向导表单
- `app/views/sessions/new.html.erb` - 登录页面

---

### Phase 2: 角色卡系统

本阶段实现角色卡的持久化存储和导入功能，支持 CCv2 (PNG/JSON) 和 CCv3 (PNG/JSON/CharX) 格式。

#### 2.1 数据模型设计

##### Character 模型

模型命名为 `Character`（而非 `CharacterCard`），更简洁直观。

```ruby
# db/migrate/xxx_create_characters.rb
create_table :characters do |t|
  # 常见展示/检索字段（从 data 中提取以提高查询性能）
  t.string :name, null: false
  t.string :nickname
  t.text :personality
  t.string :tags, array: true, default: []
  t.string :supported_languages, array: true, default: []  # CCv3 creator_notes_multilingual 的 keys
  
  # 完整 spec 数据（jsonb 存储全量有效字段，参考 TavernKit::Character::Data）
  t.jsonb :data, default: {}, null: false
  
  # 规格版本
  t.integer :spec_version, null: false  # 2 或 3
  
  # 导入去重：原始文件 SHA256，编辑后清空以允许原文件重新导入
  t.string :file_sha256, index: true
  
  # 状态管理（使用 string 枚举）
  t.string :status, default: "pending", null: false  # pending, ready, failed, deleting
  
  t.timestamps
end

add_index :characters, :name
add_index :characters, :tags, using: :gin
```

##### CharacterAsset 模型

使用 ActiveStorage 存储资源，CharacterAsset 记录资源元数据：

```ruby
# app/models/character.rb
class Character < ApplicationRecord
  # 肖像图（从 PNG 提取或 CCv3 icon with name="main"）
  # 标准尺寸：400x600 (2:3 比例)
  has_one_attached :portrait do |attachable|
    attachable.variant :standard, resize_to_limit: [400, 600]
  end
  
  # CCv3 扩展 assets 元数据（关联 ActiveStorage blob）
  has_many :character_assets, dependent: :destroy
end

# app/models/character_asset.rb
class CharacterAsset < ApplicationRecord
  belongs_to :character
  belongs_to :blob, class_name: "ActiveStorage::Blob"
  
  validates :name, uniqueness: { scope: :character_id }
  
  # kind: icon, emotion, background, user_icon, etc.
  KINDS = %w[icon emotion background user_icon other].freeze
  enum :kind, KINDS.index_by(&:itself)
  validates :kind, inclusion: { in: KINDS }
end

# db/migrate/xxx_create_character_assets.rb
create_table :character_assets do |t|
  t.references :character, null: false, foreign_key: true
  t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
  
  t.string :kind, null: false, default: "icon"  # icon, emotion, background, user_icon, etc.
  t.string :name, null: false               # asset name from spec (unique per character)
  t.string :ext                             # file extension
  t.string :content_sha256, index: true     # 用于资源复用（节约存储空间）
  
  t.timestamps
end

add_index :character_assets, [:character_id, :name], unique: true
```

##### CharacterUpload 模型

跟踪异步导入状态：

```ruby
# db/migrate/xxx_create_character_uploads.rb
create_table :character_uploads do |t|
  t.references :user, null: false, foreign_key: true
  t.references :character, foreign_key: true  # 导入成功后关联
  
  t.string :status, default: "pending", null: false  # pending, processing, completed, failed
  t.string :filename
  t.string :content_type
  t.string :error_message
  
  t.timestamps
end
```

#### 2.2 CharX 格式支持

CharX 是 CCv3 引入的 ZIP 压缩包格式，结构如下：

```
character.charx
├── card.json              # CCv3 JSON 数据（必需）
├── module.risum           # (可选) RisuAI 模块数据
└── assets/                # 嵌入资源
    ├── icon/
    │   └── image/main.png
    ├── emotion/
    │   └── image/happy.png
    └── background/
        └── image/forest.png
```

**资源 URI 规则：**
- `embeded://assets/icon/image/main.png` - 引用 ZIP 内嵌入资源
- `ccdefault:` - 引用默认图标（PNG 格式时为图片本身）
- `__asset:N` - 引用 PNG tEXt chunk 中的嵌入资源

**参考实现：**
- SillyTavern: `src/endpoints/characters.js` - `importFromCharX()`
- RisuAI: `src/ts/process/processzip.ts` - `CharXReader` 类

##### 安全加固（必须）

CharX 属于「用户可上传 ZIP」场景，默认视为不可信输入；上线前必须做安全加固：

1. **Zip bomb 防护（解压资源上限）**
   - 限制 ZIP entry 数量（例如 ≤ 512）
   - 限制单个 entry 解压后大小（例如 ≤ 25MB）
   - 限制总解压后大小（例如 ≤ 200MB）
   - 限制 `card.json` 最大大小（例如 ≤ 1MB）

2. **路径穿越防护（Path traversal）**
   - 拒绝 `../`、绝对路径、Windows 盘符、反斜杠路径
   - 只允许读取白名单路径：`card.json`、`module.risum`、`assets/**`

3. **资源白名单（MIME/扩展名/魔数）**
   - 只允许已支持的资源类型（例如 png/jpg/webp/gif/mp3/wav/ogg/mp4/webm）
   - 以魔数检测为准，扩展名仅作为辅助（避免伪造）
   - 对图片可选增加尺寸上限（防止超大分辨率造成内存压力）

4. **Data URI 限制**
   - 若支持 `data:` URI：限制 base64 解码后大小（例如 ≤ 5MB），超限直接拒绝导入

#### 2.3 导入模块架构

```
app/services/character_import/
├── base.rb              # 基础导入器接口
├── detector.rb          # 文件格式检测
├── png_importer.rb      # PNG (CCv2/CCv3) 导入
├── json_importer.rb     # JSON 导入
├── charx_importer.rb    # CharX (ZIP) 导入
├── asset_extractor.rb   # 资源提取与存储
└── deduplicator.rb      # SHA256 去重逻辑

app/jobs/
├── character_import_job.rb  # 异步导入任务
└── character_delete_job.rb  # 异步删除任务
```

##### 核心导入流程

```ruby
module CharacterImport
  class CharxImporter < Base
    def call(file_io)
      # 1. 计算文件 SHA256
      file_sha256 = Digest::SHA256.hexdigest(file_io.read)
      file_io.rewind
      
      # 2. 检查重复导入
      if (existing = Character.find_by(file_sha256: file_sha256))
        return ImportResult.duplicate(existing)
      end
      
      # 3. 解压并解析
      Zip::File.open_buffer(file_io) do |zip|
        card_json = extract_card_json(zip)
        validate_spec!(card_json)
        assets = extract_assets(zip, card_json)
        create_character(card_json, assets, file_sha256)
      end
    end
  end
end
```

##### 资源复用（SHA256 去重）

```ruby
module CharacterImport
  class AssetExtractor
    def attach_with_dedup(character, asset_data)
      # 基于 ActiveStorage checksum 或 content_sha256 检查是否已存在
      existing_blob = ActiveStorage::Blob.find_by(
        checksum: compute_checksum(asset_data[:content])
      )
      
      if existing_blob
        # 复用现有 blob，仅创建 AssetRecord 关联
        character.asset_records.create!(
          blob: existing_blob,
          asset_type: asset_data[:type],
          asset_name: asset_data[:name],
          ext: asset_data[:ext],
          content_sha256: asset_data[:content_sha256]
        )
      else
        # 创建新 blob
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(asset_data[:content]),
          filename: "#{asset_data[:name]}.#{asset_data[:ext]}",
          content_type: determine_content_type(asset_data[:ext])
        )
        character.asset_records.create!(blob: blob, ...)
      end
    end
  end
end
```

#### 2.4 异步处理

##### 导入任务

```ruby
class CharacterImportJob < ApplicationJob
  queue_as :default
  
  def perform(upload_id)
    upload = CharacterUpload.find(upload_id)
    upload.update!(status: :processing)
    
    importer = CharacterImport.for(upload.file)
    result = importer.call(upload.file)
    
    if result.success?
      upload.update!(status: :completed, character: result.character)
    else
      upload.update!(status: :failed, error_message: result.error)
    end
  rescue => e
    upload.update!(status: :failed, error_message: e.message)
    raise
  end
end
```

##### 删除任务

```ruby
class CharacterDeleteJob < ApplicationJob
  queue_as :default
  
  def perform(character_id)
    character = Character.find(character_id)
    
    # TODO: Phase 3 实现后处理关联聊天
    # - 检查是否有进行中的聊天
    # - 中断/归档关联聊天
    
    character.destroy!
  end
end
```

#### 2.5 CharactersController

```ruby
class CharactersController < ApplicationController
  def index
    @characters = Character.ready.ordered
  end
  
  def show
    @character = Character.find(params[:id])
  end
  
  def create
    upload = Current.user.character_uploads.create!(
      file: params[:file],
      filename: params[:file].original_filename,
      content_type: params[:file].content_type
    )
    
    CharacterImportJob.perform_later(upload.id)
    
    respond_to do |format|
      format.html { redirect_to characters_path, notice: "角色卡正在导入中..." }
      format.turbo_stream
    end
  end
  
  def update
    @character = Character.find(params[:id])
    
    if @character.update(character_params)
      # 编辑后清除 file_sha256，允许原文件重新导入
      @character.update!(file_sha256: nil)
      redirect_to @character
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @character = Character.find(params[:id])
    
    # TODO: Phase 3 实现后检查关联聊天
    # if @character.active_rooms.any?
    #   return redirect_to @character, alert: "存在进行中的对话，无法删除"
    # end
    
    @character.update!(status: :deleting)
    CharacterDeleteJob.perform_later(@character.id)
    
    redirect_to characters_path, notice: "角色卡正在删除中..."
  end
end
```

#### 2.6 权限说明

用户权限通过 role 字段区分：

```ruby
# app/models/user.rb
class User < ApplicationRecord
  ROLES = %w[member moderator administrator].freeze
  
  enum :role, ROLES.index_by(&:itself), default: "member"
  
  validates :role, inclusion: { in: ROLES }
  
  def can_administer?
    administrator?
  end
  
  def can_moderate?
    administrator? || moderator?
  end
end
```

**权限说明：**
- `administrator` - 可以管理（CRUD）人物卡、Presets、Lorebooks 等资源
- `moderator` - 可以管理对话、消息等（未来扩展）
- `member` - 普通用户

**注意：** 用户与角色卡的关联是 **per room** 的，在 Membership 模型中实现（见 Phase 3）。
用户可以在不同的聊天室使用不同的角色卡身份。

#### 2.7 测试策略

**测试范围：**
- ✅ `app/services/` - 需要完整测试覆盖
- ✅ `lib/` - 需要完整测试覆盖
- ✅ `app/jobs/` - 需要测试覆盖
- ❌ `app/controllers/` - 暂不做自动化测试（变更频繁）
- ❌ 前端/视图 - 暂不做自动化测试

**测试数据处理：**

`playground/resources/` 目录下的测试数据（characters、presets、lorebooks）有版权，不能加入代码仓库。
测试策略：
1. 在测试中动态生成最小可用的测试数据（使用 TavernKit 构造）
2. 使用 `test/fixtures/` 存放自制的无版权测试数据
3. 集成测试可以 skip 如果真实测试数据不存在

```ruby
# test/test_helper.rb
def self.real_test_data_available?
  File.exist?(Rails.root.join("resources/characters"))
end

# test/services/character_import/png_importer_test.rb
class PngImporterTest < ActiveSupport::TestCase
  # 使用自制测试数据
  test "imports minimal v2 card" do
    # 使用 TavernKit 动态生成测试 PNG
    png_data = build_test_png(name: "Test", description: "Test description")
    result = CharacterImport::PngImporter.call(png_data)
    assert result.success?
  end
  
  # 使用真实测试数据（可选）
  test "imports real v3 card with assets", skip: !real_test_data_available? do
    path = Rails.root.join("resources/characters/example.png")
    result = CharacterImport::PngImporter.call(File.read(path))
    assert result.success?
  end
end
```

**测试目录结构：**
```
test/
├── services/
│   └── character_import/
│       ├── detector_test.rb
│       ├── png_importer_test.rb
│       ├── json_importer_test.rb
│       ├── charx_importer_test.rb
│       ├── asset_extractor_test.rb
│       └── deduplicator_test.rb
├── jobs/
│   ├── character_import_job_test.rb
│   └── character_delete_job_test.rb
└── fixtures/
    └── files/
        ├── minimal_v2.json      # 自制最小 V2 数据
        └── minimal_v3.json      # 自制最小 V3 数据
```

#### 2.8 待后续阶段完善

1. **删除关联对话处理** - 需 Phase 3 对话系统完成后实现
2. **AI 用户自动聊天** - 需 Phase 3 + Phase 4 完成后实现
3. **角色卡导出** - 可选功能，按需实现

#### 2.9 产出文件清单

**迁移：**
- `db/migrate/xxx_create_characters.rb`
- `db/migrate/xxx_create_character_assets.rb`
- `db/migrate/xxx_create_character_uploads.rb`

**模型：**
- `app/models/character.rb`
- `app/models/character_asset.rb`
- `app/models/character_upload.rb`

**服务：**
- `app/services/character_import/base.rb`
- `app/services/character_import/detector.rb`
- `app/services/character_import/png_importer.rb`
- `app/services/character_import/json_importer.rb`
- `app/services/character_import/charx_importer.rb`
- `app/services/character_import/asset_extractor.rb`
- `app/services/character_import/deduplicator.rb`

**任务：**
- `app/jobs/character_import_job.rb`
- `app/jobs/character_delete_job.rb`

**控制器/视图：**
- `app/controllers/characters_controller.rb`
- `app/views/characters/index.html.erb`
- `app/views/characters/show.html.erb`
- `app/views/characters/_character.html.erb`
- `app/views/characters/_upload_status.html.erb`

---

### Phase 3: 聊天室系统

实现多用户/多角色聊天室。

**架构简化说明（2024-12-29更新）：**
- 不使用 STI，统一为 Direct Room 模式（创建者邀请 Character 或真人进入）
- Room 增加 `status` 字段替代原有的 Rooms::Closed 概念（`active/archived/deleting`）：
  - `archived`：**软归档/可逆/只读**，禁止发送/编辑/删除消息、修改成员/设置、触发 LLM 生成
  - `deleting`：**异步删除中/只读**，进入删除队列后后台分批删除 messages/memberships，最终删除 room
- Membership 增加 `moderator` 字段（预留，暂不使用）
- Message 使用 `content` 纯文本字段，不使用 ActionText

#### 3.1 数据模型

```ruby
# 创建 rooms 表（不使用STI，统一的Direct Room模式）
create_table :rooms do |t|
  t.string :name, null: false
  t.references :creator, null: false, foreign_key: { to_table: :users }
  t.jsonb :settings, default: {}, null: false
  t.integer :settings_version, null: false, default: 0
  
  # SillyTavern group chat 设置
  t.string :activation_strategy, default: "natural", null: false
  t.string :generation_mode, default: "swap", null: false
  t.boolean :allow_self_responses, default: false
  t.integer :auto_mode_delay, default: 5

  # active/archived/deleting（archived 软归档；deleting 异步删除中）
  t.string :status, null: false, default: "active"
  
  t.timestamps
end

# 创建 memberships 表（用户/角色在聊天室的身份）
create_table :memberships do |t|
  t.references :room, null: false, foreign_key: true
  t.references :user, foreign_key: true
  t.references :character, foreign_key: true
  t.references :llm_provider, foreign_key: true
  t.boolean :moderator, null: false, default: false  # 预留字段
  
  t.text :persona
  t.integer :position, null: false, default: 0
  t.string :copilot_mode, null: false, default: "none"
  t.string :involvement, default: "everything", null: false
  t.jsonb :settings, null: false, default: {}
  t.integer :settings_version, null: false, default: 0
  t.datetime :unread_at
  
  t.timestamps
end
add_index :memberships, [:room_id, :user_id], unique: true, where: "user_id IS NOT NULL"
add_index :memberships, [:room_id, :character_id], unique: true, where: "character_id IS NOT NULL"

# 创建 messages 表（纯文本 + metadata；生成运行态见 room_runs）
create_table :messages do |t|
  t.references :room, null: false, index: true, foreign_key: true
  t.references :membership, null: false, foreign_key: true
  t.string :role, default: "user", null: false

  t.text :content  # 纯文本存储
  t.jsonb :metadata, default: {}, null: false
  
  t.timestamps
end
```

**枚举值说明（参考 SillyTavern）：**

**Room.activation_strategy** - 决定哪个 AI 角色被激活发言：
| 值 | 说明 |
|---|---|
| `natural` | 自然顺序 - 基于对话上下文智能选择下一个发言者 |
| `list` | 列表顺序 - 按 membership.position 顺序轮流发言 |
| `manual` | 手动选择 - 用户手动指定下一个发言者 |
| `pooled` | 池化顺序 - 从可用成员池中选择（排除刚发言的） |

**Room.generation_mode** - 决定如何生成 AI 回复：
| 值 | 说明 |
|---|---|
| `sequential` | 顺序模式 - AI 角色按顺序逐个响应（目前唯一支持的模式） |

**Membership.involvement** - 通知参与级别：
| 值 | 说明 |
|---|---|
| `invisible` | 隐藏 - 不显示在成员列表中 |
| `nothing` | 无通知 - 不接收任何通知 |
| `mentions` | 仅提及 - 只在被 @ 时通知 |
| `everything` | 全部 - 接收所有消息通知 |

**Message.role** - 消息角色（OpenAI 格式）：
| 值 | 说明 |
|---|---|
| `user` | 用户消息 |
| `assistant` | AI 助手回复 |
| `system` | 系统消息 |

**实现注意事项：**
- “移除成员”的语义应当是将 `Membership.involvement` 设为 `invisible`（保持聊天记录）；避免直接 destroy membership（会触发 `dependent: :delete_all` 删除消息）
- “删除房间”的语义应当是将 `Room.status` 设为 `deleting` 并 enqueue `RoomDeleteJob` 分批清理 messages/memberships，避免单条 `DELETE` 造成锁/超时

#### 3.2 模型定义

```ruby
# app/models/room.rb
class Room < ApplicationRecord
  STATUSES = %w[active archived deleting].freeze
  ACTIVATION_STRATEGIES = %w[natural list manual pooled].freeze
  GENERATION_MODES = %w[sequential].freeze  # 目前仅支持 sequential
  
  has_many :memberships, dependent: :delete_all do
    def grant_to(participants, **options)
      # ... 授予成员资格
    end
    def revoke_from(participants)
      # ... 撤销成员资格
    end
  end
  
  has_many :users, through: :memberships
  has_many :characters, through: :memberships
  has_many :messages, dependent: :delete_all
  belongs_to :creator, class_name: "User"
  
  enum :activation_strategy, ACTIVATION_STRATEGIES.index_by(&:itself), default: "natural"
  enum :generation_mode, GENERATION_MODES.index_by(&:itself), default: "swap"
  
  validates :name, presence: { message: "must contain visible characters" }
  validates :status, presence: true, inclusion: { in: STATUSES }
  normalizes :name, with: ->(value) { value&.strip.presence }
  
  scope :ordered, -> { order("LOWER(name)") }
  scope :active, -> { where(status: "active") }
  scope :archived, -> { where(status: "archived") }
  scope :deleting, -> { where(status: "deleting") }
  
  def archive!
    update!(status: "archived")
  end
  
  def unarchive!
    update!(status: "active")
  end

  def mark_deleting!
    update!(status: "deleting")
  end
end

# app/models/membership.rb
class Membership < ApplicationRecord
  INVOLVEMENTS = %w[invisible nothing mentions everything].freeze
  COPILOT_MODES = %w[none full].freeze
  
  belongs_to :room
  belongs_to :user, optional: true
  belongs_to :character, optional: true
  belongs_to :llm_provider, class_name: "LLMProvider", optional: true
  has_many :messages, dependent: :delete_all
  
  enum :involvement, INVOLVEMENTS.index_by(&:itself), prefix: :involved_in
  enum :copilot_mode, COPILOT_MODES.index_by(&:itself), default: "none", prefix: :copilot
  
  scope :visible, -> { where.not(involvement: "invisible") }
  scope :unread, -> { where.not(unread_at: nil) }
  scope :by_position, -> { order(:position) }
  scope :copilot_enabled, -> { where.not(copilot_mode: "none") }
  scope :moderators, -> { where(moderator: true) }  # 预留
  
  def display_name
    character&.name || user&.name || "[Deleted]"
  end
  
  def moderator?
    moderator
  end
end

# app/models/message.rb
class Message < ApplicationRecord
  include Broadcasts
  
  ROLES = %w[user assistant system].freeze
  
  belongs_to :room, touch: true
  belongs_to :membership
  belongs_to :room_run, optional: true
  
  normalizes :content, with: ->(value) { value&.strip }
  
  enum :role, ROLES.index_by(&:itself), default: "user"
  
  validates :role, inclusion: { in: ROLES }
  validates :content, presence: true, unless: -> { assistant? || generating? }
  
  delegate :display_name, to: :membership, prefix: :sender
  
  # Run-driven generation state（详见 docs/CONVERSATION_AUTO_RESPONSE.md）
  def generating?
    room_run&.running? == true
  end
  
  def errored?
    room_run&.failed? == true || metadata&.dig("error").present?
  end
end
```

#### 3.3 实时通信

```ruby
# app/channels/room_channel.rb
class RoomChannel < ApplicationCable::Channel
  def subscribed
    if @room = find_room
      stream_for @room
    else
      reject
    end
  end
  
  private
  
  def find_room
    current_user.rooms.find_by(id: params[:room_id])
  end
end
```

#### 3.4 消息广播

```ruby
# app/models/message/broadcasts.rb
module Message::Broadcasts
  extend ActiveSupport::Concern
  
  included do
    after_create_commit :broadcast_create
    after_destroy_commit :broadcast_remove
  end
  
  def broadcast_create
    broadcast_append_to room, :messages, 
      target: dom_id(room, :messages),
      partial: "messages/message"
  end
  
  def broadcast_remove
    broadcast_remove_to room, :messages
  end
end
```

---

### Phase 4: LLM 集成（Day 9-11）

#### 4.1 保留现有 LLM 基础设施

- `LLMProvider` 模型
- `LLMClient` 服务
- `Setting` 模型

#### 4.2 聊天完成流程（Run-driven）

自动回复的执行单元为 `room_runs`：

- Planner：`Room::RunPlanner` 写入/覆盖 queued run，并调度 `RoomRunJob`（支持 `ActiveJob.set(wait_until:)` 延迟执行）
- Executor：`Room::RunExecutor` 负责 claim → LLM streaming（内容发送到 typing indicator）→ 原子创建 message → follow-up
- 详细行为/并发约束：见 `docs/CONVERSATION_AUTO_RESPONSE.md`

#### 4.3 提示词构建器

集成 TavernKit，支持多角色聊天室：

```ruby
# app/services/prompt_builder.rb
class PromptBuilder
  def initialize(room, user_message: nil, speaker: nil, preset: nil, greeting_index: nil)
    @room = room
    @user_message = user_message
    @speaker = speaker || room.next_speaker
    @preset = preset
    @greeting_index = greeting_index
  end

  def to_messages(dialect: :openai)
    plan = TavernKit.build(
      character: @speaker.to_participant,
      user: user_participant,
      preset: @preset || TavernKit::Preset.new,
      history: ActiveRecordChatHistory.new(@room.messages.ordered.with_membership),
      message: @user_message,
      group: group_context,
      greeting_index: @greeting_index
    )

    plan.to_messages(dialect: dialect)
  end

  private

  # 选择一个真人 membership 作为 user（优先非 copilot_full）
  def user_participant
    user_membership =
      @room.memberships.find { |m| m.user? && !m.copilot_full? } ||
      @room.memberships.find(&:user?)

    user_membership ? user_membership.to_user_participant : TavernKit::User.new(name: "User", persona: nil)
  end

  def group_context
    return nil unless @room.group?

    character_memberships = @room.character_memberships.by_position
    member_names = character_memberships.map(&:display_name)

    TavernKit::GroupContext.new(members: member_names, current_character: @speaker.display_name)
  end
end
```

---

### Phase 5: UI 实现（Day 12-15）

#### 5.1 布局结构

采用 Campfire 的三栏布局：

```erb
<%# app/views/layouts/application.html.erb %>
<!DOCTYPE html>
<html data-theme="<%= current_theme %>">
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <%= csrf_meta_tags %>
  <%= action_cable_meta_tag %>
  <%= stylesheet_link_tag "application", data: { turbo_track: "reload" } %>
  <%= javascript_include_tag "application", defer: true, data: { turbo_track: "reload" } %>
  <%= yield :head %>
</head>
<body class="<%= yield :body_class %>">
  <a href="#main-content" class="skip-link">Skip to main content</a>
  
  <nav>
    <%= yield :nav %>
  </nav>
  
  <%= render "shared/flash" %>
  
  <main id="main-content">
    <%= yield %>
  </main>
  
  <aside>
    <%= yield :sidebar %>
  </aside>
  
  <%= turbo_stream_from current_user if current_user %>
</body>
</html>
```

#### 5.2 聊天室列表

```erb
<%# app/views/rooms/index.html.erb %>
<div class="rooms-list" data-controller="rooms">
  <%= render @rooms %>
  
  <%= link_to new_room_path, class: "btn btn-primary" do %>
    <span>新建聊天室</span>
  <% end %>
</div>
```

#### 5.3 聊天界面

```erb
<%# app/views/rooms/show.html.erb %>
<% content_for :nav do %>
  <h1><%= @room.name %></h1>
  <%= link_to room_settings_path(@room), class: "btn btn-ghost btn-sm" do %>
    设置
  <% end %>
<% end %>

<div class="chat-container" data-controller="messages">
  <div class="messages" data-messages-target="list">
    <%= render @messages %>
  </div>
  
  <%= turbo_stream_from @room, :messages %>
  
  <div class="composer" data-controller="composer">
    <%= render "messages/composer", room: @room %>
  </div>
</div>

<% content_for :sidebar do %>
  <%= render "rooms/sidebar", room: @room %>
<% end %>
```

#### 5.4 消息组件

```erb
<%# app/views/messages/_message.html.erb %>
<article id="<%= dom_id(message) %>" 
         class="message message--<%= message.role %> <%= 'message--character' if message.membership.character? %>"
         data-message-id="<%= message.id %>">
  <figure class="avatar">
    <%= avatar_tag message.membership %>
  </figure>
  
  <div class="message__body">
    <header class="message__meta">
      <strong><%= message.sender_display_name %></strong>
      <time datetime="<%= message.created_at.iso8601 %>">
        <%= message.created_at.strftime("%H:%M") %>
      </time>
    </header>
    
    <div class="message__content">
      <%= message.text %>
    </div>
    
    <% if message.assistant? %>
      <footer class="message__actions">
        <%= button_to regenerate_room_path(@room), 
            method: :post, class: "btn btn-ghost btn-xs" do %>
          重新生成
        <% end %>
      </footer>
    <% end %>
  </div>
</article>
```

---

### Phase 6: 高级功能（Day 16-19）

#### 6.1 Copilot（真人绑定角色卡）

允许真人用户绑定一个 persona Character，并通过 `copilot_mode` 控制「手动/全自动」发言：
- `none`：默认，真人手动发送消息；可使用 "Generate Suggestions" 生成候选回复（候选条数由前端请求参数 `candidate_count` 传入，1..4，默认 1，不落库）
- `full`：全自动，自动回复；**必须禁用/拒绝** 手动发送 `role=user` 消息（避免同一身份同时“真人发言 + 自动发言”导致边界混乱）

```ruby
# Membership 模型（字段语义）
# - copilot_mode 仅在 user_id + character_id 同时存在时有意义
class Membership < ApplicationRecord
  COPILOT_MODES = %w[none full].freeze
  enum :copilot_mode, COPILOT_MODES.index_by(&:itself), default: "none", prefix: :copilot
end

# full 模式下禁用手动 user 消息（后端拒绝）
# app/controllers/messages_controller.rb
return head :forbidden if @message.user_message? && @membership.copilot_full?
```

#### 6.2 群组聊天室

支持多个角色（AI 和真人）在同一聊天室中：

```ruby
class Room < ApplicationRecord
  # 获取所有 AI 角色成员
  def character_memberships
    memberships.visible.where.not(character: nil)
  end
  
  # 是否为群组聊天
  def group?
    memberships.visible.count > 2
  end
  
  # 基于 activation_strategy 选择下一个发言者
  def next_speaker(last_membership = nil)
    candidates = character_memberships.by_position.to_a
    return nil if candidates.empty?
    
    case activation_strategy
    when "natural"
      # TODO: 基于上下文智能选择
      candidates.first
    when "list"
      # 轮流发言
      if last_membership
        idx = candidates.index(last_membership)
        candidates[(idx + 1) % candidates.size]
      else
        candidates.first
      end
    when "pooled"
      # 从可用成员池中随机选择
      candidates.sample
    end
  end
end
```

#### 6.3 调试面板

保留 LLM Playground 特性：

- Token 计数显示
- 提示词预览
- 生成参数调整
- 实时日志

---

### Phase 7: PWA 支持（Day 20）

#### 7.1 Web App Manifest

```erb
<%# app/views/pwa/manifest.json.erb %>
{
  "name": "<%= Setting.get('site.name', 'Playground') %>",
  "short_name": "Playground",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#570df8",
  "icons": [
    {
      "src": "<%= asset_path('icon-192.png') %>",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "<%= asset_path('icon-512.png') %>",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
```

#### 7.2 Service Worker

基础的缓存和推送通知支持。

---

## 第四部分：文件清单

> 注：本节反映当前实际文件结构（最后同步：2026-01-01）。  
> 清单口径：以 `playground/` 为根的 Rails app（下方省略 `playground/` 前缀）。

### 核心文件结构

```
app/
├── channels/
│   ├── application_cable/
│   │   ├── channel.rb
│   │   └── connection.rb
│   ├── copilot_channel.rb
│   └── room_channel.rb          # 统一处理 typing/streaming JSON 事件
├── controllers/
│   ├── concerns/
│   │   ├── authentication.rb
│   │   ├── authorization.rb
│   │   └── room_scoped.rb
│   ├── schemas/
│   │   └── settings_controller.rb    # GET /schemas/settings
│   ├── settings/
│   │   ├── application_controller.rb
│   │   ├── characters_controller.rb
│   │   └── llm_providers_controller.rb
│   ├── rooms/
│   │   ├── application_controller.rb
│   │   ├── copilot_candidates_controller.rb
│   │   ├── memberships_controller.rb
│   │   └── settings_controller.rb
│   ├── application_controller.rb
│   ├── characters_controller.rb
│   ├── first_runs_controller.rb
│   ├── messages_controller.rb
│   ├── rooms_controller.rb
│   ├── sessions_controller.rb
│   └── welcome_controller.rb
├── helpers/
│   ├── application_helper.rb
│   ├── message_helper.rb
│   └── portrait_helper.rb
├── javascript/
│   ├── application.js
│   └── controllers/               # 详见 5.E 节
│       ├── application.js
│       ├── auto_submit_controller.js
│       ├── auto_swipe_controller.js      # Auto-swipe（内容规则自动 regenerate）
│       ├── chat_hotkeys_controller.js    # 聊天热键（Swipe/Regenerate/Edit/Cancel）
│       ├── chat_scroll_controller.js     # 滚动加载历史消息
│       ├── copilot_controller.js         # Copilot 候选回复生成、候选快捷键（1-4/Esc）
│       ├── dropzone_controller.js
│       ├── llm_settings_controller.js    # LLM Provider 管理（测试连接、获取模型）
│       ├── markdown_controller.js
│       ├── message_actions_controller.js
│       ├── message_form_controller.js
│       ├── range_display_controller.js
│       ├── schema_renderer_controller.js
│       ├── segmented_controller.js
│       ├── settings_form_controller.js
│       ├── sidebar_controller.js
│       ├── tabs_controller.js
│       ├── tags_input_controller.js
│       ├── room_channel_controller.js       # 统一订阅 RoomChannel（typing/streaming）
│       ├── theme_controller.js
│       ├── toast_controller.js
│       └── typing_indicator_controller.js   # 显示 typing 状态和 streaming 内容
├── jobs/
│   ├── character_delete_job.rb
│   ├── character_import_job.rb
│   ├── copilot_candidate_job.rb
│   ├── room_delete_job.rb
│   └── room_run_job.rb            # Run 驱动调度入口（替代 chat_completion_job）
├── models/
│   ├── character.rb
│   ├── character_asset.rb
│   ├── character_upload.rb
│   ├── first_run.rb
│   ├── llm_provider.rb
│   ├── membership.rb
│   ├── membership/
│   │   └── settings_patch.rb
│   ├── message.rb
│   ├── message/
│   │   └── broadcasts.rb
│   ├── room.rb
│   ├── room/
│   │   └── copilot_candidate_generator.rb
│   ├── room_run.rb                # Run 状态机模型
│   ├── session.rb
│   ├── setting.rb
│   └── user.rb
├── services/
│   ├── character_export/          # Phase 2 导出模块
│   ├── character_import/          # Phase 2 导入模块
│   ├── llm_client.rb
│   ├── prompt_builder.rb
│   ├── room/                      # Run 驱动调度器
│   │   ├── run_planner.rb         # 计划 queued run（debounce/policy/copilot）
│   │   └── run_executor.rb        # 执行 run（claim/stream/cancel/followup）
│   ├── settings_schema_pack.rb    # Schema pack 入口
│   ├── settings_schemas/          # Schema pack 核心
│   │   ├── bundler.rb
│   │   ├── extensions.rb
│   │   ├── field_enumerator.rb
│   │   ├── loader.rb
│   └── speaker_selector.rb        # Speaker 选择逻辑
│       ├── manifest.rb
│       ├── ref_resolver.rb
│       └── storage_applier.rb
├── settings_schemas/              # Settings Schema Pack 文件
│   ├── manifest.json
│   ├── root.schema.json
│   ├── defs/
│   │   ├── character.schema.json
│   │   ├── llm.schema.json
│   │   ├── membership.schema.json
│   │   ├── preset.schema.json
│   │   ├── resources.schema.json
│   │   └── room.schema.json
│   └── providers/
│       ├── base.schema.json
│       ├── anthropic.schema.json
│       ├── deepseek.schema.json
│       ├── gemini.schema.json
│       ├── openai.schema.json
│       ├── openai_compatible.schema.json
│       ├── qwen.schema.json
│       └── xai.schema.json
└── views/
    ├── characters/
    ├── first_runs/
    ├── layouts/
    │   ├── application.html.erb
    │   └── chat.html.erb
    ├── messages/
    │   ├── _form.html.erb
    │   ├── _message.html.erb
    │   └── _typing_indicator.html.erb
    ├── rooms/
    │   ├── _form.html.erb
    │   ├── _left_sidebar.html.erb
    │   ├── _right_sidebar.html.erb
    │   └── sidebar/
    ├── sessions/
    ├── settings/
    │   ├── characters/
    │   ├── fields/                # 通用设置字段 partials
    │   │   ├── _number.html.erb
    │   │   ├── _range.html.erb
    │   │   ├── _segmented.html.erb
    │   │   ├── _select.html.erb
    │   │   ├── _slider.html.erb
    │   │   ├── _tags.html.erb
    │   │   ├── _text.html.erb
    │   │   ├── _textarea.html.erb
    │   │   └── _toggle.html.erb
    │   └── llm_providers/
    ├── shared/
    └── welcome/

db/migrate/
├── 20251229021549_create_users.rb
├── 20251229021550_create_sessions.rb
├── 20251229021551_create_settings.rb
├── 20251229021552_create_characters.rb
├── 20251229021553_create_character_assets.rb
├── 20251229021554_create_character_uploads.rb
├── 20251229021555_create_llm_providers.rb
├── 20251230000001_create_rooms.rb
├── 20251230000002_create_memberships.rb
├── 20251230000003_create_messages.rb
└── 20251231000001_add_settings_version_to_rooms.rb
```

### 与原计划差异说明

| 原计划项 | 实际状态 | 说明 |
|---------|---------|------|
| `app/javascript/helpers/` | 未创建 | 功能已整合到 Stimulus 控制器 |
| `app/javascript/models/` | 未创建 | 功能已整合到 Stimulus 控制器 |
| `app/javascript/channels/` | 已删除 | 功能已整合到 Stimulus 控制器（ActionCable 订阅） |
| `app/controllers/users/` | 未创建 | 用户管理 UI 尚未实现 |
| `app/controllers/pwa_controller.rb` | 未创建 | Phase 7 PWA 待实现 |
| `app/views/pwa/` | 未创建 | Phase 7 PWA 待实现 |
| `app/helpers/avatar_helper.rb` | 未创建 | 功能整合到 `portrait_helper.rb` |
| `app/helpers/markdown_helper.rb` | 未创建 | Markdown 渲染由 Stimulus 控制器处理 |
| `app/controllers/schemas/` | 新增 | Settings Schema Pack endpoint |
| `app/services/settings_schemas/` | 新增 | Schema pack 核心服务 |
| `app/settings_schemas/` | 新增 | Schema pack 文件目录 |
| `app/channels/room_channel.rb` | 新增 | 统一的实时通信频道（typing、streaming、message 事件） |
| `app/models/room/*.rb` | 新增 | Room 相关服务对象（CopilotCandidateGenerator） |
| `app/models/message_swipe.rb` | 新增 | MessageSwipe 模型（Swipes 版本管理） |
| `app/controllers/rooms/messages/swipes_controller.rb` | 新增 | Swipe 切换控制器（room-scoped，确保权限控制） |
| `app/javascript/controllers/chat_hotkeys_controller.js` | 新增 | 聊天热键控制器（ArrowLeft/Right 切换 Swipe、Ctrl+Enter 再生成、Up/Ctrl+Up 编辑消息、Esc 取消编辑） |
| `app/models/room_run.rb` | 新增 | Run 状态机模型 |
| `app/services/room/run_planner.rb` | 新增 | Run 驱动调度：计划 queued run |
| `app/services/room/run_executor.rb` | 新增 | Run 驱动调度：执行 run（claim/stream/cancel/followup） |
| `app/services/speaker_selector.rb` | 新增 | Speaker 选择逻辑 |
| `app/jobs/room_run_job.rb` | 新增 | Run 执行入口（调用 RunExecutor） |
| `app/controllers/rooms/copilot_candidates_controller.rb` | 新增 | Copilot 候选回复 API |
| `messages.content` (renamed from `text`) | 重命名 | 消息内容字段 |
| `memberships.copilot_remaining_steps` 字段 | 新增 | Full Copilot 剩余步数（范围 1..10；默认 5；成功消耗；耗尽自动关闭并广播 reason） |
| `room_runs` 表 | 新增 | Run 驱动调度：存储执行状态机（queued/running/succeeded/failed/canceled/skipped） |

---

## 第五部分：时间估算

| Phase | 任务 | 预估时间 |
|-------|------|----------|
| 0 | 准备工作 | 1 天 |
| 1 | 核心框架 (Setting, Auth) | 2 天 |
| 2 | 角色卡系统 | 2 天 |
| 3 | 对话系统 | 3 天 |
| 4 | LLM 集成 | 3 天 |
| 5 | UI 实现 | 4 天 |
| 6 | 高级功能 | 4 天 |
| 7 | PWA 支持 | 1 天 |
| - | **总计** | **20 天** |

---

## 第六部分：风险与注意事项

### 技术风险

1. **ActionCable 性能** - 现有 Falcon + Async::Cable 配置可能需要调整
2. **数据迁移** - 角色卡从文件系统迁移到数据库需要仔细处理
3. **TavernKit 集成** - 确保与新架构兼容

### 设计注意

1. **保持简洁** - 不要过度设计，优先实现核心功能
2. **渐进增强** - 基础功能先行，高级功能后续添加
3. **代码风格** - 严格遵循 Campfire 的代码风格和组织方式

### 兼容性

1. **保留 LLM Provider 配置** - 现有用户配置不丢失
2. **角色卡向后兼容** - 支持文件系统和数据库两种模式（过渡期）

---

## 附录：Campfire 代码风格参考

### Ruby 代码风格

```ruby
# 控制器 - 简洁、专注
class MessagesController < ApplicationController
  before_action :set_room
  before_action :set_message, only: [:show, :edit, :update, :destroy]
  
  def create
    @message = @room.messages.create!(message_params.merge(creator: Current.user))
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @room }
    end
  end
  
  private
  
  def set_room
    @room = Current.user.rooms.find(params[:room_id])
  end
  
  def message_params
    params.require(:message).permit(:body)
  end
end
```

### ERB 风格

```erb
<%# 使用 content_for 组织 %>
<% content_for :nav do %>
  <%= link_back_to rooms_path %>
<% end %>

<%# 简洁的条件渲染 %>
<%= render @messages if @messages.any? %>

<%# 使用 dom_id 生成唯一 ID %>
<article id="<%= dom_id(message) %>">
```

### Stimulus 控制器风格

```javascript
// 单一职责，清晰的生命周期
export default class extends Controller {
  static targets = ["list", "item"]
  static values = { url: String }
  
  connect() {
    this.scrollToBottom()
  }
  
  append(event) {
    this.listTarget.insertAdjacentHTML("beforeend", event.detail.html)
    this.scrollToBottom()
  }
  
  scrollToBottom() {
    this.listTarget.scrollTop = this.listTarget.scrollHeight
  }
}
```

---

## 结论

本方案详细描述了将 Playground 按照 Campfire 风格重写的完整计划。通过学习和采用 Campfire 的最佳实践，我们将构建一个更加现代、简洁、功能完善的 LLM Playground 应用。

重写后的 Playground 将具备：
- 完整的用户系统和认证
- 多对话管理
- AI 用户和真实用户的灵活交互
- 实时流式响应
- PWA 支持
- 保留完整的 LLM 调试能力

建议按 Phase 顺序逐步实施，每个 Phase 完成后进行测试和代码审查。

---

## 第七部分：任务清单

以下是各阶段的详细任务分解，用于追踪开发进度。

**状态标记：** ⬜ 待开始 | 🔄 进行中 | ✅ 已完成 | ⏸️ 暂停 | ❌ 取消

---

### Phase 2: 角色卡系统

#### 2.A 数据模型与迁移

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 2.A.1 | 创建 Character 模型和迁移 | `db/migrate/xxx_create_characters.rb`, `app/models/character.rb` | - | ✅ |
| 2.A.2 | 创建 CharacterAsset 模型和迁移 | `db/migrate/xxx_create_character_assets.rb`, `app/models/character_asset.rb` | 2.A.1 | ✅ |
| 2.A.3 | 创建 CharacterUpload 模型和迁移 | `db/migrate/xxx_create_character_uploads.rb`, `app/models/character_upload.rb` | 2.A.1 | ✅ |
| 2.A.4 | 配置 Character 的 ActiveStorage portrait | `app/models/character.rb` | 2.A.1 | ✅ |

#### 2.B 导入服务模块

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 2.B.1 | 实现 CharacterImport::Base 基类 | `app/services/character_import/base.rb` | 2.A.1 | ✅ |
| 2.B.2 | 实现 CharacterImport::Detector 格式检测 | `app/services/character_import/detector.rb` | 2.B.1 | ✅ |
| 2.B.3 | 实现 CharacterImport::JsonImporter | `app/services/character_import/json_importer.rb` | 2.B.1 | ✅ |
| 2.B.4 | 实现 CharacterImport::PngImporter | `app/services/character_import/png_importer.rb` | 2.B.3 | ✅ |
| 2.B.5 | 实现 CharacterImport::CharxImporter | `app/services/character_import/charx_importer.rb` | 2.B.3 | ✅ |
| 2.B.6 | 实现 CharacterImport::AssetExtractor | `app/services/character_import/asset_extractor.rb` | 2.A.2, 2.B.1 | ✅ |
| 2.B.7 | 实现 CharacterImport::Deduplicator | `app/services/character_import/deduplicator.rb` | 2.B.1 | ✅ |

#### 2.B+ 导出服务模块（新增）

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 2.B+.1 | 实现 CharacterExport::Base 基类 | `app/services/character_export/base.rb` | 2.A.1 | ✅ |
| 2.B+.2 | 实现 CharacterExport::JsonExporter | `app/services/character_export/json_exporter.rb` | 2.B+.1 | ✅ |
| 2.B+.3 | 实现 CharacterExport::PngExporter | `app/services/character_export/png_exporter.rb` | 2.B+.1 | ✅ |
| 2.B+.4 | 实现 CharacterExport::CharxExporter | `app/services/character_export/charx_exporter.rb` | 2.B+.1 | ✅ |

#### 2.C 异步任务

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 2.C.1 | 实现 CharacterImportJob | `app/jobs/character_import_job.rb` | 2.B.2 | ✅ |
| 2.C.2 | 实现 CharacterDeleteJob | `app/jobs/character_delete_job.rb` | 2.A.1 | ✅ |

#### 2.D 控制器与视图

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 2.D.1 | 实现公有 CharactersController（只读：index/show/portrait） | `app/controllers/characters_controller.rb` | 2.A.1 | ✅ |
| 2.D.2 | 实现 Settings::CharactersController（管理：上传导入/编辑/删除） | `app/controllers/settings/characters_controller.rb` | 2.C.1 | ✅ |
| 2.D.3 | 创建公有角色视图（只读） | `app/views/characters/index.html.erb`, `_character.html.erb`, `show.html.erb` | 2.D.1 | ✅ |
| 2.D.4 | 创建 Settings 角色管理视图（含上传入口） | `app/views/settings/characters/index.html.erb`, `_character.html.erb`, `show.html.erb` | 2.D.2 | ✅ |
| 2.D.5 | 实现 portrait 路由 | `app/controllers/characters_controller.rb` | 2.D.1 | ✅ |
| 2.D.6 | 实现上传拖拽组件（Dropzone） | `app/javascript/controllers/dropzone_controller.js` | 2.D.4 | ✅ |
| 2.D.7 | 添加路由配置（`/characters` 只读；`/settings/characters` 管理） | `config/routes.rb` | 2.D.1 | ✅ |

#### 2.E 测试

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 2.E.1 | 创建测试 fixtures（V2/V3 JSON、PNG、CharX） | `test/fixtures/files/characters/` | - | ✅ |
| 2.E.2 | 测试 Detector 服务 | `test/services/character_import/detector_test.rb` | 2.B.2, 2.E.1 | ✅ |
| 2.E.3 | 测试 JsonImporter 服务 | `test/services/character_import/json_importer_test.rb` | 2.B.3, 2.E.1 | ✅ |
| 2.E.4 | 测试 PngImporter 服务 | `test/services/character_import/png_importer_test.rb` | 2.B.4 | ✅ |
| 2.E.5 | 测试 CharxImporter 服务 | `test/services/character_import/charx_importer_test.rb` | 2.B.5 | ✅ |
| 2.E.6 | 测试 AssetExtractor 服务 | `test/services/character_import/asset_extractor_test.rb` | 2.B.6 | ✅ |
| 2.E.7 | 测试 Deduplicator 服务 | `test/services/character_import/deduplicator_test.rb` | 2.B.7 | ✅ |
| 2.E.8 | 测试 CharacterImportJob | `test/jobs/character_import_job_test.rb` | 2.C.1 | ✅ |
| 2.E.9 | 测试 CharacterDeleteJob | `test/jobs/character_delete_job_test.rb` | 2.C.2 | ✅ |
| 2.E.10 | 测试 CharacterExport::Base 服务 | `test/services/character_export/base_test.rb` | 2.B+.1 | ✅ |
| 2.E.11 | 测试 CharacterExport::JsonExporter 服务 | `test/services/character_export/json_exporter_test.rb` | 2.B+.2 | ✅ |
| 2.E.12 | 测试 CharacterExport::PngExporter 服务 | `test/services/character_export/png_exporter_test.rb` | 2.B+.3 | ✅ |
| 2.E.13 | 测试 CharacterExport::CharxExporter 服务 | `test/services/character_export/charx_exporter_test.rb` | 2.B+.4 | ✅ |

---

### Phase 3: 聊天室系统

#### 3.A 数据模型与迁移

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 3.A.1 | 创建 Room 模型和迁移（不使用 STI，统一 Direct Room） | `db/migrate/xxx_create_rooms.rb`, `app/models/room.rb` | Phase 2 | ✅ |
| 3.A.2 | 确认不使用 STI（不创建 rooms/* 子类） | `app/models/room.rb` | 3.A.1 | ✅ |
| 3.A.3 | 创建 Membership 模型和迁移 | `db/migrate/xxx_create_memberships.rb`, `app/models/membership.rb` | 3.A.1 | ✅ |
| 3.A.4 | 创建 Message 模型和迁移 | `db/migrate/xxx_create_messages.rb`, `app/models/message.rb` | 3.A.3 | ✅ |
| 3.A.5 | 确认不使用 ActionText（Message 使用 `content` 纯文本字段） | `app/models/message.rb` | 3.A.4 | ✅ |

#### 3.B 实时通信

**配置说明：** 使用 `async-cable` 提供 Fiber 友好的 WebSocket 处理（兼容 Falcon），配合 `solid_cable` 作为生产环境的消息 pub/sub 适配器。

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 3.B.1 | 配置 ApplicationCable Connection | `app/channels/application_cable/connection.rb` | 3.A.1 | ✅ |
| 3.B.2 | 实现 RoomChannel | `app/channels/room_channel.rb` | 3.B.1 | ✅ |
| 3.B.3 | 实现 Message::Broadcasts concern | `app/models/message/broadcasts.rb` | 3.A.4, 3.B.2 | ✅ |
| 3.B.4 | 创建 room_channel.js 客户端 | `app/javascript/channels/room_channel.js` | 3.B.2 | ✅ |

#### 3.C 控制器

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 3.C.1 | 实现 RoomsController (index, show, new, create) | `app/controllers/rooms_controller.rb` | 3.A.1 | ✅ |
| 3.C.2 | 实现 RoomsController (edit, update, destroy) | `app/controllers/rooms_controller.rb` | 3.C.1 | ✅ |
| 3.C.3 | 实现 MessagesController | `app/controllers/messages_controller.rb` | 3.A.4 | ✅ |
| 3.C.4 | 实现 Rooms::MembershipsController | `app/controllers/rooms/memberships_controller.rb` | 3.A.3 | ✅ |
| 3.C.5 | 实现 Rooms::SettingsController | `app/controllers/rooms/settings_controller.rb` | 3.A.1 | ✅ |
| 3.C.6 | 添加路由配置 | `config/routes.rb` | 3.C.1 | ✅ |

#### 3.D 测试

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 3.D.1 | 测试 ApplicationCable::Connection | `test/channels/application_cable/connection_test.rb` | 3.B.1 | ✅ |
| 3.D.2 | 测试 RoomChannel | `test/channels/room_channel_test.rb` | 3.B.2 | ✅ |
| 3.D.3 | 测试 Message::Broadcasts | `test/models/message/broadcasts_test.rb` | 3.B.3 | ✅ |
| 3.D.4 | 测试 RoomsController | `test/controllers/rooms_controller_test.rb` | 3.C.1, 3.C.2 | ✅ |
| 3.D.5 | 测试 MessagesController | `test/controllers/messages_controller_test.rb` | 3.C.3 | ✅ |
| 3.D.6 | 测试 Rooms::MembershipsController | `test/controllers/rooms/memberships_controller_test.rb` | 3.C.4 | ✅ |
| 3.D.7 | 测试 Rooms::SettingsController | `test/controllers/rooms/settings_controller_test.rb` | 3.C.5 | ✅ |

---

### Phase 4: LLM 集成

#### 4.A 提示词构建

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 4.A.1 | 实现 PromptBuilder 服务 | `app/services/prompt_builder.rb` | Phase 3 | ✅ |
| 4.A.2 | 实现 Membership#to_participant | `app/models/membership.rb` | Phase 3 | ✅ |
| 4.A.3 | 集成 TavernKit 提示词构建 | `app/services/prompt_builder.rb` | 4.A.1, 4.A.2 | ✅ |

#### 4.B 调度与执行（Run-driven）

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 4.B.1 | 实现 RunPlanner（写入/覆盖 queued + kick） | `app/services/room/run_planner.rb` | 4.A.1 | ✅ |
| 4.B.2 | 实现 RunExecutor（claim/stream/followup） | `app/services/room/run_executor.rb` | 4.B.1 | ✅ |
| 4.B.3 | 实现 RoomRunJob | `app/jobs/room_run_job.rb` | 4.B.2 | ✅ |
| 4.B.4 | 实现 copilot_mode 基础语义（full 禁止手动 user 消息） | `app/models/membership.rb`, `app/controllers/messages_controller.rb` | Phase 3 | ✅ |

#### 4.C 消息控制器扩展

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 4.C.1 | 消息创建后触发 AI 响应 | `app/controllers/messages_controller.rb` | 4.B.1 | ✅ |
| 4.C.2 | 实现 regenerate 功能 | `app/controllers/rooms_controller.rb` | 4.B.1 | ✅ |

#### 4.D 测试

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 4.D.1 | 测试 PromptBuilder | `test/services/prompt_builder_test.rb` | 4.A.1 | ✅ |
| 4.D.2 | 测试 RunPlanner/RunExecutor | `test/services/room/run_planner_test.rb`, `test/services/room/run_executor_test.rb` | 4.B.* | ✅ |
| 4.D.3 | 测试 copilot_mode full 禁止手动 user 消息 | `test/controllers/messages_controller_test.rb` | 4.B.4 | ✅ |

---

### Phase 5: UI 实现（Chat Room）

本阶段实现三栏「聊天室」UI，并将右侧（Membership LLM 设置）切换为 **Settings Schema Pack（模块化 JSON Schema）驱动** 的渲染方案。

**设计目标：**
- Desktop：固定三栏（左 320px / 中央自适应 / 右 380px）
- Mobile：左右 Sidebar 使用 DaisyUI Drawer 抽屉
- 右侧 Sidebar 专注“当前 Membership 的 LLM 设置”（Quick/Advanced 两个 Tab）
- Room Settings 提供独立页面 `/rooms/:id/settings`（Quick/Advanced）
- Character Settings 提供编辑页面 `/settings/characters/:id/edit`（Quick/Advanced）
- 所有设置变更：debounce 300ms 自动保存（JSON merge patch / deep-merge），无需整页刷新
- **Schema pack 驱动**：Schema 文件在 `app/settings_schemas/`，Rails 侧 bundle 成单一 schema JSON 提供给前端（`GET /schemas/settings`）

**技术约束：**
- 必须使用 Rails + Turbo + Stimulus + ActionCable
- CSS 只用 TailwindCSS 4 + DaisyUI 5
- **数据库**：PostgreSQL（支持 `jsonb` 类型，为未来 RAG 功能预留 pgvector）
- **三层设置存储**：
  - `Setting` (全局) → `Room.settings:jsonb` (房间) → `Membership.settings:jsonb` (成员)
- API Key 等敏感字段使用 Rails Active Record Encryption
- **provider_key 不落库**：由 `membership.llm_provider_id` 推导（`membership.llm_provider.name` → `LLMProvider#schema_provider_key`）
- **Provider Gating**：右侧面板以 Schema 的 `x-ui.visibleWhen` + UI context `{provider_key}` 控制显示/隐藏
- 前端 schema-renderer 只负责：`x-ui.tab / x-ui.group / x-ui.order / x-ui.quick / x-ui.visibleWhen` 的布局与显示/隐藏；不做复杂校验/互斥/范围推导
- 后端校验（可选）：当前保存接口只做 deep-merge 写入；如需完整 JSON Schema 校验，可在 Rails 侧补充

**Schema pack 文件策略（`app/settings_schemas/`）：**
- pack 根目录：`playground/app/settings_schemas/`
- 入口索引：`manifest.json`；entry schema：`root.schema.json`
- Schema 通过 `$ref` 跨文件引用；Rails 侧通过 `SettingsSchemaPack.bundle` 输出 bundled “单 schema JSON”
- 预留 `extensions/`：bundler 内部有 `apply_extensions(bundle)` hook（当前 no-op）
- `SettingsSchemaPack.digest` 用于 ETag/cache key；开发环境可 `SettingsSchemaPack.reload!`
- 备注：旧的单文件 schema（`playground/config/settings_schema.json`）与对应服务已移除

**Schema pack 驱动架构：**

```
app/settings_schemas/* (manifest + root + defs + providers)
                ↓ (Rails bundle / dereference $ref)
SettingsSchemaPack.bundle  →  GET /schemas/settings (ETag: SettingsSchemaPack.digest)
                ↓
SettingsSchemas::FieldEnumerator (server 渲染 leaf fields → hidden pool)
                ↓
schema_renderer_controller.js (仅做 layout + visibleWhen 显示/隐藏 + group/order/quick)
                ↓
settings_form_controller.js (debounce 300ms → PATCH membership/room/character JSON)
```

#### 5.0 数据模型变更（前置）

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 5.0.1 | Membership 支持 LLM provider 覆盖与 settings 存储 | `playground/db/migrate/20251230000002_create_memberships.rb` | Phase 4 | ✅ |
| 5.0.2 | Membership: effective provider + provider_key 派生 | `playground/app/models/membership.rb` | 5.0.1 | ✅ |
| 5.0.3 | LLMProvider: schema_provider_key 映射 | `playground/app/models/llm_provider.rb` | - | ✅ |
| 5.0.4 | 接入 Settings Schema Pack（模块化 schema） | `playground/app/settings_schemas/` | - | ✅ |

说明：
- 切换 provider 只更新 `memberships.llm_provider_id`；`memberships.settings` 保留 `llm.providers.*` 的全量对象，便于切回恢复。
- `memberships.settings_version` 用于乐观锁：保存时校验 version，不一致返回 409；`settings-form` 会自动重试一次。

**Membership Model（关键方法）：**
```ruby
# app/models/membership.rb
class Membership < ApplicationRecord
  belongs_to :llm_provider, class_name: "LLMProvider", optional: true

  def effective_llm_provider
    llm_provider || LLMProvider.get_default
  end

  def provider_identification
    provider = effective_llm_provider
    return "openai_compatible" unless provider

    provider.identification
  end
end
```

**LLMProvider Model（关键方法）：**
```ruby
# app/models/llm_provider.rb
class LLMProvider < ApplicationRecord
  IDENTIFICATIONS = %w[openai openai_compatible gemini deepseek anthropic qwen xai]

  # 获取默认 provider（通过 Setting 存储）
  def self.get_default
    provider_name = Setting.get("llm.default_provider", "OpenAI")
    find_by(name: provider_name)
  end

  # 设置默认 provider
  def self.set_default!(name)
    provider = find_by!(name: name)
    Setting.set("llm.default_provider", name)
    provider
  end
end
```

**Room 设置继承：**
```ruby
# app/models/room.rb
def effective_settings
  global = Setting.get("generation.defaults", "{}")
  global_hash = JSON.parse(global) rescue {}
  global_hash.deep_merge(settings.presence || {})
end

def effective_setting(key)
  effective_settings[key.to_s]
end
```

#### 5.A 布局与共享组件

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 5.A.1 | 更新 chat 布局（三栏 Drawer 设计） | `app/views/layouts/chat.html.erb` | Phase 4 | ✅ |
| 5.A.2 | 创建 shared/flash partial | `app/views/shared/_flash.html.erb` | 5.A.1 | ✅ |
| 5.A.3 | 创建 avatar_helper | `app/helpers/avatar_helper.rb` | - | ✅ |
| 5.A.4 | 创建 message_helper | `app/helpers/message_helper.rb` | - | ✅ |
| 5.A.5 | 创建 membership_avatar helper | `app/helpers/avatar_helper.rb` | 5.A.3 | ✅ |

#### 5.B 左侧边栏重构

**左侧 Sidebar 结构：**
- Header: Chat Switcher dropdown + 搜索框
- Tabs: Members / Stats / Lorebooks / Presets（ST Presets）
- Tab Content: 每个 tab 使用 turbo-frame 懒加载
- Footer: Room Settings 链接（`/rooms/:id/settings`）

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 5.B.1 | 重构左侧边栏主结构 | `app/views/rooms/_left_sidebar.html.erb` | 5.A.1 | ✅ |
| 5.B.2 | 实现 Chat Switcher dropdown | `app/views/rooms/_left_sidebar.html.erb` | 5.B.1 | ✅ |
| 5.B.3 | 创建 Members tab 内容 | `app/views/rooms/sidebar/_members.html.erb` | 5.B.1 | ✅ |
| 5.B.4 | 创建 Stats tab 内容 | `app/views/rooms/sidebar/_stats.html.erb` | 5.B.1 | ✅ |
| 5.B.5 | 创建 Lorebooks tab 内容（占位） | `app/views/rooms/sidebar/_lorebooks.html.erb` | 5.B.1 | ⚠️ 占位 |
| 5.B.6 | 创建 Presets tab 内容 | `app/views/rooms/sidebar/_presets.html.erb` | 5.B.1 | ⚠️ 占位 |

**Tab 内容说明：**

| Tab | 内容 | 说明 |
|-----|------|------|
| **Members** | 人类用户 + AI Characters | 显示当前 Room 参与者，含 LLM Provider 覆盖指示 |
| **Stats** | 聊天统计 | 消息数、字数、创建时间、最后活动时间 |
| **Lorebooks** | 关联的 World Info | 当前 Room 使用的知识库（占位，后续实现） |
| **Presets** | ST Presets | SillyTavern 格式的 Presets（聊天/生成预设，与右侧 LLM Profile 不同） |

#### 5.C 右侧设置面板（Membership LLM 设置）

目标：右侧面板完全由 **Settings Schema Pack** 驱动渲染（Membership LLM 的 prompt-budget 设置），并按 provider gating + Quick/Advanced 分层；`provider_key` 完全由 `membership.llm_provider_id` 推导（不落库）。

**右侧 Sidebar（当前实现）：**
- Header：
  - Target Member 下拉（管理员可切换目标；通过 Turbo Frame 重渲染右侧面板）
  - Provider 下拉（写入 `memberships.llm_provider_id`）
  - Connection 状态 badge
- Model 行：显示 effective provider 的 model + 派生的 `provider_key` badge
- Tabs：Quick / Advanced
- 内容区：Rails 预渲染所有 leaf 字段到 hidden pool；Stimulus `schema-renderer` 只根据 `x-ui.group / x-ui.order / x-ui.quick / x-ui.visibleWhen` 进行分组、排序与显示/隐藏

**字段来源与分层：**
- Schema 来源：`GET /schemas/settings`（bundle 后单 schema）
- 渲染范围：`membership.llm` 子树（含 `providers.*` 全家）
- Quick：`x-ui.quick=true` 的 leaf 字段
- Advanced：全部 leaf 字段（按 group 折叠；目前默认展开）

**Provider gating：**
- 使用 Schema 的 `x-ui.visibleWhen`（例如 `{context:"provider_key", const:"openai"}`）控制 provider-specific block 显示/隐藏
- UI context 的 `provider_key` 由后端返回的 `membership.schema_provider_key` 决定（membership override → global fallback）

**保存协议（JSON PATCH / deep-merge）：**
- Endpoint：`PATCH /rooms/:room_id/memberships/:id`（`Content-Type: application/json`）
- Payload：
  ```json
  {
    "schema_version": "membership_llm_v1",
    "llm_provider_id": 123,
    "settings": {
      "llm": {
        "providers": {
          "openai": { "generation": { "max_context_tokens": 16384, "max_response_tokens": 768 } }
        }
      }
    }
  }
  ```
- 规则：
  - 切换 provider 只更新 `llm_provider_id`
  - `settings` 采用 deep-merge 写入：不会清空未提交的 `llm.providers.*`（便于切回恢复）
  - 成功响应包含 `membership.schema_provider_key`，前端用于更新 gating context

**Disabled 支持：**
- 若 schema `disabled=true` 或 `x-ui.disabled=true`：控件渲染为 disabled；若 `x-ui.disabledReason` 存在则展示原因

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 5.C.1 | 重构右侧边栏主结构（Schema-Ready） | `playground/app/views/rooms/_right_sidebar.html.erb` | 5.A.1 | ✅ |
| 5.C.2 | 实现 Header（Target Member + Provider + 状态） | `playground/app/views/rooms/_right_sidebar.html.erb` | 5.C.1 | ✅ |
| 5.C.3 | 实现 Quick/Advanced tabs | `playground/app/views/rooms/_right_sidebar.html.erb` | 5.C.1 | ✅ |
| 5.C.4 | Server 渲染字段池（leaf fields） | `playground/app/services/settings_schemas/field_enumerator.rb` | 5.0.4 | ✅ |
| 5.C.5 | Schema-renderer 布局（group/order/quick/visibleWhen） | `playground/app/javascript/controllers/schema_renderer_controller.js` | 5.C.4 | ✅ |
| 5.C.6 | Provider dropdown 立即保存并刷新 gating | `playground/app/javascript/controllers/settings_form_controller.js` | 5.C.2 | ✅ |
| 5.C.7 | 保存状态 Footer | `playground/app/javascript/controllers/settings_form_controller.js` | 5.C.1 | ✅ |

#### 5.D 消息视图

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 5.D.1 | 创建消息列表 partial | `app/views/messages/_message.html.erb` | 3.C.3 | ✅ |
| 5.D.2 | 创建消息编辑器组件 | `app/views/messages/_form.html.erb` | 3.C.3 | ✅ |
| 5.D.3 | 创建消息 Turbo Stream 模板 | `app/views/messages/create.turbo_stream.erb` | 3.B.3 | ✅ |
| 5.D.4 | 创建 typing indicator 组件 | `app/views/messages/_typing_indicator.html.erb` | 5.D.1 | ✅ |
| 5.D.5 | 增强消息 actions（编辑/删除/再生成） | `app/views/messages/_message.html.erb` | 5.D.1 | ✅ |

#### 5.E Stimulus 控制器

**当前控制器清单：**

| ID | 任务 | 产出物 | 说明 | 状态 |
|----|------|--------|------|------|
| 5.E.1 | tabs_controller.js（Quick/Advanced tab 切换） | `playground/app/javascript/controllers/tabs_controller.js` | - | ✅ |
| 5.E.2 | schema_renderer_controller.js（布局 + visibleWhen；不生成字段） | `playground/app/javascript/controllers/schema_renderer_controller.js` | schema-driven 布局 | ✅ |
| 5.E.3 | settings_form_controller.js（debounce 300ms + deep-merge PATCH） | `playground/app/javascript/controllers/settings_form_controller.js` | JSON PATCH 自动保存 | ✅ |
| 5.E.4 | auto_submit_controller.js（Target Member 切换提交） | `playground/app/javascript/controllers/auto_submit_controller.js` | Turbo Frame 重渲染右侧面板 | ✅ |
| 5.E.5 | range_display_controller.js（滑块值显示） | `playground/app/javascript/controllers/range_display_controller.js` | - | ✅ |
| 5.E.6 | tags_input_controller.js（标签输入） | `playground/app/javascript/controllers/tags_input_controller.js` | - | ✅ |
| 5.E.7 | segmented_controller.js（分段控件） | `playground/app/javascript/controllers/segmented_controller.js` | - | ✅ |
| 5.E.8 | chat_scroll_controller.js | `playground/app/javascript/controllers/chat_scroll_controller.js` | Intersection Observer 加载历史消息 | ✅ |
| 5.E.9 | message_form_controller.js | `playground/app/javascript/controllers/message_form_controller.js` | 消息输入表单（Enter 提交、Ctrl+Enter 换行） | ✅ |
| 5.E.10 | message_actions_controller.js | `playground/app/javascript/controllers/message_actions_controller.js` | 消息操作（编辑/删除/再生成） | ✅ |
| 5.E.11 | room_channel_controller.js | `playground/app/javascript/controllers/room_channel_controller.js` | ActionCable 订阅、typing/streaming 事件分发 | ✅ |
| 5.E.12 | typing_indicator_controller.js | `playground/app/javascript/controllers/typing_indicator_controller.js` | 打字指示器（显示流式内容） | ✅ |
| 5.E.13 | chat_hotkeys_controller.js | `playground/app/javascript/controllers/chat_hotkeys_controller.js` | 聊天热键（ArrowLeft/Right 切换 Swipe、Ctrl+Enter 再生成、Up/Ctrl+Up 编辑消息、Esc 取消编辑） | ✅ |
| 5.E.14 | markdown_controller.js | `playground/app/javascript/controllers/markdown_controller.js` | Markdown 渲染（marked） | ✅ |
| 5.E.15 | toast_controller.js | `playground/app/javascript/controllers/toast_controller.js` | Toast 通知显示与自动消失 | ✅ |
| 5.E.16 | dropzone_controller.js | `playground/app/javascript/controllers/dropzone_controller.js` | 文件拖拽上传（角色卡导入） | ✅ |
| 5.E.17 | theme_controller.js | `playground/app/javascript/controllers/theme_controller.js` | 主题切换（light/dark） | ✅ |
| 5.E.18 | sidebar_controller.js | `playground/app/javascript/controllers/sidebar_controller.js` | 侧边栏开关（移动端 Drawer） | ✅ |
| 5.E.19 | llm_settings_controller.js | `playground/app/javascript/controllers/llm_settings_controller.js` | LLM Provider 管理（测试连接、获取模型） | ✅ |
| 5.E.20 | copilot_controller.js | `playground/app/javascript/controllers/copilot_controller.js` | Copilot 候选回复生成、候选快捷键（1-4/Esc） | ✅ |
| 5.E.21 | auto_swipe_controller.js | `playground/app/javascript/controllers/auto_swipe_controller.js` | Auto-swipe（内容规则自动 regenerate） | ✅ |

说明：
- `schema-renderer` 只处理 `x-ui.group / x-ui.order / x-ui.quick / x-ui.visibleWhen`（以及未来可扩展的 `x-ui.tab`）；不做字段生成与复杂校验。
- `settings-form` 以 `data-setting-path` 为准：`settings.*` 生成嵌套 patch，其它路径作为直接列（如 `llm_provider_id`），并在 provider 变更时立即保存。
- `chat_scroll_controller` 实现了 Intersection Observer 驱动的历史消息懒加载（每次 20 条），替代了原计划的 `scroll_manager.js`。

#### 5.F 设置 Field Partials

通用设置字段 partials，用于 **server 渲染 leaf fields**。`schema-renderer` 不生成字段，只做布局与显示/隐藏，因此每个 partial 必须输出稳定的 data 属性（供 `settings-form` 和 `schema-renderer` 使用）。

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 5.F.1 | range field partial（slider） | `playground/app/views/settings/fields/_range.html.erb` | - | ✅ |
| 5.F.2 | number field partial | `playground/app/views/settings/fields/_number.html.erb` | - | ✅ |
| 5.F.3 | toggle field partial | `playground/app/views/settings/fields/_toggle.html.erb` | - | ✅ |
| 5.F.4 | select field partial | `playground/app/views/settings/fields/_select.html.erb` | - | ✅ |
| 5.F.5 | text field partial | `playground/app/views/settings/fields/_text.html.erb` | - | ✅ |
| 5.F.6 | textarea field partial | `playground/app/views/settings/fields/_textarea.html.erb` | - | ✅ |
| 5.F.7 | tags field partial | `playground/app/views/settings/fields/_tags.html.erb` | - | ✅ |
| 5.F.8 | segmented field partial | `playground/app/views/settings/fields/_segmented.html.erb` | - | ✅ |

**Field 数据契约（右侧面板必需）：**
- `data-schema-field="true"`（表示该节点可被 schema-renderer 移动/排序）
- `data-setting-path="settings.llm.providers.openai.generation.max_context_tokens"`（右侧面板统一以 `settings.*` 开头；provider 下拉为 `llm_provider_id`）
- `data-setting-type="number|integer|boolean|string|array"`
- `data-ui-quick="true|false"` / `data-ui-order="N"` / `data-ui-group="Generation"`
- `data-visible-when='{"context":"provider_key","const":"openai"}'`（可选）
- Disabled：控件禁用时附加 `data-schema-disabled=true`，并展示 `disabledReason`（如果有）

#### 5.G 后端支持（Routes & Controllers）

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 5.G.1 | 提供 bundled schema endpoint（/schemas/settings） | `playground/app/controllers/schemas/settings_controller.rb`, `playground/config/routes.rb` | 5.0.4 | ✅ |
| 5.G.2 | Membership JSON PATCH（deep-merge） | `playground/app/controllers/rooms/memberships_controller.rb` | 5.C.* | ✅ |
| 5.G.3 | Room Settings JSON PATCH（schema pack + `x-storage` 映射） | `playground/app/controllers/rooms/settings_controller.rb` | - | ✅ |
| 5.G.4 | 移除 legacy：/rooms/:room_id/membership/llm_settings | `playground/config/routes.rb` | - | ✅ |
| 5.G.5 | RunExecutor 使用 speaker 的 provider/settings | `playground/app/services/room/run_executor.rb` | 5.C.* | ✅ |

**Endpoints（右侧面板当前使用）：**
- `GET /schemas/settings`：返回 `SettingsSchemaPack.bundle`（ETag: `SettingsSchemaPack.digest`，缓存 5 分钟）
- `PATCH /rooms/:room_id/memberships/:id`（`Content-Type: application/json`）：接受 `{schema_version, llm_provider_id?, settings?}` 并 deep-merge 写入 `membership.settings`，成功响应包含 `membership.schema_provider_key` 以更新前端 gating context
- `PATCH /rooms/:room_id/settings`（`Content-Type: application/json`）：接受 `{schema_version, settings_version, settings}`，按 `defs/room.schema.json` 的 `x-storage` 映射写入 `Room`（columns + `room.settings`）
- `PATCH /settings/characters/:id`（`Content-Type: application/json`）：接受 `{schema_version, data}`，deep-merge 写入 `Character#data`

备注：
- 新右侧面板使用 `PATCH /rooms/:room_id/memberships/:id` 进行设置保存（deep-merge），不再使用旧的 `/rooms/:room_id/membership/llm_settings` 路径。
- legacy 的 `Rooms::LLMSettingsController` 已移除；`llm_settings_controller.js` 仍用于 Settings → LLM Providers 管理页。

#### 5.H Services（Schema pack 驱动核心）

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 5.H.1 | SettingsSchemaPack 对外入口（bundle/digest/reload!） | `playground/app/services/settings_schema_pack.rb` | 5.0.4 | ✅ |
| 5.H.2 | Manifest/Loader/RefResolver/Bundler | `playground/app/services/settings_schemas/` | 5.H.1 | ✅ |
| 5.H.3 | Leaf field 枚举（用于 server 渲染字段池） | `playground/app/services/settings_schemas/field_enumerator.rb` | 5.H.2 | ✅ |
| 5.H.4 | Extensions hook（预留 overlay） | `playground/app/services/settings_schemas/extensions.rb` | 5.H.2 | ✅ |

**核心语义（Schema pack）：**
- `SettingsSchemas::Loader`：按 pack-relative path 读取 JSON（进程级 memoize），并保留 absolute path 供 `$ref` 相对路径解析。
- `SettingsSchemas::RefResolver`：支持 `defs/*.schema.json`、`defs/*.schema.json#/$defs/...`、`#/$defs/...`；支持 JSON Pointer 转义 `~0/~1`。
- `SettingsSchemas::Bundler`：递归 dereference `$ref`，并处理 `$ref` 与 sibling keys 共存（overlay deep-merge）；提供循环引用检测；并对 `allOf` 做 flatten/deep-merge（便于 server 遍历/渲染）。
- `SettingsSchemas::FieldEnumerator`：从 bundled schema 生成 leaf fields（包含 `ui_group/ui_order/ui_quick/visible_when/disabled_reason` 等元信息），供 `playground/app/views/rooms/_right_sidebar.html.erb` 渲染字段池。

备注：
- 旧方案（单文件 schema + JSON Patch ops）已移除，统一以 schema pack 为准。

#### 5.I Room Settings 页面（Schema pack 驱动）

Room 级别设置使用 schema pack（`defs/room.schema.json`）驱动渲染，并通过 `x-storage` 将 schema 字段映射到 Room 的 column/json 存储。

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 5.I.1 | Room Settings UI（field pool + Quick/Advanced + visibleWhen ref/in） | `playground/app/views/rooms/settings/_form.html.erb`, `playground/app/javascript/controllers/schema_renderer_controller.js` | 5.F.*, 5.H.3 | ✅ |
| 5.I.2 | Room Settings JSON PATCH（schema pack + `x-storage` 映射） | `playground/app/controllers/rooms/settings_controller.rb`, `playground/app/services/settings_schemas/storage_applier.rb` | 5.H.2 | ✅ |

---

### Phase 6: 高级功能

#### 6.A Copilot / Auto-mode

**已完成**：
- `Membership.copilot_mode` 字段简化为 `none` 和 `full`（移除 `partial`）
- 候选条数由前端请求参数 `candidate_count` 传入（1..4，默认 1），不落库
- "Generate Suggestions" 功能在 `copilot_mode = none` 时可用
- `CopilotCandidateJob` 实现候选回复生成
- `CopilotChannel` 实现实时广播（按 membership 单播）
- 完整的 Stimulus 控制器 `copilot_controller.js`（支持候选快捷键 1-4/Esc）
- LLM 调用超时（30s）和错误处理
- toggleFullMode() 无刷新切换（UI 原地更新 + toast 反馈）

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 6.A.1 | UI：设置 copilot_mode toggle（none/full） | `app/views/messages/_form.html.erb` | Phase 5 | ✅ |
| 6.A.2 | Generate Suggestions：生成候选回复（1..4）并提供"Use"操作 | `app/jobs/copilot_candidate_job.rb`, `copilot_controller.js` | 4.B.1, 6.A.1 | ✅ |
| 6.A.3 | full：自动回复（由 Room 调度器实现） | `app/models/room.rb` | - | ✅ |
| 6.A.4 | Copilot UX 增强：候选快捷键（1-4/Esc）、无刷新切换 | `copilot_controller.js` | 6.A.2 | ✅ |
| 6.A.5 | Auto-swipe：内容规则自动 regenerate | `auto_swipe_controller.js`, `_auto_swipe_settings.html.erb` | Phase 5 | ✅ |

#### 6.B 群组聊天增强

**后端已完成**：`Room#next_speaker`、`activation_strategy`、`generation_mode` 字段与逻辑已实现。UI 已在 Edit Room 的 Advanced Settings 中。

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 6.B.1 | 实现 Room#next_speaker 方法 | `app/models/room.rb` | 3.A.1 | ✅ |
| 6.B.2 | 实现 activation_strategy 切换 UI | `app/views/rooms/_form.html.erb` | 3.C.5 | ✅ 在 Edit Room Advanced Settings |
| 6.B.3 | 实现 generation_mode 切换 UI | `app/views/rooms/_form.html.erb` | 3.C.5 | ✅ 在 Edit Room Advanced Settings |

#### 6.C 调试面板

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 6.C.1 | 创建 Token 计数显示组件 | `app/views/rooms/_debug_panel.html.erb` | Phase 4 | ⬜ |
| 6.C.2 | 创建提示词预览功能 | `app/views/rooms/_prompt_preview.html.erb` | 4.A.1 | ⬜ |
| 6.C.3 | 创建生成参数调整 UI | `app/views/rooms/_generation_settings.html.erb` | Phase 4 | ⬜ |
| 6.C.4 | 实现实时日志显示 | `app/javascript/controllers/debug_controller.js` | 6.C.1 | ⬜ |

#### 6.D LLM Provider 管理

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 6.D.1 | 实现 Settings::LLMProvidersController | `app/controllers/settings/llm_providers_controller.rb` | - | ✅ |
| 6.D.2 | 创建 LLM Provider 列表视图 | `app/views/settings/llm_providers/index.html.erb` | 6.D.1 | ✅ |
| 6.D.3 | 实现 Provider 测试连接功能 | `app/controllers/settings/llm_providers_controller.rb` | 6.D.1 | ✅ |
| 6.D.4 | 实现模型列表获取功能 | `app/controllers/settings/llm_providers_controller.rb` | 6.D.1 | ✅ |

---

### Phase 7: PWA 支持

| ID | 任务 | 产出物 | 依赖 | 状态 |
|----|------|--------|------|------|
| 7.1 | 创建 PwaController | `app/controllers/pwa_controller.rb` | Phase 5 | ⬜ |
| 7.2 | 创建 Web App Manifest | `app/views/pwa/manifest.json.erb` | 7.1 | ⬜ |
| 7.3 | 创建 Service Worker | `app/views/pwa/service_worker.js.erb` | 7.1 | ⬜ |
| 7.4 | 创建 PWA 图标 | `app/assets/images/icon-192.png`, `icon-512.png` | - | ⬜ |
| 7.5 | 配置 PWA 路由 | `config/routes.rb` | 7.1 | ⬜ |
| 7.6 | 在 layout 中引用 manifest | `app/views/layouts/application.html.erb` | 7.2 | ⬜ |

---

### 任务统计（更新至 2026-01-03 CST）

**整体进度：**

| Phase | 描述 | 状态 | 完成度 |
|-------|------|------|--------|
| Phase 0 | 准备工作 | ✅ 已完成 | 100% |
| Phase 1 | 核心框架 (Setting, Auth) | ✅ 已完成 | 100% |
| Phase 2 | 角色卡系统 | ✅ 已完成 | 100% |
| Phase 3 | 聊天室系统 | ✅ 已完成 | 100% |
| Phase 4 | LLM 集成 | ✅ 已完成 | 100% |
| Phase 5 | UI 实现 | ✅ 核心完成 | 100% |
| Phase 6 | 高级功能 | ✅ 核心完成 | ~90% |
| Phase 7 | PWA 支持 | ⬜ 未开始 | 0% |

**Phase 5 详情：**
- ✅ 三栏布局、左右侧边栏
- ✅ Settings Schema Pack 驱动的 LLM 设置
- ✅ Room Settings 页面（schema pack 驱动）
- ✅ Character Settings 编辑页（schema pack 驱动）
- ✅ 消息视图、typing indicator、消息 actions
- ✅ 所有 Stimulus 控制器（包括 chat_scroll 滚动加载）
- ✅ Swipes 支持（消息多版本管理）
- ✅ 提示词预览面板 (Prompt Preview)

**Phase 6 详情：**
- ✅ 6.A.1-5 Copilot / Auto-mode（候选回复、快捷键、Auto-swipe）
- ✅ 6.B.1-3 群组聊天（`Room#next_speaker`、activation_strategy/generation_mode UI）
- ✅ 6.D.1-4 LLM Provider 管理
- ⬜ 6.C.1-4 调试面板（部分通过 Prompt Preview 实现）

**Phase 5（Settings Schema Pack）里程碑：**
- Step 1（提交 58094e6）：接入 schema pack 到 `playground/app/settings_schemas/`（manifest/root/defs/providers + 预留 extensions）
- Step 2（提交 4aba914）：Rails `$ref` bundler + `GET /schemas/settings`（ETag: `SettingsSchemaPack.digest`）+ 最小测试
- Step 3（提交 c820017）：右侧面板 schema-driven（field pool + Stimulus layout），provider_key 由 `membership.llm_provider_id` 派生；JSON PATCH deep-merge 自动保存
- Step 4（提交 7fb7daf）：Room Settings 页面 schema-driven（`x-storage` 映射 + visibleWhen ref/in）
- Step 5（提交 a0fd7dc）：Character Settings 编辑页 schema-driven（`Character#data` deep-merge）
- Step 6（提交 e8a3abc）：彻底移除 legacy（单文件 schema + JSON Patch ops + legacy LLM settings endpoint）

**测试覆盖：**
- 测试套件需要重新运行以验证最新重构

**最新架构变更（2026-01-01）：**

1. **LLMProvider 模型重构**：
   - 新增 `identification` 字段（替代 `schema_provider_key`），用于关联 Settings Schema providers
   - `name` 字段直接用作显示名称（移除 `label` 方法）
   - 新增 `last_tested_at` 字段记录最后测试时间
   - 移除 `configured?`、`local?`、`current_model`、`model_selected?` 方法
   - `current` 方法重命名为 `get_default`
   - `activate!` 方法重命名为 `set_default!`
   - 路由 `post :activate` 改为 `post :set_default`

2. **Membership 模型更新**：
   - `schema_provider_key` 重命名为 `provider_identification`
   - 使用 `provider.identification` 获取 provider 标识

3. **ActionCable 架构优化**：
   - `RoomChannel` 统一处理所有 JSON 事件（typing_start/typing_stop、stream_chunk/stream_complete）
   - `CopilotChannel` 专用于 copilot 候选回复单播（按 membership 隔离，避免多用户房间数据泄漏）
   - `Turbo::StreamsChannel` 用于 DOM 更新（消息追加/删除）
   - 使用 `solid_cable` 适配器（PostgreSQL）支持跨进程广播
   - 删除 `MessageStreamingChannel` 和 `TypingNotificationsChannel`（功能合并到 `RoomChannel`）
   - 前端通过 `room_channel_controller.js` 订阅 `RoomChannel` 并分发事件给 `typing_indicator_controller.js`

4. **Web 服务器更换**：
   - 从 Falcon 切换到 Puma，提升 ActionCable 兼容性

5. **异步 IO 约束（强制）**：
   - 除 "Test Connection" 功能外，所有 `LLMClient` 调用必须在 `ActiveJob` 中执行
   - 禁止在 Controller/Model 中直接调用 LLM API 阻塞请求
   - 重 IO 操作（外部 API 调用、文件处理等）同样必须异步执行
   - 已实现：`RoomRunJob`、`CopilotCandidateJob` 负责 LLM 调用
   - "Test Connection" 例外原因：用户主动触发、需要即时反馈、有明确超时

6. **Message 模型重构**：
   - `text` 字段重命名为 `content`
   - **原子创建**：assistant message 在 LLM 生成完成后创建（不使用 placeholder 模式），避免 broadcast race condition
   - `metadata` 用于存储 LLM 参数快照、错误信息等
   - **Swipes 支持**（SillyTavern 风格多版本 AI 回复）：
     - `active_message_swipe_id`：当前活跃的 swipe 版本
     - `message_swipes_count`：swipe 数量（counter_cache）
     - `message.content` 作为活跃 swipe 内容的缓存（始终与 `active_message_swipe.content` 同步）
   - **MessageSwipe 模型**：存储消息的多个版本（position、content、metadata、room_run_id）
   - **Swipe 方法**：
     - `ensure_initial_swipe!`：创建初始版本（position=0）
     - `add_swipe!(content:, metadata:, room_run_id:)`：添加新版本并设为活跃
     - `select_swipe!(direction:)`：切换版本（:left/:right）
   - **内容同步**：`after_update` 回调确保编辑 `message.content` 时自动同步到 `active_message_swipe.content`
   - **上下文影响**：`PromptBuilder` 使用 `message.content` 构建历史，因此切换 swipe 会影响后续生成的上下文

7. **Membership 模型新增 `copilot_remaining_steps` 字段**：
   - 限制 full copilot 自动回复次数，避免 AI 无限对话导致 LLM 调用费用爆炸
   - 取值范围：1..10（启用 Full Copilot 时默认 5）
   - 成功生成后递减 1；耗尽自动关闭并广播 reason
   - 失败不消耗步数（但会自动关闭并广播 error，避免无限重试）

8. **Run 驱动调度器架构**（详见 [CONVERSATION_AUTO_RESPONSE.md](./CONVERSATION_AUTO_RESPONSE.md)）：
   - `Room` 只存配置（Policy），不存运行态
   - 运行态全部落在 `room_runs`（执行状态机：queued/running/succeeded/failed/canceled/skipped）
   - 并发保证：每个 room 同时最多 1 个 `running` run；同时最多 1 个 `queued` run（单槽队列）
   - **Room::RunPlanner**：计划/写入 queued run
     - `plan_from_user_message!` - 用户发消息后触发 AI 响应
     - `plan_copilot_start!` - 启用 Full Copilot 时触发首次发言
     - `plan_copilot_followup!` - Copilot User 发言后触发 AI Character 响应
     - `plan_copilot_continue!` - AI Character 发言后触发 Copilot User 继续
     - `plan_auto_mode_followup!` - AI-to-AI 链式响应（需 `auto_mode_enabled=true`）
   - **Room::RunExecutor**：执行 run（claim/stream/cancel/followup）
     - `kick_followups_if_needed` 根据 speaker 类型触发对应的 follow-up
   - **SpeakerSelector**：选择下一个 speaker（支持 natural/list/manual/pooled）
   - 旧调度字段与 legacy job 已移除（见 `docs/CONVERSATION_AUTO_RESPONSE.md`）

**⚠️ 已知技术债务 / TODO（按优先级）：**

| ID | 内容 | 位置 | 优先级 |
|----|------|------|--------|
| TD-6 | Lorebooks / Presets tab 真实内容 | `playground/app/views/rooms/_left_sidebar.html.erb` | P3 |
| TD-7 | RAG / 知识库（检索 + 注入 prompt；schema 已预留但默认禁用） | `playground/app/settings_schemas/defs/resources.schema.json`, `playground/app/services/prompt_builder.rb` | P2 |
| TD-8 | 记忆（summary / vector memory；schema 已预留但默认禁用） | `playground/app/settings_schemas/defs/resources.schema.json`, `playground/app/services/prompt_builder.rb` | P2 |

---

### 推荐实施顺序

**Phase 2 建议顺序：** ✅ 已完成
1. 先完成 2.A（数据模型），这是所有后续任务的基础
2. 同步进行 2.E.1（测试 fixtures），为测试做准备
3. 按 2.B.1 → 2.B.2 → 2.B.3 → 2.B.4/2.B.5 顺序实现导入服务
4. 2.B.6/2.B.7 可与上述并行
5. 2.C 依赖 2.B 完成
6. 2.D 可在 2.A 完成后逐步开始
7. 2.E 跟随对应服务完成后编写

**Phase 3 建议顺序：** ✅ 已完成
1. 3.A.1 → 3.A.2 → 3.A.3 → 3.A.4 → 3.A.5（数据模型链）
2. 3.B 可在 3.A.1 完成后开始
3. 3.C 跟随模型完成后实现

**Phase 5 建议顺序：** ✅ 核心完成（Settings Schema Pack 驱动）；剩余增强见上方 TODO

```
1. Schema pack 接入（Step 1 / 5.0.4）
   ├── `playground/app/settings_schemas/`（manifest + root + defs + providers）
   └── 预留 `extensions/`（apply_extensions hook）

2. Rails bundle 输出（Step 2 / 5.H + 5.G.1）
   ├── `$ref` dereference + overlay deep-merge + 循环检测
   ├── `SettingsSchemaPack.bundle` / `SettingsSchemaPack.digest`
   └── `GET /schemas/settings`（前端无需再请求 defs/*.json）

3. Membership LLM 设置落地（Step 3 / 5.C + 5.G.2）
   ├── provider_key 由 `membership.llm_provider_id` 派生（不落库）
   ├── Rails 渲染 leaf fields → hidden pool
   ├── schema-renderer：按 `x-ui.group/order/quick/visibleWhen` 布局 + gating
   └── settings-form：debounce 300ms → deep-merge PATCH `/rooms/:room_id/memberships/:id`

4. 可选增强（对应 TD 列表）
   └── Lorebooks / Presets tab 真实内容
```

**关键路径：**
```
Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 7 (PWA)
                                  ↓
                            5.0 (Model)
                                  ↓
                            5.H (Services)
                                  ↓
                      ┌─────────────────────┐
                      ↓                     ↓
              5.F (Field Partials)    5.E.1-4 (Stimulus)
                      ↓                     ↓
                      └──────────┬──────────┘
                                 ↓
                         5.G (Controllers)
                                 ↓
                ┌────────────────┴────────────────┐
                ↓                                 ↓
        5.C (Right Sidebar)              5.I (Room Settings)
                ↓                                 ↓
        5.B (Left Sidebar)               Edit Room Advanced
                └────────────────┬────────────────┘
                                 ↓
                     5.D.4-5 / 5.E.6 (Enhancement)
```

---

## 第八部分：最佳实践与经验教训

### 8.1 实时通信架构：避免 Broadcast Race Condition

**问题背景：**

在实现 AI 消息生成功能时，最初采用的双通道架构导致了严重的 race condition：
- `Turbo::StreamsChannel`：负责消息 DOM 更新（append/replace/remove）
- `MessageStreamingChannel`：负责 token 流式传输事件

**失败模式：**

1. **流式 chunks 早于 DOM 元素到达**：`MessageStreamingChannel` 的 chunks 可能在 Turbo Stream 的 `append` 操作完成前到达，导致找不到目标元素
2. **Placeholder 消息更新竞争**：先创建空 placeholder message，再通过流式更新内容，但 Turbo Stream replace 与 streaming chunks 存在时序不确定性
3. **多通道订阅复杂度**：前端需要同时订阅多个 channel，协调逻辑分散在多个 Stimulus 控制器中

**正确架构（已采用）：**

```
┌─────────────────────────────────────────────────────────────────┐
│                     RoomChannel (JSON)                          │
│  - typing_start / typing_stop（打字指示器显示/隐藏）              │
│  - stream_chunk（流式内容预览，显示在 typing indicator 中）       │
│  - stream_complete（流式完成信号）                               │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    前端 Stimulus 控制器
                    room_channel_controller.js
                              ↓
                    ┌─────────────────────┐
                    │  typing indicator   │  ← 流式内容在此显示
                    │  (ephemeral UI)     │
                    └─────────────────────┘
                              ↓
                    生成完成后，后端创建 Message
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│              Turbo::StreamsChannel (DOM)                        │
│  - broadcast_append（追加最终消息到 DOM）                        │
│  - broadcast_replace（更新消息内容）                             │
│  - broadcast_remove（删除消息）                                  │
└─────────────────────────────────────────────────────────────────┘
```

**核心原则：**

| 原则 | 说明 |
|------|------|
| **分离 ephemeral 与 persistent** | JSON 事件用于临时状态（typing、streaming preview）；Turbo Streams 用于持久化 DOM 变更 |
| **消息原子创建** | 不使用 placeholder message；Message 在内容完全生成后才创建，通过 Turbo Stream append 一次性添加到 DOM |
| **统一 JSON 通道** | 同一 room 的所有 JSON 事件（typing、streaming）统一通过 `RoomChannel` 广播，避免多通道时序问题 |
| **typing indicator 作为 streaming 容器** | 流式内容显示在 typing indicator 中（ephemeral），而非 placeholder message bubble（persistent） |

**代码示例：**

```ruby
# app/channels/room_channel.rb
class RoomChannel < ApplicationCable::Channel
  class << self
    # 统一广播 typing 状态（含样式信息，支持动态 typing indicator）
    def broadcast_typing(room, membership:, active:)
      broadcast_to(room, {
        type: active ? "typing_start" : "typing_stop",
        membership_id: membership.id,
        name: membership.display_name,
        is_user: membership.user?,
        avatar_url: membership_avatar_url(membership),
        bubble_class: typing_bubble_class(membership),
      })
    end

    # 流式 chunk 广播到 typing indicator（不更新 message bubble）
    def broadcast_stream_chunk(room, content:, membership_id:)
      broadcast_to(room, {
        type: "stream_chunk",
        membership_id: membership_id,
        content: content,
      })
    end

    # 流式完成信号
    def broadcast_stream_complete(room, membership_id:)
      broadcast_to(room, {
        type: "stream_complete",
        membership_id: membership_id,
      })
    end
  end
end
```

```ruby
# app/services/room/run_executor.rb
def execute!
  broadcast_typing_start
  
  # 流式生成，chunks 发送到 typing indicator
  content = generate_response(prompt_messages)
  
  # 生成完成后，原子创建 message
  @message = create_final_message(content)  # 触发 Turbo Stream append
  
  broadcast_typing_stop
  finalize_success!
end

def generate_response(prompt_messages)
  full = +""
  client.chat(messages: prompt_messages) do |chunk|
    full << chunk
    # 流式内容发送到 typing indicator，不更新任何 message
    RoomChannel.broadcast_stream_chunk(room, content: full, membership_id: speaker.id)
  end
  full
end
```

```javascript
// app/javascript/controllers/room_channel_controller.js
export default class extends Controller {
  static targets = ["typingIndicator", "typingAvatar", "typingBubble", "typingName", "typingContent"]
  
  handleMessage(data) {
    switch (data.type) {
      case "typing_start":
        this.updateTypingIndicatorStyle(data)
        this.showTypingIndicator()
        break
      case "typing_stop":
        this.hideTypingIndicator()
        break
      case "stream_chunk":
        // 流式内容显示在 typing indicator 中
        this.typingContentTarget.textContent = data.content
        break
      case "stream_complete":
        this.typingContentTarget.textContent = ""
        // Message 会通过 Turbo Stream append 自动添加到 DOM
        break
    }
  }
}
```

**禁止模式（会导致 race condition）：**

```ruby
# ❌ 错误：先创建 placeholder，再通过 streaming 更新
def execute!
  @message = create_placeholder_message  # 空 content
  broadcast_typing_start
  
  client.chat(messages: prompt_messages) do |chunk|
    @message.content += chunk
    @message.broadcast_stream_chunk(chunk)  # Race condition!
  end
  
  @message.save!
  @message.broadcast_stream_complete  # 可能与 Turbo Stream replace 竞争
end
```

```javascript
// ❌ 错误：streaming 内容直接更新 message bubble
case "stream_chunk":
  // message 元素可能还不存在（Turbo Stream append 尚未完成）
  const messageBubble = document.getElementById(`message_${data.message_id}`)
  messageBubble.textContent = data.content  // 可能 null reference
```

**检查清单（新功能开发时）：**

- [ ] 是否将 ephemeral 状态（typing、streaming preview）与 persistent 状态（message）分离？
- [ ] Message 是否在内容完全就绪后才创建（而非 placeholder 模式）？
- [ ] 同一 room 的 JSON 事件是否统一通过单一 channel 广播？
- [ ] 前端是否使用 typing indicator 作为 streaming 容器，而非直接操作 message 元素？
- [ ] Turbo Stream 操作是否只处理最终 DOM 状态，不参与中间状态更新？

---

### 8.2 Namespaced ApplicationController 模式（命名空间控制器基类）

**设计原则**：当为控制器创建一个 namespace（例如 `Rooms`、`Settings`）时，必须创建该 namespace 下的 `ApplicationController` 基类，所有该 namespace 下的控制器都继承自这个基类。

**问题背景**：

在没有 namespace 级别基类的情况下，每个控制器都需要重复以下逻辑：
- 资源加载（如 `before_action :set_room`）
- 访问控制（如验证用户是否有权限访问该资源）
- 通用的 concerns 引入

这导致：
1. 代码重复
2. 容易遗漏权限检查，造成数据泄漏
3. 边界不清晰

**正确架构（已采用）**：

```
app/controllers/
├── application_controller.rb           # 全局基类（认证、Current.user）
├── rooms/
│   ├── application_controller.rb       # Rooms namespace 基类
│   ├── memberships_controller.rb       # 继承自 Rooms::ApplicationController
│   ├── settings_controller.rb          # 继承自 Rooms::ApplicationController
│   ├── prompt_previews_controller.rb   # 继承自 Rooms::ApplicationController
│   └── messages/
│       └── swipes_controller.rb        # 继承自 Rooms::ApplicationController
└── settings/
    ├── application_controller.rb       # Settings namespace 基类
    ├── characters_controller.rb        # 继承自 Settings::ApplicationController
    └── llm_providers_controller.rb     # 继承自 Settings::ApplicationController
```

**Namespace ApplicationController 实现**：

```ruby
# app/controllers/rooms/application_controller.rb
module Rooms
  class ApplicationController < ::ApplicationController
    include RoomScoped  # 加载 @room，验证访问权限
  end
end

# app/controllers/settings/application_controller.rb
module Settings
  class ApplicationController < ::ApplicationController
    before_action :require_administrator  # 管理员权限验证
  end
end
```

**Namespace 下控制器继承**：

```ruby
# ✅ 正确：继承自 namespace 的 ApplicationController
class Rooms::PromptPreviewsController < Rooms::ApplicationController
  # @room 已经加载并验证权限
  def create
    builder = PromptBuilder.new(@room, ...)
    # ...
  end
end

# ❌ 错误：直接继承 ApplicationController
class Rooms::PromptPreviewsController < ApplicationController
  include RoomScoped  # 每个控制器都要重复引入
  # 容易遗漏，导致权限问题
end
```

**核心原则**：

| 原则 | 说明 |
|------|------|
| **单一职责** | Namespace ApplicationController 只处理该 namespace 的公共逻辑 |
| **强制继承** | 所有 namespace 下的控制器必须继承自对应的 ApplicationController |
| **资源边界** | 资源加载和权限验证在基类中完成，子控制器无需关心 |
| **明确依赖** | 通过 `include Concern` 明确依赖关系 |

**检查清单（新建 namespace 控制器时）**：

- [ ] 该 namespace 是否已有 `ApplicationController`？如无，先创建
- [ ] 新控制器是否继承自 namespace 的 `ApplicationController`？
- [ ] 公共逻辑（资源加载、权限验证）是否在基类中？
- [ ] 是否有重复的 `before_action` 可以提取到基类？

**已有 Namespace 基类**：

| Namespace | 基类位置 | 主要职责 |
|-----------|---------|---------|
| `Rooms` | `app/controllers/rooms/application_controller.rb` | 加载 `@room`，验证房间访问权限 |
| `Settings` | `app/controllers/settings/application_controller.rb` | 验证管理员权限 |

---

### 8.3 Typing Indicator 动态样式

**问题：** 打字指示器需要根据正在输入的角色动态改变位置、头像和颜色。

**解决方案：** 在 `broadcast_typing` 时携带完整的样式信息，前端根据这些信息动态更新 typing indicator：

```ruby
# 后端广播时包含样式信息
def broadcast_typing(room, membership:, active:)
  broadcast_to(room, {
    type: active ? "typing_start" : "typing_stop",
    membership_id: membership.id,
    name: membership.display_name,
    is_user: membership.user?,           # 用于决定位置（chat-start/chat-end）
    avatar_url: membership_avatar_url,   # 用于显示正确的头像
    bubble_class: typing_bubble_class,   # 用于显示正确的气泡颜色
  })
end
```

```javascript
// 前端根据样式信息更新 typing indicator
updateTypingIndicatorStyle(data) {
  // 位置：用户在右侧，AI 在左侧
  const container = this.typingContainerTarget
  container.classList.toggle("chat-start", !data.is_user)
  container.classList.toggle("chat-end", data.is_user)
  
  // 头像
  this.typingAvatarTarget.src = data.avatar_url
  
  // 气泡颜色
  this.typingBubbleTarget.className = `chat-bubble ${data.bubble_class}`
  
  // 名称
  this.typingNameTarget.textContent = data.name
}
```

**关键点：**
- 样式信息在后端计算，确保与实际消息样式一致
- 前端只负责应用样式，不做业务逻辑判断
- 头像 URL 使用 signed URL 确保安全性
