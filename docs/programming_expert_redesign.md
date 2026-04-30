# Programming Expert v4.0 重构提案 — 对照 Warp 编程 Loop 架构

> 目标读者：OpenHand 维护者
> 状态：**研究 + 提案，未落盘**。审核后再覆盖 `assets/prompts/programming_expert/*.md`
> 参考代码：`/Users/liguanda/Public/RustProjects/warp` (commit at time of研究)

---

## 第一部分 · Warp 编程 Loop 架构深挖

### 1. 整体形态：服务端 LLM + 客户端事件源

Warp 的 LLM Loop **不在客户端**。客户端是事件消费者：

```
┌──────────────┐    SSE (AgentRunEvent)   ┌───────────────────┐
│ warp client  │ ◀───────────────────────│ warp_server (LLM) │
│  (Rust GUI)  │ ──── tool_result ──────▶│  Anthropic/OAI    │
└──────────────┘                         └───────────────────┘
```

证据：
- [`app/src/ai/agent_events/driver.rs`](file:///Users/liguanda/Public/RustProjects/warp/app/src/ai/agent_events/driver.rs) — `run_agent_event_driver` 是带指数退避 + 主动回收 (14 min) 的重连 SSE 消费者，单向接收 `AgentRunEvent`。
- 系统 Prompt 只在 **agent_sdk harness**（包装 Claude Code / Codex / Gemini CLI）时通过临时文件 `--system-prompt` 注入；主 Agent Mode 的 prompt 在服务端，源码不可见。

**对 OpenHand 的启示**：我们是**客户端 LLM Loop**（直接调 OpenAI / Claude / Qwen 等），所以必须**自己**在 prompt 里把 Warp 服务端隐式做的事写明白：planner 决策、context budget、subagent 类型化、stop condition 等。

### 2. 工具目录（client 端可执行的 Action）

来自 `app/src/ai/agent/api/convert_from.rs:626-790`：

| 类别 | 工具 | OpenHand 对应 |
|------|------|--------------|
| Shell | `RunShellCommand` / `WriteToLongRunningShellCommand` / `ReadShellCommandOutput` / `TransferShellCommandControlToUser` | `Bash`（缺：长任务 stdin 写入 / 输出读回） |
| 文件读 | `ReadFiles` | `Read` |
| 文件改 | `ApplyFileDiffs` / `EditDocuments` / `CreateDocuments` | `Edit` / `MultiEdit` / `Write` |
| 搜索 | `SearchCodebase` (语义) / `Grep` / `FileGlob` / `FileGlobV2` | `CodebaseSearch` / `Grep` / `Glob` |
| MCP | `ReadMcpResource` / `CallMcpTool` | mcp__* |
| 计算机 | `UseComputer` / `RequestComputerUse` | （缺） |
| 子 Agent | `Subagent` / `StartAgent` / `StartAgentV2` / `SendMessageToAgent` | `Task`（功能弱，只 fire-and-forget） |
| 规划 | `UpdateTodos` (TodoOperation) | `TodoWrite` |
| 互动 | `AskUserQuestion` / `SuggestPrompt` / `SuggestNewConversation` | `AskUserChoice`（只单选） |
| 上下文 | `ReadSkill` / `FetchConversation` / `ReadDocuments` | `SkillManager` |
| 评审 | `OpenCodeReview` / `InsertReviewComments` | （缺） |
| 工件 | `UploadFileArtifact` | （缺） |
| Init | `InitProject` | （缺） |

**Warp 独有、对编程极有价值的能力**：
1. **`ApplyFileDiffs`** — 一次提交多个 hunk 的统一 diff，由客户端校验 + 高亮。我们是 Edit/MultiEdit，但**没有 hunk 级粒度**。
2. **长跑 shell + 双向写入**：`RunShellCommand` 启动后续命令可继续写入 stdin，`ReadShellCommandOutput` 拉新输出。这让 Agent 能像人一样和 REPL/dev-server 交互。
3. **典型化 Subagent**（见下）。
4. **`InitProject`** — 项目首问时自动跑结构化扫描，把结果作为 system context。

### 3. 子 Agent 类型化（最被低估的差异点）

`app/src/ai/agent/mod.rs:1515-1530`：

```rust
pub enum SubagentType {
    Cli,                       // 跑外部 CLI（claude, codex, gemini）
    Research,                  // 只读探索
    Advice,                    // 给主 Agent 提建议
    ComputerUse,               // 屏幕/键鼠
    Summarization,             // 把长 conversation 压缩成纲要
    ConversationSearch { query, conversation_id },
    WarpDocumentationSearch,
    Unknown,
}
```

**关键洞察**：Subagent 不是一个泛用占位符，而是**有目标分类**。每个子任务带"我要的是什么类型的回答"。

OpenHand 现状：`Task` 工具只是"派一个子任务"，没有 type 维度。当前模板里也只是说"parallel investigation"。**这是最大可改进项之一**。

### 4. Todo 是一等公民，不是装饰

`app/src/ai/agent/todos/mod.rs`：

```rust
pub struct AIAgentTodoList {
    pending_items: Vec<AIAgentTodo>,    // {id, title, description}
    completed_items: Vec<AIAgentTodo>,
}

pub enum TodoOperation {
    UpdateTodos { todos },                // 完整重写
    MarkAsCompleted { completed_todos },  // 增量完成
}
```

Warp 的 Todo 有专门的 popup view (`todos/popup.rs` 312 行)、滚动到 in-progress 项、blocklist 历史事件钩子。它**不是 prompt 里的形式主义**，而是 UI 主线之一，每个 Action 完成都会查询/刷新。

**OpenHand 现状**：`TodoWrite` 工具存在，模板要求"≥3 步"。但**没有写明何时必须 update（每个 in_progress 完成后立即）、何时必须 mark_as_completed（不是 update_pending 重写）、in_progress 是否唯一**——这些 Warp 都通过类型分立 + UI 驱动来强制。

### 5. 消息线性化：DAG → 线性

`app/src/ai/agent/linearization.rs` (108 行) 把 `parent_agent_id` / `parent_conversation_id` 形成的 DAG 拍平成 token 流。这意味着 Warp 可以**一个会话里同时跑多 Agent，并把它们的输出融合进同一个 LLM context**，而不是简单 transcript。

OpenHand 的 `AiSessionController` 是单会话单线性，子任务结果用 markdown 块塞回；功能等价但**没有"哪些输出来自 subagent X"的元数据**——LLM 看不到这层结构。

### 6. Skill 系统：自描述 + scope 排序

`crates/ai/src/skills/`：
- `parse_skill.rs` — 解析 Markdown front-matter (`name`, `description ≤ 512 chars`)
- `skill_provider.rs` — `SkillScope` (Bundled / Home / Project)，有 `provider_rank`，本地 > 内置
- `read_skills.rs` — 启动时扫描 + 缓存
- `skill_reference.rs` — Agent 在 prompt 里看到的精简引用

Warp 把 skills 作为**冷启动注入 + ReadSkill 工具按需懒加载**两段式：列表给 LLM 看 description，需要时拉全文。

OpenHand 已有 `ai_skill_manager_tool` + `assets/prompts/...`，但**两段式装载策略没在 prompt 里明示**——LLM 不知道"我应该先看名字 list，再 ReadSkill 拉详情"。

### 7. Block Context — 把当前 IDE/Terminal 状态注入

`app/src/ai/block_context.rs` (103 行) 把当前选中的终端 block（命令 + 输出 + cwd + 错误码）作为强上下文喂给 LLM。Warp 的"问问题就基于刚才那条命令的报错"体验来源于此。

OpenHand 缺少**等价的"当前焦点上下文"**：用户提问时，LLM 不知道用户刚刚在看哪个 markdown、刚才执行的工具结果是什么。我们靠 transcript 全量回灌，token 成本高、信号弱。

### 8. Harness：把 CLI Agent 当作可替换后端

`app/src/ai/agent_sdk/driver/harness/{claude_code, codex, gemini}.rs` — 每个第三方 CLI 都封装为同一 `Harness` trait：`prepare_environment_config(working_dir, system_prompt, secrets)` + `start_session()`。系统 prompt 写到临时文件用 `--system-prompt-file` 传入，**避免 shell quoting**。

**对 OpenHand 没直接借鉴价值**（我们是直接调 LLM），但**临时文件传 prompt** 这一招值得记：当我们以后想接 codex/claude-code CLI 作为 Skill 后端，必须走这条路。

---

## 第二部分 · OpenHand 现状诊断

读 [assets/prompts/programming_expert/system_instructions.md](../assets/prompts/programming_expert/system_instructions.md) (197 行) + [developer_instructions.md](../assets/prompts/programming_expert/developer_instructions.md) (125 行)，按 Cursor / Warp 体验对比：

### 已经做对的
- ✅ Working directory 锚定 (`WD` / `PR` 别名)
- ✅ Tool-First 原则 + 反模式表（"描述 vs 调用"）
- ✅ Skill > MCP > Builtin 优先级
- ✅ TodoWrite ≥ 3 步、单 in_progress
- ✅ Plan Mode 的 ExitPlanMode 行为
- ✅ 图片附件 `<image_summary>` 协议
- ✅ Memory tone（不要"我记得你说过…"）

### 关键缺失（按影响力排序）

| # | 缺失 | 影响 | Cursor/Warp 怎么做 |
|---|------|------|--------------------|
| **1** | **没有"会话起手探查"协议** | LLM 第一轮就猜文件位置 / 框架 | Warp 用 `InitProject`；Cursor 自动读 `AGENTS.md` / `.cursorrules` + 顶层 ls |
| **2** | **Subagent 没有类型** | `Task` 沦为口号 | Warp 7 种 SubagentType 让 LLM 选明确目标 |
| **3** | **Todo 协议太软** | LLM 写完一个 in_progress 经常忘记 mark complete | Warp 强制 `MarkAsCompleted` 单独调用 |
| **4** | **没有"context budget"** | 大文件全量 Read、十轮还在搜 | Warp/Cursor 都有"先 sample 100 行 + outline，再 deep read"的范式 |
| **5** | **没有"diff 化编辑"思路** | LLM 倾向 Write 整文件覆盖 | Warp `ApplyFileDiffs` 强制 hunk 思维 |
| **6** | **Verification 弱** | "edit 完就完事" | Cursor: 每次 Edit 后自动 ReadLints；测试失败立刻进入 fix loop |
| **7** | **没 Stop Condition** | 死循环 retry 或过早交差 | 明确"3 次同错即停 + 报告"已写但**只对 lint**生效 |
| **8** | **Long-running 命令缺策略** | `flutter run` / dev server 启动会卡住 | Warp 的 long-running shell + read output 区分 |
| **9** | **没 Uncertainty 信号** | LLM 自信汇报"修好了"，其实没跑测试 | Cursor: "I haven't verified X" 强制声明 |
| **10** | **没 Atomic Change 边界** | 一个 turn 改 10 文件难回滚 | Cursor: "建议每 1-3 文件 commit 一次" |
| **11** | **错误分类粗** | timeout / denied / mismatch 同一处理 | 应区分 transient / permanent / design-error |
| **12** | **Skill 装载语义未明** | LLM 不知道何时主动 ReadSkill | Warp: "skills 列表是 description-only，详情按需 ReadSkill" |
| **13** | **没语言/框架路由** | Dart 项目里仍然 grep 大锤打钉 | Cursor: "TS/Dart/Rust → 优先 LSP" |

---

## 第三部分 · v4.0 重构方案

### 设计原则

1. **总长度控制在 +20% 以内**（v3 = 197 行 → v4 ≤ 240 行）。每次 LLM 调用都要付 token 成本。
2. **新加内容优先以表格 + 短句**，避免段落叙述。
3. **可机检约束** > 哲学指引（"必须 X" 比 "尽量 X" 强）。
4. **新增章节**：[1.5] 会话起手 / [3.5] Subagent 类型 / [4.5] Diff-thinking / [5.5] Verification / [9] Uncertainty / [10] Atomic Change。
5. **保留所有 v3 已对的部分**，只增补 + 收紧措辞。

### v4 system_instructions.md 骨架（建议覆盖结构）

```
[0]  Identity & Core Principles                    ← 保留 + 加 #8 Uncertainty Honesty
[1]  Agent Loop Protocol                            ← 保留 4 阶段，加"Stop Condition"
[1.5] Session Bootstrap (NEW)                       ← 起手必做：read AGENTS.md, ls top, 探活
[2]  Tool Invocation Rules                          ← 保留
[3]  Research Strategy                              ← 加"Context Budget" 段
[3.5] Subagent Typing (NEW)                         ← Research / Verify / Summarize / Advice
[4]  Code Quality Standards                         ← 保留
[4.5] Diff-Thinking & Edit Granularity (NEW)        ← 优先最小 Edit；3 hunks 以上用 MultiEdit
[5]  Communication Protocol                         ← 保留 + Uncertainty 标记
[5.5] Verification Loop (NEW)                       ← Edit → Read back → Lint → Test 强制
[6]  Git Protocol                                   ← 保留
[7]  Error Recovery                                 ← 加错误分类
[8]  Safety & Constraints                           ← 保留
[9]  Atomic Change Discipline (NEW)                 ← 1 turn ≤ N 文件 + commit 边界
[10] Skill Loading Protocol (NEW)                   ← list-only → ReadSkill on demand
图片附件协议                                          ← 保留
```

### 关键新增条款（草稿）

#### [1.5] Session Bootstrap — 第一轮强制行为

```
当 conversation 中尚无任何 tool_result（首轮）时，按顺序执行：
1. LS 工作目录顶层（≤1 调用，记结构）
2. 若存在 AGENTS.md / .cursorrules / README.md → Read（仅这一个文件，≤200 行）
3. 若用户问题涉及具体文件 → 先 Glob/Grep 定位，再 Read
4. 然后才能做 Edit/Write

例外：用户明确说"直接做 X"或"跳过 explore" → 跳过步骤 1-2。
```

#### [3.5] Subagent 类型（4 种，覆盖 Warp 7 种里的实用部分）

```
| Type        | 用途                       | 何时派 |
|-------------|----------------------------|--------|
| research    | 只读探索 / 多文件检索        | 不确定结构 / 需要 ≥3 处 grep |
| verify      | 跑测试 / lint / build        | 边改边验，避免主线 context 膨胀 |
| summarize   | 长输出 / 长会话 → 摘要       | 输出 >5000 字时 |
| advice      | 设计选型 / 架构权衡          | 多种实现方案需要权衡时 |

调用 Task 时必须在第一句话写明 `[type=research]` 等，便于人类审阅。
```

#### [4.5] Diff-Thinking

```
- 修改 ≤3 行 → Edit (单 hunk)
- 修改 ≥2 处不连续 → MultiEdit
- 改造 ≥30% 文件内容 / 文件 ≤50 行 → Write
- 永远先 Read 出 oldString 的精确文本（含缩进），不要凭记忆构造
- 修改后必须 Read back 修改区域 ±10 行验证
```

#### [5.5] Verification Loop

```
每次 Edit/Write/MultiEdit 后必须：
1. 读取工具返回字段确认 success（不要假设）
2. 若改的是源码 → ReadLints scope 到这些文件
3. 若 lint 报错 → 修，最多 3 轮
4. 若涉及行为改变 → 提示需要跑测试/构建（在 [10] Atomic Change 提交前）

Edit 失败 (oldString 不匹配) 的恢复：
- 第 1 次：Re-Read 同区域 ±20 行，调整 oldString
- 第 2 次：换用 MultiEdit 缩小每个 hunk
- 第 3 次：Read 全文 + Write 整文件
```

#### [9] Atomic Change Discipline

```
- 单 turn 修改 ≤5 个文件，超出时分段汇报并询问是否继续
- 修改跨越多个无关功能时，明确提示"建议拆分为 N 个 commit"
- 永远不调用 git commit 除非用户说 "commit it" / "提交"
- 写完 ≥3 文件后主动建议运行测试
```

#### [10] Skill Loading Protocol

```
你看到的 skill 列表只有 name + description 摘要。
触发条件：
- 用户问题 keyword 命中 description → ReadSkill 读完整 SKILL.md，再行动
- 用户显式 /skill_name → 直接 ReadSkill
- 自己已在该领域有方案 → 不需要 ReadSkill
- 同一 turn 不重复 ReadSkill 同一 skill
```

#### [0.8] Uncertainty Honesty（嵌入 Core Principles）

```
8. Uncertainty Honesty: 当你声称某事"已修复 / 已验证"时，必须有对应工具结果。
   未跑测试就说"应该可以了" → 必须改写为"已修改但未运行测试，建议执行 X"。
```

#### Loop Stop Condition（[1] 末尾追加）

```
循环停止条件（满足任一即停 + 报告）：
- 同一错误连续 3 次未解决
- 已修改 ≥5 文件且未验证
- 用户原始问题需要外部输入（凭据 / 设计决策）
- 工具集合不足以完成（缺 Write 等）→ 立即说明
```

### 兼容性 / 风险

- **Token 成本**：v4 估算 +35-45 行（≈ +800 tokens / 调用）。若按月 100k 次调用 × 单价 ¥0.001/1k input ≈ +¥80/月 — 可接受。
- **回归风险**：新增"Session Bootstrap" 强制 LS + Read，对"快速一句话回答"场景增加 1-2 个工具调用。需在 [1.5] 末尾加例外子句（已加）。
- **现有 OpenHand 工具不支持 SubagentType 元数据** — Phase 1 只在 prompt 层让 LLM 在 Task 描述里标 `[type=...]`，Phase 2 再扩 `ai_task_tool.dart` 加 enum 字段。

### 未来 Phase 2（代码改动，本次不做）

| 项 | 文件 | 改动 |
|----|------|------|
| Task 工具加 `subagent_type` 字段 | `lib/features/ai/tools/ai_task_tool.dart` | 加 enum + UI badge |
| Long-running shell stdin/read split | `lib/features/ai/tools/ai_bash_tool.dart` | 拆 `BashStart` / `BashWrite` / `BashRead` |
| ApplyFileDiffs 工具 | new `ai_apply_diffs_tool.dart` | 接受 unified diff，校验后 apply |
| Block context 注入 | `lib/features/ai/service/ai_prompt_builder.dart` | 把当前选中 markdown / 上一轮 tool result 摘要塞 system 段 |
| Skill 两段式装载 | `lib/features/ai/tools/ai_skill_manager_tool.dart` | 默认只返 list；`ReadSkill(name)` 才返全文 |

---

## 第四部分 · 落地步骤建议

1. **审阅本文档** — 决定哪些 v4 条款采纳 / 调整 / 否决。
2. 我根据反馈生成 **v4.0 system_instructions.md / developer_instructions.md**（compression_summary 不动）。
3. 跑一次 `flutter analyze && flutter test` 基线（无代码改动应是 0 issues + 114 tests）。
4. 灰度策略：可先把 v4 命名为 `system_instructions.v4.md` 并加 feature flag 切换，对比一周再替换。

---

**核心一句话**：Warp 的"丝滑感"来自**服务端 LLM 强 + 客户端事件源化 + 工具粒度精细（diff、long-shell、typed subagent）+ 上下文注入**。我们是客户端 LLM，必须把 Warp 服务端隐式做的工程纪律**显式写进 prompt**，并在工具层逐步对齐。
