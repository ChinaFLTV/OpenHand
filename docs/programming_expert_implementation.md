# 编程专家（Programming Expert）模板 — 实现原理文档

## 1. 目标

在 OpenHand 中新增「编程专家」对话模板，对标 Cursor Agent Mode，提供：

- 自主编程 Agent 循环（研究→方案→实现→验证）
- 19 个内置工具（原有 15 + 新增 4）
- Cursor 级的代码搜索、LSP 智能、Git 感知、诊断闭环

## 2. 架构总览

```
┌──────────────── 模板层 ────────────────┐
│  AiPromptTemplateRepository            │
│   └─ programming_expert 模板           │
│       ├─ system_instructions.md        │
│       ├─ developer_instructions.md     │
│       └─ compression_summary_instr...  │
│   (Fallback: programming_expert_       │
│    prompts.dart const strings)         │
└────────────────────────────────────────┘
         │ loadBundle()
         ▼
┌──────────────── 工具层 ────────────────┐
│  AiToolRegistry                        │
│   ├─ lightweightOnly()  ← 4 new tools │
│   └─ withServiceDependencies()         │
│                                        │
│  AiToolRuntimeService                  │
│   ├─ _builtinTools (19 个定义)         │
│   ├─ _hookToolName (19 个映射)         │
│   └─ dispatch → AiTool.execute()       │
└────────────────────────────────────────┘
         │
         ▼
┌─────── 新增工具实现 ──────────────────┐
│  AiCodebaseSearchTool  (多信号搜索)    │
│  AiLspTool             (真实 LSP)     │
│  AiGitTool             (只读 Git)     │
│  AiDeleteFileTool      (安全删除)     │
│  AiReadLintsTool       (诊断分析)     │
└────────────────────────────────────────┘
```

## 3. 新增 / 改动文件清单

| 文件 | 动作 | 说明 |
|------|------|------|
| `assets/prompts/programming_expert/system_instructions.md` | **新增** | Agent 系统指令：角色、四阶段工作流、安全规则 |
| `assets/prompts/programming_expert/developer_instructions.md` | **新增** | 工具使用策略（每个工具的调用规范） |
| `assets/prompts/programming_expert/compression_summary_instructions.md` | **新增** | 编程专用上下文压缩模板 |
| `lib/features/ai/service/programming_expert_prompts.dart` | **新增** | 降级常量（asset 加载失败时的 fallback） |
| `lib/features/ai/tools/ai_codebase_search_tool.dart` | **新增** | 多信号加权搜索工具 |
| `lib/features/ai/tools/ai_git_tool.dart` | **新增** | 结构化只读 Git 工具 |
| `lib/features/ai/tools/ai_delete_file_tool.dart` | **新增** | 安全文件删除工具 |
| `lib/features/ai/tools/ai_read_lints_tool.dart` | **新增** | 诊断/Lint 读取工具 |
| `lib/features/ai/tools/ai_lsp_tool.dart` | **重写** | 真实 LSP 集成（dart language-server --lsp） |
| `lib/features/ai/tools/ai_tool_registry.dart` | **修改** | 注册 4 个新工具 |
| `lib/features/ai/service/ai_tool_runtime_service.dart` | **修改** | 新增 4 个 enum 值 + hook 映射 + 工具定义 |
| `lib/features/ai/service/ai_prompt_template_repository.dart` | **修改** | 注册模板 + loadBundle case |
| `lib/features/ai/ai_session_controller.dart` | **修改** | switch 穷举 + 并行化策略 |
| `lib/app/model/ai_thread_template.dart` | **修改** | icon 映射 `code_rounded` |

## 4. 核心设计决策

### 4.1 CodebaseSearch — 多信号加权搜索

Cursor 依赖本地向量嵌入数据库做语义搜索，OpenHand 无此基础设施。

**替代方案**：三路并行信号 + 权重合并

| 信号 | 权重 | 方法 |
|------|------|------|
| 精确关键词 | +3 | 对 query 提取关键词，逐词 ripgrep |
| 组合模式 | +1 | 关键词 OR 连接 ripgrep |
| 文件名匹配 | +2 | 基于关键词生成 glob 模式 |

关键词提取：
- 过滤英/中停用词
- 拆分 camelCase（`myFunction` → `my`, `Function`）
- 拆分 snake_case（`my_function` → `my`, `function`）
- 最少 3 字符

### 4.2 LSP — 真实 dart language-server 集成

旧实现是占位符。新实现：

- 启动 `dart language-server --lsp` 子进程
- JSON-RPC 2.0 通信（Content-Length header framing）
- 会话按 workspace root 缓存，30 秒空闲自动回收
- 支持 9 种操作：goToDefinition、findReferences、hover、documentSymbol、workspaceSymbol、goToImplementation、prepareCallHierarchy、incomingCalls、outgoingCalls
- 15 秒单请求超时

### 4.3 Git — 只读安全设计

| 操作 | 命令 |
|------|------|
| status | `git status --porcelain=v2 --branch --show-stash` |
| diff | `git diff [--cached] [target] [-- file]` |
| log | `git log --oneline --graph -n {count}` |
| blame | `git blame -L{start},{end}` |
| show | `git show {target}` |
| branch | `git branch -a -vv` |
| stash_list | `git stash list` |

**关键决策**：commit/push/rebase 等写操作不在此工具中，走 Bash 工具（有权限审批流）

### 4.4 DeleteFile — 路径安全门

拒绝列表：`/System`, `/usr`, `/bin`, `/sbin`, `/etc`, `~`（home 根）, 目录

标记 `isDestructive = true` → 触发权限 hook 的审批流

### 4.5 ReadLints — 诊断闭环

- 自动检测 pubspec.yaml → `flutter analyze` / `dart analyze`
- 60 秒超时
- 支持路径范围限定

## 5. Prompt 设计

### 系统指令（system_instructions.md）

- **角色定义**：自主编程 Agent，持续工作直到任务完全解决
- **四阶段工作流**：Research → Synthesis → Implementation → Verification
- **搜索策略**：CodebaseSearch → Grep → Glob → Read 递进
- **代码质量**：不引入新 lint、先读后改、精确匹配替换
- **安全规则**：不修改环境变量、不安装全局包、不运行危险命令

### 开发者指令（developer_instructions.md）

每个工具的详细使用策略，匹配 Cursor 的工具调用纪律：
- Edit：要求 3 行上下文、精确匹配
- Bash：标注是否读写命令
- CodebaseSearch vs Grep 分工
- Git：read-only 约束
- LSP：位置精度要求

### 压缩指令（compression_summary_instructions.md）

编程场景专用的上下文压缩：Code Changes、Build & Test State、Git State 三段

## 6. 并行化策略

以下工具支持并行执行（`_isParallelizableToolCall`）：

| 工具 | 并行 | 原因 |
|------|------|------|
| CodebaseSearch | ✅ | 只读搜索 |
| Git | ✅ | 只读查询 |
| ReadLints | ✅ | 只读分析 |
| DeleteFile | ❌ | 文件变更 |

## 7. 编译验证

```
$ dart analyze lib/
Analyzing lib...  0.9s
No issues found!
```
