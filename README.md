<div align="center">
  <img src="assets/branding/openhand_logo.png" alt="OpenHand Logo" width="128" />

# OpenHand

**一款面向桌面端的、可自托管的 AI 智能体工作台**

把 20+ 模型协议、可编程的工具/技能/MCP/钩子/定时任务，统一编排在一个 Flutter 原生应用里。

[![Flutter](https://img.shields.io/badge/Flutter-%3E=3.27-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart SDK](https://img.shields.io/badge/Dart-%5E3.11-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-555)](#-下载与运行)
[![Status](https://img.shields.io/badge/status-active-brightgreen)](#)
[![中文](https://img.shields.io/badge/lang-简体中文-red)](README.md)
[![English](https://img.shields.io/badge/lang-English-blue)](README.en.md)

</div>

> 🤝 **OpenHand** = Open + Hand —— 把 AI 的“双手”交还给开发者：模型自由切换、工具可插拔、提示词与会话完全本地化、所有自动化流程透明可控。

---

## 📑 目录

- [✨ 项目亮点](#-项目亮点)
- [🖼 应用截图](#-应用截图)
- [🚀 核心功能](#-核心功能)
- [🧠 内置 AI 工具集](#-内置-ai-工具集)
- [🌐 支持的模型协议](#-支持的模型协议)
- [🧩 线程模板（Thread Templates）](#-线程模板thread-templates)
- [🔌 MCP / 技能 / 钩子 / 定时任务](#-mcp--技能--钩子--定时任务)
- [⌨️ 常用快捷键](#️-常用快捷键)
- [🏗 系统架构](#-系统架构)
- [📦 下载与运行](#-下载与运行)
- [🛠 开发者指引](#-开发者指引)
- [🗂 项目结构](#-项目结构)
- [🌍 国际化](#-国际化)
- [🤝 参与贡献](#-参与贡献)
- [❓ FAQ](#-faq)
- [📜 协议](#-协议)

---

## ✨ 项目亮点

| | |
|---|---|
| 🪐 **多协议接入** | 一套 UI，连通 OpenAI / Claude / Gemini / DeepSeek / Qwen / Kimi / GLM / Grok / Ollama / vLLM / SGLang / 字节 Seed / 阶跃 / MiniMax / LongCat / JoyCode / 文心 / Meta / Mimo / 混元 等 **20+ 协议**。 |
| 🧰 **完整工具链** | 内置 25+ 工具：Bash、Read/Write/Edit、Grep（内置 ripgrep）、Glob、LSP、Git、WebFetch、WebSearch、Codebase Search、TodoWrite、Memory、Task、Notebook、Skill Manager…… |
| 🧠 **DSML 工具调用降级** | 不支持原生 function-calling 的模型自动注入 DSML 协议描述，让“裸文本模型”也能稳定执行工具链。 |
| 🛡 **桌面级安全** | 命令规则白/黑名单、外部进程统一走 `safe_subprocess` 强制超时与 `SIGKILL`，避免 macOS Apple Events 卡死输入法。 |
| 🧩 **MCP / Hooks / Crons / Skills** | 一站式管理 Model Context Protocol 服务、生命周期钩子、Cron 自动化、技能市场。 |
| 📚 **可成长的智能体** | Hermes Talker 模板 + Self-Learning 调度器，定时蒸馏会话洞察至用户档案与「自主学习」记忆。 |
| 🏎 **性能优化** | 代码块语法高亮 LRU 缓存、>120KB Markdown 体延迟解析、并行 Boot、4 MiB SSE 缓冲区、入场动画一次性追踪。 |
| 🌍 **本地优先** | 所有会话、记忆、技能、MCP 配置存储于本地 SQLite；多语言界面（中英日法德 + 繁中）。 |

---

## 🖼 应用截图

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/01-main-chat.png" alt="主聊天界面" /><br/><sub><b>主聊天 · 多模型并行</b></sub></td>
    <td align="center"><img src="docs/screenshots/02-programming-expert.png" alt="编程专家" /><br/><sub><b>编程专家 · 工作区视图</b></sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/03-hardness-engineering.png" alt="硬度工程模板" /><br/><sub><b>硬度工程 · 阶段化流水线</b></sub></td>
    <td align="center"><img src="docs/screenshots/04-mcp-servers.png" alt="MCP 服务" /><br/><sub><b>MCP 服务管理</b></sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/05-skills-market.png" alt="技能市场" /><br/><sub><b>技能市场</b></sub></td>
    <td align="center"><img src="docs/screenshots/06-settings.png" alt="设置面板" /><br/><sub><b>模型 / 协议 / 工具 / 命令规则配置</b></sub></td>
  </tr>
</table>

---

## 🚀 核心功能

### 1. 多线程会话与多模型工作台
- 并列多个会话，每个线程独立选择 **模型 / 协议 / 模板 / 工具开关**。
- 支持 **图片 / 音频 / 视频** 创作模式（按协议自动路由：OpenAI Sora、MiniMax T2V/T2A、Qwen DashScope 异步任务、GLM CogVideoX 等）。
- **会话导出**：右键线程 → 导出 JSONL，可选 role / kind 过滤、消息区间、是否包含已删除、是否美化。

### 2. 智能上下文压缩
- 仅对“模型已消费过的历史轮次”启用工具结果压缩；`Read`/`Bash` 命令体永远保留原文，避免写入死循环。
- 内置 `compression_summary_instructions.md` 模板，逐线程模板自定义。

### 3. 计划模式（Plan Approval）
- 模型先输出 **Plan** → 待用户「继续 / 好 / OK」等批准后才进入执行；批准词集合保持精确匹配，避免误触发。
- 计划面板状态会随执行进度自动切换为「执行中」「已完成」。

### 4. 自学习与记忆系统
- **Memory 工具**：`list / append / upsert_profile / update / delete`，支持标签、JSON 内容。
- **Hermes Talker** 模板 + 系统级 Cron `self_learning.hermes_talker`（默认 `*/5 * * * *`），自动扫描近 7 天会话，蒸馏出长期洞察。
- 全局 **Memory Tone Policy**：使用记忆时不说「我记得…」，自然融入回复。

### 5. 编程专家（Programming Expert）
- 内嵌 **工作区视图**：项目浏览、最近项目、文件 hover 预览、点击跳转、写命令对话框。
- 支持 **LSP 后端目录**（自动安装 / 托管），覆盖 Dart、TypeScript、Python、Rust、Go 等主流语言。
- 工具调用卡片含 **入场淡入 + 高度过渡** 动画。

### 6. 硬度工程（Hardness Engineering）
- 阶段化（Plan → Implement → Verify → Recap）流水线，自带工具亲和过滤。
- 内嵌 CLI 安装与登录助手，所有外部进程通过 `safe_subprocess` 受控执行。
- Dashboard 拆分为 13 个 `.part.dart` UI 子树，单文件可维护。

### 7. 桌面级人机协作
- **全局快捷键**：`Ctrl+P` 切换面板、`Ctrl+Enter` 发送、`@` 触发提及/技能选择。
- **Slash Command** 解析、附件粘贴、SVG 渲染、KaTeX 数学公式。
- **入场动画**：消息、工具卡片、侧栏线程统一使用 `AppearOnce` + `AppearTracker`，列表性能不受影响。

---

## 🧠 内置 AI 工具集

| 类别 | 工具 | 说明 |
|---|---|---|
| 文件 | `Read` `Write` `Edit` `MultiEdit` `LS` `Glob` `Grep`* `NotebookEdit` `DeleteFile` | `Grep` 始终调用应用内置 `vendor/ripgrep` 跨平台二进制。 |
| 代码 | `CodebaseSearch` `LSP` `ReadLints` `Git` | LSP 支持自动安装语言服务器。 |
| 执行 | `Bash` `Task` | `Bash` 经命令规则白/黑名单 + `safe_subprocess` 超时控制。 |
| 网络 | `WebFetch` `WebSearch` | 统一域名/超时配置。 |
| 智能体 | `TodoWrite` `Memory` `SkillManager` `ExitPlanMode` `AskUserChoice` | 计划/记忆/技能/确认。 |

> 模型若不支持原生 function-calling，OpenHand 会自动在系统提示末尾追加 DSML 调用规范，并禁止 `##TOOL_CALL##` / 杜撰名 / Markdown 包裹等常见幻觉形式。

---

## 🌐 支持的模型协议

| 国际厂商 | 国内厂商 | 自托管 / 私有部署 |
|---|---|---|
| OpenAI · Claude · Gemini · Grok · Meta | DeepSeek · Qwen · Kimi · GLM · 字节 Seed · 阶跃 StepFun · MiniMax · LongCat · JoyCode · 文心 Wenxin · 混元 Hunyuan · Mimo | Ollama · vLLM · SGLang |

每个协议自带：
- **模型目录预设**（最大上下文、是否支持工具调用、视觉/音频/视频能力）
- **Token 用量回传** 解析
- **流式 / 非流式** 自动适配
- **多模态 endpoint 路由**（图片 / 音频 / 视频生成）

---

## 🧩 线程模板（Thread Templates）

| 模板 | 适用场景 | 特色 |
|---|---|---|
| 🪄 **Default** | 通用聊天 | 最小工具集、上下文最干净。 |
| 💻 **Programming Expert** | 代码读写、重构、调试 | 完整工具集（Bash/LSP/Grep/Edit/...）+ 工作区视图。 |
| 🛠 **Hardness Engineering** | 复杂多阶段任务 | Plan→Implement→Verify→Recap 阶段化流水线。 |
| 💬 **Hermes Talker** | 闲聊式自学习 | `memory` + `skill_manager` + 后台 Cron 自动蒸馏长期记忆。 |

> 模板提示词位于 [assets/prompts/](assets/prompts/)，每个模板包含 `system_instructions.md`、`developer_instructions.md`、`compression_summary_instructions.md` 三件套。

---

## 🔌 MCP / 技能 / 钩子 / 定时任务

| 模块 | 入口 | 能力 |
|---|---|---|
| **MCP** | 侧栏 → MCP | 添加 stdio / SSE / WebSocket 类型的 Model Context Protocol 服务，工具自动注入会话目录。MCP 工具集庞大时支持**懒加载**模式（详见 [docs/mcp-lazy-loading.md](docs/mcp-lazy-loading.md)）。 |
| **Skills** | 侧栏 → 技能 | 内置技能市场，支持本地 Skill 包；`SkillManager` 工具供 AI 自主装载。 |
| **Hooks** | 侧栏 → 钩子 | 在会话生命周期事件（如 PostToolUse / PreCompact）执行 Shell；统一通过 `HooksExecutor`。 |
| **Crons** | 侧栏 → 定时 | Cron 表达式 + 历史清理 Worker；支持 `script` / `agent` 两种执行类型，系统级任务带锁不可删。 |
| **Memory** | 侧栏 → 记忆 | 标签化记忆条目 + 用户档案；可与 Hermes Talker 联动。 |
| **Instructions** | 侧栏 → 指令 | 全局/工作区级指令片段，注入系统提示。 |

---

## ⌨️ 常用快捷键

| 快捷键 | 功能 |
|---|---|
| `Ctrl + Enter` | 发送当前消息 |
| `Ctrl + P` | 打开/切换命令面板 |
| `@` | 在输入框中触发提及 / 技能 / 模型选择 |
| `/` | 触发 Slash 命令解析 |
| `Esc` | 取消当前对话框 / 中止流式输出 |

> macOS 上 `Ctrl` 等同 `⌃`（不是 `⌘`），避免与系统编辑快捷键冲突。

---

## 🏗 系统架构

```
┌────────────────────────────────────────────────────────────────────────────┐
│                            Flutter UI (lib/features)                       │
│  home · ai · hardness · settings · mcp · skills · memory · crons · hooks   │
└──────────────┬─────────────────────────────────────────────┬───────────────┘
               │                                             │
        ┌──────▼──────┐                              ┌───────▼────────┐
        │  Controllers │  ← Provider/ChangeNotifier  │  Renderers     │
        │  (state)     │                              │  (markdown,    │
        └──────┬──────┘                              │   highlight,   │
               │                                      │   katex, svg)  │
   ┌───────────┼───────────────────────────────┐     └───────┬────────┘
   │           │                               │             │
┌──▼──┐   ┌────▼─────┐   ┌──────────────┐   ┌─▼───────────┐ │
│ AI  │   │  Tools   │   │ MCP / Skills │   │ Persistence │ │
│Chat │   │ Registry │   │ / Hooks /    │   │  SQLite     │ │
│Svc  │   │ + DSML   │   │   Crons      │   │  (sqflite_  │ │
└──┬──┘   │ Parser   │   └──────┬───────┘   │   common_   │ │
   │      └────┬─────┘          │           │    ffi)     │ │
   │           │                │           └─────────────┘ │
   │   ┌───────▼──────────┐  ┌──▼─────────┐                 │
   │   │ Builtin Tools    │  │ External   │                 │
   │   │ (Bash/Read/Edit/ │  │ Processes  │  ← safe_        │
   │   │  Grep/LSP/Git…)  │  │ (osascript │    subprocess   │
   │   └──────────────────┘  │  / rg /    │    强制超时     │
   │                         │  npx / …)  │    + SIGKILL    │
   │                         └────────────┘                 │
   │                                                         │
   └──────────► Protocol Adapters (OpenAI/Claude/Gemini/…)──┘
```

关键机制：
- **`safe_subprocess.runProcessWithTimeout`** 统一收敛所有外部进程超时与子进程强杀。
- **`AiToolRuntimeService.toolRegistry`** 暴露给 `AiSessionController`，运行时可热改工具字段。
- **`AppearOnce` + `AppearTracker`** 220ms FadeTransition + 绘制期纵向位移；列表/Sliver 内安全。
- **并行 Boot**：7 个 Controller 并发初始化，3 个 `openhand.boot.*` Timeline 标记可在 DevTools 观测。

---

## 📦 下载与运行

> 当前未提供预编译二进制，请从源码构建。

### 系统要求

| 平台 | 最低版本 |
|---|---|
| macOS | 12 Monterey 及以上（Apple Silicon 推荐） |
| Windows | Windows 10 21H2 及以上 |
| Linux | Ubuntu 22.04 / Fedora 38 及以上（GTK 3） |

### 一键构建

```bash
git clone https://github.com/<your-org>/openhand.git
cd openhand
flutter pub get

# macOS
flutter build macos --release
open build/macos/Build/Products/Release/openhand.app

# Windows
flutter build windows --release

# Linux
flutter build linux --release
```

---

## 🛠 开发者指引

### 1. 准备环境

```bash
flutter --version          # >= 3.27
dart --version             # ^3.11
flutter doctor             # 确保 macOS/Windows/Linux 桌面工具链 OK
```

### 2. 拉取依赖

```bash
flutter pub get
```

> ⚠️ 项目使用 [`pub hooks`](pubspec.yaml) 让 `sqlite3` 走系统库（`source: system`），避免每次 build 从 GitHub 下载二进制。

### 3. 启动调试

```bash
flutter run -d macos       # 或 windows / linux
```

### 4. 验证门禁

提交前请保证 `flutter analyze` 0 issues、`flutter test` 全绿：

```bash
flutter analyze 2>&1 | tail -5
flutter test 2>&1 | tail -5
```

### 5. 生成本地化

修改 `lib/l10n/app_*.arb` 后：

```bash
flutter gen-l10n
```

---

## 🗂 项目结构

```
lib/
├── main.dart                       # 引导入口（并行 Boot + 错误兜底 zone）
├── app/
│   ├── openhand_app.dart           # MaterialApp + Localization
│   ├── model/                      # AppInfo 等
│   ├── state/                      # 全局 SettingsController
│   ├── support/                    # silent_log, safe_subprocess, runtime_context
│   └── theme/                      # 主题与色板
├── features/
│   ├── ai/                         # 会话引擎
│   │   ├── ai_session_controller.dart
│   │   ├── tools/                  # 25+ 内置工具
│   │   ├── service/                # ChatService / DSML / Hook / Self-Learning…
│   │   └── model/                  # 协议、模型目录、Token 用量、模板
│   ├── home/                       # 主界面（聊天、侧栏、工作区、对话框）
│   ├── hardness/                   # 硬度工程模板（13 个 part 文件）
│   ├── mcp/                        # MCP 服务器管理
│   ├── skills/                     # 技能市场
│   ├── memory/                     # 记忆库
│   ├── crons/                      # 定时任务
│   ├── hooks/                      # 生命周期钩子
│   ├── instructions/               # 指令片段
│   └── settings/                   # 设置中心
├── shared/
│   ├── data/                       # SQLite 数据访问层
│   ├── net/                        # 网络层
│   └── widgets/                    # 通用控件（AppearOnce、AppearTracker…）
└── l10n/                           # ARB + 生成的 AppLocalizations
assets/
├── branding/openhand_logo.png
└── prompts/                        # 各模板的 system / developer / compression 提示词
vendor/
└── ripgrep/                        # 跨平台 rg 二进制（Grep 工具底层）
scripts/
└── copy_vendor.sh                  # 同步 vendor 二进制
```

---

## 🌍 国际化

| 语言 | 状态 |
|---|---|
| 简体中文 `zh_Hans` | ✅ 默认 |
| 繁體中文 `zh_Hant` | ✅ |
| English `en` | ✅ |
| 日本語 `ja` | ✅ |
| Français `fr` | ✅ |
| Deutsch `de` | ✅ |

新增语种：在 `lib/l10n/` 创建 `app_<locale>.arb`，运行 `flutter gen-l10n`，并在设置面板注册。

---

## 🤝 参与贡献

欢迎 Issue 与 PR！请遵守以下约定：

1. **提交信息使用简体中文**，动词开头，目标 + 影响。
   - 范例：`修复机器专家弹窗导致全局输入框失焦/无法输入粘贴的问题`
2. 提交前必跑：`flutter analyze` + `flutter test`，保持 0 issues / 全绿。
3. 涉及外部进程一律走 [lib/app/support/safe_subprocess.dart](lib/app/support/safe_subprocess.dart)，禁止裸 `Process.run(...).timeout(...)`。
4. 静默忽略错误请使用 [silentLog](lib/app/support/silent_log.dart) 而非 `catch (_) {}`。
5. UI 文案先写入 `lib/l10n/app_zh.arb`，再运行 `flutter gen-l10n` 同步其他语种占位。

---

## ❓ FAQ

**Q：为什么我配置好的模型在工具调用时疯狂幻觉 `##TOOL_CALL##`？**
A：模型本身不支持 function-calling，OpenHand 已自动注入 DSML 规范并禁止 `##TOOL_CALL##`/`Write`/`TodoWrite` 之类的虚构调用。如仍出现，请检查模型是否被识别为「supportsToolCalls=true」却实际不支持。

**Q：dialog 里的 `TextField` 突然无法粘贴/输入？**
A：99% 是直接调用了 `osascript` 而未经 `safe_subprocess`。Apple Events 残留会让 IMK 输入上下文失效。请改走 `runProcessWithTimeout` 并用 `addPostFrameCallback` 延后到首帧之后。

**Q：会话历史会上传到云端吗？**
A：**不会**。所有数据都存储在本地 SQLite。模型请求只发送给你自己配置的服务端点。

**Q：Hermes Talker 自学习能关掉吗？**
A：可以，前往 **设置 → Hermes Talker** 关闭主开关，或将 `self_learning.hermes_talker` Cron 的「启用」开关关闭（系统任务不可删除，但允许禁用）。

---

## 📜 协议

> ⚠️ 本仓库尚未在根目录添加 `LICENSE` 文件。在正式分发前请补充开源协议（推荐 MIT / Apache-2.0），并明确第三方依赖的归属（如 `vendor/ripgrep` 沿用 BurntSushi 原协议）。

---

<div align="center">
<sub>Built with ❤️ in Flutter · Hand back to developers · OpenHand</sub>
</div>
