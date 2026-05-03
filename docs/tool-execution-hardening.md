# 工具执行加固指南（Tool Execution Hardening）

> 2026-05-09 起逐步落地：参考 [Claude Code](https://github.com/anthropics/claude-code) 子进程沙盒、可观测性、可中断性的工程实践，结合 OpenHand 桌面版 Flutter 架构特点，对**工具调用 / MCP 调用 / 技能执行**等所有最终落到子进程派生与外部 IO 的链路做安全加固与可观测性增强。本文是阶段性总览与操作指南。

---

## 一、问题域

OpenHand 的"工具调用"链路长、入口多：

```
模型流式输出 → DSML / OpenAI 协议解析 → AiSessionController._executeSingleToolCall
              → AiToolRuntimeService.execute（builtin / mcp / skill 三路）
                ├─ Builtin Bash → AiBashToolService.execute → Process.start
                ├─ Builtin ReadLints / Git → AiReadLintsTool / AiGitTool → Process.start
                ├─ MCP stdio → McpToolDiscoveryService → Process.start (per call)
                └─ Skill → 纯文本读取（v1）/ 脚本执行（roadmap）
```

历史问题：

1. **不可观测** — 同时跑多个工具调用时无法看到"现在有谁在跑、哪个 pid、运行多久了"。
2. **不可独立中断** — `_sessionCancelHandlers[sessionId]` 是 per-session 粒度，并发的工具调用要么都被取消、要么都被保留，无法只杀其中一个。
3. **后台进程残留** — `Process.run(...).timeout(...)` 只解开 Dart Future、不杀子进程；`runProcessWithTimeout` 已经修过这一类问题（hard SIGKILL on timeout），但**没有覆盖运行时取消路径**：用户点 stop，cancel 信号到达 Bash 工具内部后才发 SIGTERM，外面看起来"按了立刻停"，实际可能让 awk/python 子孙进程多活几百毫秒。
4. **设置缺失** — 用户无法自定义"输出截断阈值 / SIGKILL 升级宽限期 / 工具最大并发"等系统级安全参数。

---

## 二、与 Claude Code 的对照

| 维度 | Claude Code 做法 | OpenHand 现状 / 目标 |
|------|------------------|---------------------|
| 子进程派生 | `child_process.spawn` + `tree-kill` | `Process.start`（已有）+ 进程组 kill（roadmap） |
| 任务注册表 | `AppState.tasks` + `LocalShellTaskState` | ✅ `AiToolExecutionRegistry` 单例（v1 已上线） |
| Kill 接口 | `killTask(taskId)` → `treeKill(pid, SIGKILL)` | ✅ `cancelToolCall(id)` / `cancelSession(id)` |
| 升级语义 | 任务前台 SIGTERM→可选后台化；后台超 768MB → SIGKILL | Bash: SIGTERM→500ms→SIGKILL（已有） |
| 命令准入 | 黑名单 regex + tree-sitter AST 白名单 | 已有 `AiDenyCommandRule` 黑名单；AST 白名单（roadmap） |
| 大输出 | `TaskOutput` 文件溢出 + 5MB 阈值 | 已有 `_appendChunk` 截断 + `maxToolOutputChars` budget |
| 停滞检测 | 5s 轮询 + 45s 无增长 + interactive prompt 启发式 | （roadmap） |
| MCP 连接 | SDK 长连接 + 401 自动刷新 | 当前 per-call fork（roadmap：连接池） |

> v1 落地的是**"注册中心 + 级联终止"**这一对最高 ROI 的能力，其余项按使用反馈分批跟进。

---

## 三、v1 已落地的核心能力

### 3.1 `AiToolExecutionRegistry`（[lib/features/ai/service/ai_tool_execution_registry.dart](../lib/features/ai/service/ai_tool_execution_registry.dart)）

应用单例、`ChangeNotifier`，提供：

```dart
register({toolCallId, sessionId, kind, displayName, killer?})
attachPid(toolCallId, int pid)
attachKiller(toolCallId, Future<void> Function() killer)
unregister(toolCallId)
cancelToolCall(toolCallId)
cancelSession(sessionId)
get activeRecords -> List<AiToolExecutionRecord>  // 不可变快照
get lifetimeCount -> int
```

`AiToolExecutionRecord` 字段：`toolCallId / sessionId / kind / displayName / startedAt / pid?`，附 `Duration get elapsed`。

### 3.2 `AiToolRuntimeService.execute` 自动登记 / 反注销

- 在 hook 之后、`dispatchOnce` 之前 register；
- 整段 dispatch + postHook 包在 `try / finally` 中，无论成功 / 失败 / 异常都会反注销，避免幽灵记录；
- 任何 `source`（builtin / mcp / skill）都登记，便于 UI 一致展示。

### 3.3 `AiBashToolService` 一次性派生路径回填 pid + killer

- `execute(...)` 新增 `String? toolCallId` 入参；
- `Process.start` 成功后立即 `attachPid` + `attachKiller(() => _killProcess(process))`；
- killer 直接复用 Bash 工具内部已经验证过的 SIGTERM→500ms→SIGKILL 升级逻辑，不重复造轮子。

### 3.4 `AiSessionController.stopResponding` 级联终止

- 用户点击"停止响应"时，除了原有的 stop signal + per-session cancel handler，**额外** `unawaited(registry.cancelSession(sessionId))`；
- 即使 stream 还没解开 cancel Future、即使 Bash 工具的 `cancelSignal.then` 还没触发，子进程也会立即收到 OS 级信号；
- 这一步是"根治后台残留"的关键。

---

## 四、运行时观察

代码侧消费示例（UI 后续可接入）：

```dart
final reg = AiToolExecutionRegistry.instance;
reg.addListener(() {
  for (final rec in reg.activeRecords) {
    print('[${rec.kind.name}] ${rec.displayName} '
          'pid=${rec.pid} elapsed=${rec.elapsed.inSeconds}s');
  }
});

// 用户从工具卡片右上角点 X：
await reg.cancelToolCall(card.toolCallId);
```

---

## 五、下一阶段路线图

| 阶段 | 工作项 | 核心改动 |
|------|--------|----------|
| **v2 — UI 集成** | 工具卡片右上角"独立 Stop"按钮、设置页"运行中工具调用"列表 | Listen `registry`，在 `_ToolCallBody` 里加按钮调用 `cancelToolCall` |
| **v2 — Persistent Bash 接管** | 持久 shell 路径也支持 attachKiller | 让 `_executeWithPersistentSession` 把 `_killProcess(session.process)` 注册为 killer，命中即 close session |
| **v2 — Lints / Git / safe_subprocess** | 所有内置 Process.start 路径都接入 registry | 让 `runProcessWithTimeout` 接受 `toolCallId` 可选参数，自动 attach |
| **v3 — 进程组 kill** | POSIX 上派生时入新会话（`setsid` 包装） | `_startProcess` 在 macOS / Linux 上用 `setsid -f bash -lc ...`；kill 时 `Process.killPid(-pid, ...)` 杀整个组 |
| **v3 — MCP 连接池** | stdio MCP server 长连接 + 401 自愈 | `_StdioConnectionPool` 替代 per-call fork |
| **v3 — 设置项** | `subprocessGracefulShutdownMs` / `bashOutputMaxBytes` / `maxConcurrentTools` | 沿袭 9 步参数化流程：snapshot → store → controller → runtime context → home → consumer → propagation → l10n × 7 → settings_view |
| **v4 — AST 命令准入** | bash AST 白名单解析 | 自实现轻量 AST 或迁 `bash_parser` 包；fail-closed |
| **v4 — 停滞检测** | 5s 轮询 + 45s 无新输出 + interactive prompt 启发式 | 套在 `_BashExecution` 顶层，触发后通过 `onUpdate` 推 stall warning |

---

## 六、提示词侧约束（保持 Claude-style 高效结构）

任何后续给模型的工具相关提示文本必须遵守：

```
# {ToolName}
Description: <一句话>
Hard rules:
- <一行约束>
- <一行约束>
Inputs: <参数表，每行 ≤ 80 列>
Outputs: <语义>
Failure modes: <列表>
```

**禁止**长段落散文、禁止"This tool can be used to ..." 罗嗦开头、禁止重复说明同一约束。

---

## 七、变更点速查

| 文件 | 改动类型 |
|------|---------|
| [lib/features/ai/service/ai_tool_execution_registry.dart](../lib/features/ai/service/ai_tool_execution_registry.dart) | 新增 |
| [lib/features/ai/service/ai_tool_runtime_service.dart](../lib/features/ai/service/ai_tool_runtime_service.dart) | register/unregister + try/finally |
| [lib/features/ai/service/ai_bash_tool_service.dart](../lib/features/ai/service/ai_bash_tool_service.dart) | `toolCallId` 入参 + attachPid/attachKiller |
| [lib/features/ai/tools/ai_bash_tool.dart](../lib/features/ai/tools/ai_bash_tool.dart) | 把 `context.toolCall.id` 透传给 service |
| [lib/features/ai/ai_session_controller.dart](../lib/features/ai/ai_session_controller.dart) | `stopResponding` 级联调用 `cancelSession` |

---

## 八、本文档维护责任

每完成一个 roadmap 项后追加一节"vX 落地说明"，**不要**改写已交付章节。

---

## 九、v2 落地说明（2026-05）

本轮交付以下 roadmap 项：

### 9.1 持久 Bash 会话接入登记中心
* `_executeWithPersistentSession` 增加 `String? toolCallId` 可选参数，由 `execute` 透传。
* 拿到 `_PersistentBashSession` 后将 `session.process.pid` 与 `() => _closePersistentSession(sessionId)` 闭包登记到 registry；UI 触发 `cancelToolCall` 即关闭整个 shell，下次同 sessionId 的 bash 调用经 `_ensurePersistentSession` 自动重建，**不影响**后续命令执行（lazy respawn）。
* 设计权衡：未尝试 SIGINT 当前前台命令的精细做法 —— 我们的持久 shell 是非交互模式（`bash` 无 `-i`），SIGINT 行为不稳定；直接 close + 重建更可预期。

### 9.2 MCP stdio 接入 per-call kill
* `McpToolDiscoveryService.callTool` 抽象签名加 `String? toolCallId`，`DefaultMcpToolDiscoveryService.callTool` 与 `_callToolOverStdio` 同步扩展。
* `_StdioSession` 暴露 `process` 只读 getter；stdio 路径在握手成功后将 pid + `() => session.close()` 登记到 registry。`session.close()` 内部已实现 stdin.close → 等待 exit → 超时 SIGKILL，复用既有路径。
* HTTP / SSE 协议不派生子进程，仍依赖外层 `_toolCallTimeout` 自然超时，故无需登记 killer（registry 默认 no-op）。
* `AiToolRuntimeService._executeMcpTool` 透传 `toolCall.id`。

### 9.3 工具卡片独立 Stop 按钮
* 新增 `_ToolCancelButton`（[lib/features/home/_home_tool_call_widgets.dart](../lib/features/home/_home_tool_call_widgets.dart)）：subscribe `AiToolExecutionRegistry`，仅当 `recordOf(toolCallId) != null` 时显现红色 Stop 图标 chip；点击只杀本调用。
* 显示态：常态 `stop_circle_outlined` + `errorContainer` 底；点击进入 hourglass 占位避免重复触发，结束后随 registry 反注销自动隐藏。
* 与全局"停止响应"区别：本按钮**不**清空 streaming 状态、**不**触发 plan-approval 重置；仅向 registry 发起单点取消，并行兄弟工具继续执行。
* 新增 l10n key `tlCallStopRequest`（7 个 ARB 同步更新 + `flutter gen-l10n` 重生成）。

### 9.4 变更点

| 文件 | 改动 |
|------|------|
| [lib/features/ai/service/ai_bash_tool_service.dart](../lib/features/ai/service/ai_bash_tool_service.dart) | 持久 session 路径 attachPid/attachKiller |
| [lib/features/mcp/service/mcp_tool_discovery_service.dart](../lib/features/mcp/service/mcp_tool_discovery_service.dart) | callTool 加 toolCallId、stdio 路径登记 + `_StdioSession.process` getter |
| [lib/features/ai/service/ai_tool_runtime_service.dart](../lib/features/ai/service/ai_tool_runtime_service.dart) | _executeMcpTool 透传 toolCall.id |
| [lib/features/home/_home_tool_call_widgets.dart](../lib/features/home/_home_tool_call_widgets.dart) | 新增 `_ToolCancelButton` |
| [lib/features/home/openhand_home_page.dart](../lib/features/home/openhand_home_page.dart) | import registry |
| [lib/l10n/*.arb](../lib/l10n/) × 7 | 新增 `tlCallStopRequest` |

### 9.5 暂未交付（继续保留在路线图，理由说明）
* **v2 设置页"运行中工具调用"列表**：可观测面板属于增量 UX，等首批用户反馈再设计交互结构。
* **v2 ReadLints / Git / safe_subprocess 全量接入 registry**：当前 `runProcessWithTimeout` 已具备硬超时 + SIGKILL 兜底，对 lint/git 等短命令"必须能手动中止"的优先级较低；后续会通过给 `runProcessWithTimeout` 增加 `String? toolCallId` 可选参数 + 默认调用方批量补丁的方式一次性吞掉。
* **v3 进程组 kill / MCP 连接池 / 设置项参数化 / v4 AST 准入 / 停滞检测**：保持原计划，不在本轮交付。

---

## 十、v2/v3/v4 续接落地说明（2026-05 后续）

### 10.1 safe_subprocess 透传 toolCallId（v2 收尾）
* `runProcessWithTimeout` 新增可选 `String? toolCallId`：非空时 `Process.start` 后立即 `attachPid` + `attachKiller`（SIGTERM → 500ms 宽限 → SIGKILL）。HTTP/Dart 工具不传即保持无副作用。
* `AiReadLintsTool`：`_runAnalyze` 接 `toolCallId` 参数，从 `dispatchInput` 拿到调用 ID 注入。
* `AiGitTool`：`_executeGitOperation`/`_run` 全量改用 `runProcessWithTimeout`，去掉直接 `Process.start`，所有 8 个 `_run(...)` 调用点都在闭包内拿到 `toolCallId`，工具用户能在卡片点 Stop 立即终止 git。
* MCP stdio 之外所有内建工具的派生子进程因此都进入登记中心。

### 10.2 进程组 kill：setsid 包装（v3）
* 直接通过外部 `setsid` 二进制（`/usr/bin/setsid` / `/usr/local/bin/setsid` / `/opt/homebrew/bin/setsid` / `/bin/sh -lc 'command -v setsid'`）派生 bash，让 bash 成为新进程组的 leader，pid == pgid。
* `_setsidProbe` 静态缓存探测结果，未命中 setsid 时 graceful 降级为原生派生路径（与 Windows 一致）。
* `_processGroupLeaders` 记录所有以 leader 身份派生的 pid。
* `_killProcess` 检测到 leader 时改走 `_sendSignalToProcessGroup(pid, 'TERM')`，等 500ms 仍存活再 `KILL`，等价于 `kill -- -PGID`，保证 bash 创建的子孙进程链一并结束。

### 10.3 5s/45s 停滞监控 + 交互式 prompt 启发式（v4）
* `BashToolExecutionUpdate` 新增 `String? stallWarning` 字段。持久 + 一次性两个执行路径都内嵌 `Timer.periodic(5s)` 看 `lastOutputAtMs`：超过 45 秒无新增 stdout/stderr 即触发一次告警 update。
* 命中条件后再用 `_interactivePromptHeuristic`（覆盖 `(y/n)` / `Continue?` / `password:` / `Are you sure?` / `Press <Enter> to continue` 等）扫描末尾 1KB stdout/stderr，命中则把匹配片段拼进警告："已 45s 无新输出，疑似在等待交互式输入：…"。
* `AiSessionController` onUpdate 把 `stallWarning` 透传到工具消息 metadata `tool_execution_stall_warning`；`_ToolCallBody` running 状态下显示 "可能停滞" chip + Tooltip 原文，命令重新有输出后 `stallWarningEmitted` 复位、警告自动消失。

### 10.4 设置页观测面板（v2）
* `_settings_active_tool_calls.dart`：订阅 `AiToolExecutionRegistry`，按行展示每个调用的 displayName / kind / pid / sessionId / elapsed，提供独立 Stop。
* Active records 为空时不起 1s ticker，避免空转重绘。
* 插在 `_SettingsSection.activeToolCalls`（AI 模型与内建工具之间），便于调试和"全局停止"后验证所有项是否都被迫中止。
* 7 份 ARB 同步新增 `settingsActiveToolCallsTitle/Body/Empty/Cancel`。

### 10.5 设置项参数化（v3，已落地）
`subprocessGracefulShutdownMs`（100-5000ms，默认 500）、`bashOutputMaxBytes`（16000-4000000，默认 200000）、`maxConcurrentTools`（1-64，默认 8）三个参数已走完 9 步参数化流程：snapshot defaults+ctor+field+copyWith → settings_store read clamp+write → settings_controller 字段/getter/`updateXxx`/_snapshot/_applySnapshot → ai_session_runtime_context 字段+toJson → openhand_home_page 两个 ctor 站点 + reactive cache key list → 消费方接通：`AiBashToolService.maxCapturedCharacters` 由 static const 转为公有可变实例字段；`safe_subprocess.dart` 新增顶层 `safeSubprocessDefaultGracefulShutdownMs` 全局变量，所有不显式传 `gracefulShutdownMs` 的 `runProcessWithTimeout` 调用方自动跟随 → `AiSessionController._captureLatestRuntimeContext` 把两值分别下放到上述两处；`maxConcurrentTools` 当前留作 schema，后续在批量调度层接入 → 7 份 ARB Label/Body/Invalid + `flutter gen-l10n` → `_settings_active_tool_calls.dart::_ToolHardeningParamsPanel`：3 行 TextField + Save 按钮 + 范围错误提示，叠在观测面板下方；保存反馈复用全局 `saveSuccessSignal` HighlightPulse。


