# Playground Roadmap

本文档定义 Playground（Rails app）的发布前路线图，基于 [FEATURE_COMPARISON.md](../FEATURE_COMPARISON.md) 的功能对比分析。

> **定位**：Playground 是基于 TavernKit 的现代化 SillyTavern 替代品，专注于多用户、实时协作的 AI 角色扮演体验。

---

## 发布策略

```
Phase 1: Pre-release Polish (当前)
    ↓
v1.0.0 Release (Public Beta)
    ↓
Phase 2: Memory & RAG
    ↓
v1.1.0 Release
    ↓
Phase 3: Advanced Features
    ↓
v1.2.0+ Releases
```

---

## Phase 1: Pre-release Polish

**目标**：完成细碎但重要的功能，准备公开测试。

### 1.1 必须完成 (Must Have)

| 任务 | 优先级 | 状态 | 说明 |
|------|--------|------|------|
| **Chat Hotkeys** | P0 | ⚠️ | 显著提升使用体验 |
| ├─ `Left/Right` Swipe | | ⚠️ | 部分实现 |
| ├─ `Ctrl+Enter` Regenerate | | ⚠️ | |
| ├─ `Escape` Stop generation | | ❌ | 需要 stop endpoint |
| └─ `Up` Edit last message | | ❌ | |
| **Stop Generation** | P0 | ❌ | `POST /conversations/:id/stop` |
| **Generation Status UI** | P0 | ✅ | typing indicator + status badge |
| **Error Handling** | P0 | ⚠️ | |
| ├─ LLM API 错误展示 | | ⚠️ | toast 提示 |
| └─ 重试机制 | | ❌ | 失败后重试按钮 |

### 1.2 体验提升 (UX Improvement)

| 任务 | 优先级 | 状态 | 说明 |
|------|--------|------|------|
| **Conversation Export** | P1 | ❌ | |
| ├─ JSONL 导出 | | ❌ | 可重新导入 |
| └─ TXT 导出 | | ❌ | 可读文本 |
| **热键帮助** | P1 | ❌ | 显示可用快捷键 |
| **Mobile 优化** | P1 | ⚠️ | |
| ├─ 触摸手势 | | ❌ | swipe 等 |
| └─ 响应式布局修复 | | ⚠️ | 小屏幕适配 |
| **Disable auto-mode on typing** | P2 | ❌ | ST 行为对齐 |

### 1.3 数据管理

| 任务 | 优先级 | 状态 | 说明 |
|------|--------|------|------|
| **Preset 管理** | P1 | ⚠️ | |
| ├─ Preset 列表页 | | ⚠️ | 基础实现 |
| ├─ Preset 编辑页 | | ⚠️ | |
| └─ Preset 导入/导出 | | ❌ | ST preset JSON |
| **Character 批量操作** | P2 | ❌ | 批量删除/导出 |

### 1.4 代码审计清单

- [ ] 移除所有 `# TODO` 和 `# FIXME` 注释或转为 issue
- [ ] 检查所有 Controller 的错误处理
- [ ] 审查 N+1 查询（bullet gem）
- [ ] 检查 ActionCable broadcast 竞态条件
- [ ] 安全审计（权限检查、输入验证）
- [ ] 前端 JS 代码 lint（ESLint）
- [ ] CSS/Tailwind 清理未使用样式
- [ ] 依赖安全审计（bundler-audit, brakeman）
- [ ] 测试覆盖率检查

---

## v0.1.0 Release Checklist

- [ ] 所有 P0 任务完成
- [ ] CI pipeline 绿色（tests, lint, security）
- [ ] 部署文档完善
- [ ] seeds.rb 提供示例数据
- [ ] 环境变量文档
- [ ] Docker/docker-compose 配置
- [ ] 性能基准（100+ 消息会话）

---

## Phase 2: Memory & RAG

**目标**：实现 Memory 和 RAG 功能，对齐 ST/RisuAI 核心能力。

### 2.1 RAG / Data Bank

| 任务 | 说明 | 依赖 |
|------|------|------|
| **Document Attachments** | | |
| ├─ 文档上传 UI | Message/Conversation 级别 | Active Storage |
| ├─ 文档解析 | PDF, TXT, MD | |
| └─ 文档分块 | Chunking 策略 | |
| **Vector Store** | | |
| ├─ Embedding 集成 | OpenAI/local embeddings | |
| ├─ Vector DB 适配 | pgvector / Qdrant | |
| └─ 检索服务 | top-k 相似度搜索 | |
| **Injection** | | |
| ├─ PromptBuilder 集成 | TavernKit KnowledgeProvider | |
| └─ 注入模板配置 | UI 配置 | |

### 2.2 Memory System

| 任务 | 说明 |
|------|------|
| **Conversation Summary** | |
| ├─ 自动摘要触发 | 消息数/token 阈值 |
| ├─ 摘要存储 | ConversationSummary model |
| └─ 摘要注入 | PromptBuilder 集成 |
| **Long-term Memory** | |
| ├─ 事实提取 | 从对话中提取关键信息 |
| ├─ 向量存储 | 与 RAG 共享基础设施 |
| └─ 检索注入 | 相关记忆注入 prompt |

### 2.3 UI 更新

- [ ] RAG 配置面板（Space Settings）
- [ ] 文档管理 UI
- [ ] Memory 状态显示
- [ ] 手动触发摘要

---

## Phase 3: Advanced Features

**目标**：实现高级功能，差异化竞争。

### 3.1 Tool Calling

| 任务 | 说明 |
|------|------|
| Tool 注册 UI | 配置可用工具 |
| Tool 执行引擎 | 安全沙箱执行 |
| 结果展示 | 工具调用结果 UI |
| 内置工具 | 搜索、计算等 |

### 3.2 高级采样参数

参见 [BACKLOGS.md](BACKLOGS.md#advanced-sampler-parameters-sillytavern-common-settings)

| 参数组 | 优先级 |
|--------|--------|
| `min_p`, `typical_p`, `repetition_penalty_range` | High |
| `tfs`, `mirostat`, `dry_*` | Medium |
| `top_a`, `epsilon_cutoff`, `eta_cutoff`, `xtc_*` | Low |

### 3.3 Persona 完整化

参见 [BACKLOGS.md](BACKLOGS.md#persona-bound-lorebooks)

| 任务 | 说明 |
|------|------|
| Persona Model | 从 text 字段升级为独立模型 |
| Persona 管理 UI | 创建/编辑/删除 |
| Persona Lorebooks | 关联 Lorebook |
| PromptBuilder 集成 | 处理 persona lorebooks |

### 3.4 其他功能

| 功能 | 说明 | 优先级 |
|------|------|--------|
| PWA 支持 | 离线访问、推送通知 | P2 |
| Chat Import | 导入 ST JSONL | P2 |
| Settings Search | 设置搜索 | P3 |
| Backup/Restore | 用户数据备份 | P3 |

---

## Backlog (低优先级)

以下功能不在近期计划内，已移至 [BACKLOGS.md](BACKLOGS.md)：

| 功能 | 说明 |
|------|------|
| TTS/STT | 语音合成/识别 |
| Sprites/Expressions | 角色表情系统 |
| Image Generation | SD 集成 |
| Visual Novel Mode | VN 风格展示（RisuAI 特色） |
| MCP Integration | Model Context Protocol |
| Cloud Sync | 多设备同步（非多用户） |

---

## 版本规划

| 版本 | 内容 | 预计时间 |
|------|------|----------|
| v1.0.0 | Phase 1 完成，公开 Beta | - |
| v1.1.0 | RAG 基础功能 | v1.0 后 |
| v1.2.0 | Memory System | v1.1 后 |
| v1.3.0 | Tool Calling | v1.2 后 |
| v2.0.0 | 重大功能/架构更新 | 视需要 |

---

## 技术债务

发布前需要关注的技术债务：

### 高优先级

- [ ] `chat_hotkeys_controller.js` 完善（参见 BACKLOGS.md）
- [ ] WebSocket 重连逻辑健壮性
- [ ] Large conversation 性能优化（虚拟滚动）

### 中优先级

- [ ] 统一错误处理模式
- [ ] Service Result 对象一致性
- [ ] 前端状态管理优化

### 低优先级

- [ ] 代码注释完善
- [ ] 组件拆分（大型 Stimulus controllers）

---

## 参考文档

- [PLAYGROUND_ARCHITECTURE.md](PLAYGROUND_ARCHITECTURE.md) - 架构设计
- [CONVERSATION_RUN.md](CONVERSATION_RUN.md) - Run 状态机
- [CONVERSATION_AUTO_RESPONSE.md](CONVERSATION_AUTO_RESPONSE.md) - 自动回复
- [FRONTEND_BEST_PRACTICES.md](FRONTEND_BEST_PRACTICES.md) - 前端规范
- [FRONTEND_TEST_CHECKLIST.md](FRONTEND_TEST_CHECKLIST.md) - 测试清单
- [BACKLOGS.md](BACKLOGS.md) - 完整 Backlog 列表
- [../FEATURE_COMPARISON.md](../FEATURE_COMPARISON.md) - 功能对比总表
- [../spec/ROADMAP.md](../spec/ROADMAP.md) - TavernKit Gem Roadmap
