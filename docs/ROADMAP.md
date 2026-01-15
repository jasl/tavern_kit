# TavernKit Gem Roadmap

本文档定义 TavernKit（Ruby gem）的发布前路线图，基于 [FEATURE_COMPARISON.md](FEATURE_COMPARISON.md) 的功能对比分析。

> **定位**：TavernKit 是一个 **Prompt Builder 库**，专注于构建高质量的 AI 聊天 prompt，不包含 LLM 通信或 UI 功能。

---

## 发布策略

```
Phase 1: Pre-release Polish (当前)
    ↓
v1.0.0 Release
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

**目标**：完成细碎但重要的功能，准备 v1.0 发布。

### 1.1 必须完成 (Must Have)

| 任务 | 优先级 | 状态 | 说明 |
|------|--------|------|------|
| **Macro Engine 2.0 完善** | P0 | ⚠️ | 确保与 ST MacroEngine 行为一致 |
| ├─ `{{space}}` / `{{space::N}}` | | ❌ | MacroEngine-only 工具宏 |
| ├─ `{{newline::N}}` | | ❌ | 多换行宏 |
| └─ `\{` / `\}` 转义 | | ✅ | 已实现 |
| **Provider Dialect 完善** | P0 | ⚠️ | |
| ├─ Anthropic `cache_control` | | ❌ | 成本优化，用户有需求 |
| └─ 验证所有 dialect 输出 | | 🔄 | 确保符合各 provider API |
| **文档与测试** | P0 | 🔄 | |
| ├─ 更新 README.md | | 🔄 | 反映当前 API |
| ├─ 完善 YARD 文档 | | 🔄 | 关键类的文档注释 |
| └─ 补充 conformance tests | | 🔄 | 与 ST 行为对齐测试 |

### 1.2 体验提升 (UX Improvement)

| 任务 | 优先级 | 状态 | 说明 |
|------|--------|------|------|
| **错误信息改进** | P1 | 🔄 | |
| ├─ 更清晰的 parse 错误 | | 🔄 | Character card 解析失败时 |
| └─ Macro 展开错误定位 | | 🔄 | 指出问题宏的位置 |
| **CLI 改进** | P1 | ⚠️ | |
| ├─ `--verbose` 模式 | | 🔄 | 详细的调试输出 |
| └─ 彩色输出 | | 🔄 | 提升可读性 |

### 1.3 代码审计清单

- [ ] 移除所有 `# TODO` 和 `# FIXME` 注释或转为 issue
- [ ] 检查所有 public API 的文档完整性
- [ ] 审查 deprecation warnings
- [ ] 统一代码风格（RuboCop clean）
- [ ] 依赖版本锁定审查
- [ ] 性能热点检查（大 lorebook 场景）
- [ ] 安全审计（用户输入处理）

---

## v0.1.0 Release Checklist

- [ ] 所有 P0 任务完成
- [ ] 测试覆盖率 > 90%
- [ ] CHANGELOG.md 更新
- [ ] README.md 包含完整使用示例
- [ ] rubygems.org 发布准备
- [ ] GitHub release tag

---

## Phase 2: Memory & RAG

**目标**：实现 Memory 和 RAG 功能，对齐 ST/RisuAI 核心能力。

### 2.1 Knowledge Provider Interface

```ruby
# 设计目标：TavernKit 提供接口，用户实现检索逻辑
class TavernKit::KnowledgeProvider
  def retrieve(query:, messages:, k:, filters: {})
    # 返回 [{ content:, metadata:, score: }]
    raise NotImplementedError
  end
end
```

| 任务 | 说明 |
|------|------|
| `KnowledgeProvider` 接口定义 | 抽象的知识检索接口 |
| Builder 集成 | `knowledge_providers:` 参数 |
| 结果注入 | 作为 PromptBlock 注入 |
| 注入模板 | 支持自定义注入格式 |
| Include in WI scanning | RAG 结果参与 lorebook 扫描 |

### 2.2 Memory System

| 任务 | 说明 |
|------|------|
| **Mid-term Memory** | |
| ├─ Summarization 接口 | `summarizer:` lambda 注入 |
| ├─ 触发条件 | 消息数或 token 溢出 |
| └─ Summary block 注入 | 可配置位置 |
| **Long-term Memory** | |
| ├─ VectorStore 接口 | 向量存储抽象 |
| └─ 检索注入 | 类似 KnowledgeProvider |

### 2.3 World Info 向量匹配（可选）

- [ ] `vector_key` 字段支持
- [ ] Embedding 接口 (`embedding_fn:`)
- [ ] 与关键词匹配的混合模式

---

## Phase 3: Advanced Features

**目标**：实现高级功能，完善生态。

### 3.1 Tool Calling

```ruby
TavernKit.tools.register(
  name: "get_weather",
  description: "Get weather for a location",
  parameters: { location: { type: "string", required: true } },
  action: ->(params) { WeatherAPI.get(params[:location]) }
)
```

| 任务 | 说明 |
|------|------|
| ToolManager | 工具注册和管理 |
| ToolDefinition | 工具定义结构 |
| Provider 格式转换 | OpenAI/Anthropic tool format |
| Tool 结果注入 | 解析响应，执行工具，注入结果 |
| Stealth Tools | 对模型隐藏的内部工具 |

### 3.2 高级宏

| 宏 | 说明 | 优先级 |
|----|------|--------|
| `{{random:weighted::...}}` | 加权随机 | P2 |
| `{{eval}}` / `{{calc}}` | 表达式求值 | P3 |
| `{{#if}}` / `{{#each}}` | Handlebars 条件 | P3 (使用条件 prompt 替代) |

### 3.3 格式支持

| 任务 | 说明 |
|------|------|
| CharX 导入 | `.charx` ZIP 格式 |
| CharX 导出 | 带 assets 的导出 |
| ST 备份导入 | 聊天历史 JSONL |

---

## Backlog (低优先级)

以下功能不在近期计划内，但已记录：

| 功能 | 说明 | 参考 |
|------|------|------|
| Legacy 宏 (`<USER>`) | 故意不实现 | 使用 `{{user}}` |
| `activation_regex` | Instruct mode 按模型名启用 | 小众功能 |
| OpenRouter transforms | 特殊 header 处理 | 在 HTTP client 层处理 |
| Gemini thinking mode | 扩展推理配置 | Provider 特定 |
| LLM Adapter | 可选的 LLM 集成层 | 见 main ROADMAP.md Appendix |

---

## 版本规划

| 版本 | 内容 | 预计时间 |
|------|------|----------|
| v0.1.0 | Phase 1 完成，稳定 API | - |
| v0.2.0 | Memory & RAG 基础 | v0.1 后 |
| v0.3.0 | Tool Calling | v0.2 后 |
| v0.4.0 | 如有 breaking changes | 视需要 |

---

## 参考文档

- [TAVERNKIT_BEHAVIOR.md](TAVERNKIT_BEHAVIOR.md) - 行为规范
- [COMPATIBILITY_MATRIX.md](COMPATIBILITY_MATRIX.md) - 兼容性矩阵
- [SILLYTAVERN_DIVERGENCES.md](SILLYTAVERN_DIVERGENCES.md) - 已知差异
- [CCv3_UNIMPLEMENTED.md](CCv3_UNIMPLEMENTED.md) - CCv3 未实现功能
- [../FEATURE_COMPARISON.md](FEATURE_COMPARISON.md) - 功能对比总表
- [Main ROADMAP.md](../ROADMAP.md) - 详细开发历史
