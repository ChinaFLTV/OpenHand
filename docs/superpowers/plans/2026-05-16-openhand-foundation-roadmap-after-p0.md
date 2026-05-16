# OpenHand P0 之后的 Roadmap

> 状态：Plan-1/2/3/4 已完成，P0 工程骨架交付。本文档梳理后续 P1-P6 阶段。

## P0 完成态摘要

| 维度 | 状态 |
|---|---|
| APP feature 标准模板 | 12 个中 10 个已对齐（hooks 试点 + Plan-2 5 个小 feature + Plan-3 mcp/message_gateway + 形态 B：settings/hardness）。ai 与 home 留给 P1/P2 |
| WEB feature 标准模板 | 全部 10 个完成（含 settings 试点） |
| lib/shared 五子目录重组 | core/db/ui/net/util 完整 |
| 跨 feature import 检查 | `scripts/check_imports.dart` + `build_web.sh` 闸门 |
| 脚手架 | `scripts/scaffold_feature.dart` + 黄金用例 |
| 真实违规数 | 680 → 130（其中 524 是脚本 bug，153 是实际 cross-feature deep import 在 Plan-1+2 后；Plan-3+ 又降 23） |
| 文档 | `docs/architecture.md` + 4 份 spec/plan |

剩余 130 条 check_imports 违规集中在 features/ai/* 与 features/home/* 内部及对它们的引用，由 P1/P2 处理。

## P1 — features/ai 拆解

**当前规模：** 108 文件 / 6.2 万行。单 feature 巨型化。

**目标拆解：**
- `features/ai/chat/`（会话核心：session、controller、消息流水）
- `features/ai/tools/`（已有 tools/ 子目录；继续按工具类型聚合）
- `features/ai/runtime/`（service/ 中的协议适配、tool runtime、self-learning 调度）
- `features/ai/model/`（model_config、session_message、runtime_context 等数据类型）
- `features/ai/cache/`（web_search、web_fetch 缓存）

**Module 形态：** controller-bearing。`AiSessionModule.bootstrap(...)` 注入 settings/mcp/hooks/memory/skills/instructions 等。鉴于体积大，建议把 module 拆成 `AiChatModule` / `AiToolsModule` / `AiRuntimeModule` 三层并通过子 module 组合，而不是单一巨型 module。

**关键风险：**
- `AiSessionController` 极可能是大类（5000+ 行）。拆解前必须先做行为冻结测试：抓 10 条 representative 会话 trace，作为 fixture 校验拆解前后输出等价。
- `self_learning_dispatcher / runner / scheduler` 在 main.dart 中有专门的并发启动逻辑；不能简单 inline 改造。
- `ai_protocol_adapter.dart` 是协议层多模型分支，触线即跨 provider 影响。

**预计 commits 量级：** 30-50 个。

**前置：** 完整准备测试 fixture；建一份 Plan-5 spec 文档明确每个子拆分的对外 API；与用户讨论是否引入 ai_session_module 的并行 bootstrap 策略。

## P2 — features/home 拆解

**当前规模：** 27 文件 / 5.6 万行。

**目标：**
- `home_page.dart` 主体（~12k 行）保留为入口；拆出导航 / 侧栏 / 列表 / composer / detail 等子 part files 到 `widgets/`
- 把 `_home_*.dart`（已经是 `part of openhand_home_page.dart` 形式）按职责分到 widgets/state/data 子目录，必要时把 controller 状态从 home_page 内部抽离成独立 `HomePageController`
- 这是 widget-bundle 还是 controller-bearing 取决于现有状态机的归属：若 home_page 自身持有大量 state（如选中工作区、当前 session、模式切换），抽 `HomePageController`；否则保持 widget-bundle

**关键风险：**
- home_page 是入口屏，性能敏感。拆解过程中要保留所有 perf annotation（Timeline、content-visibility 等）。
- `part of` 的拆解触及 23 个 `_home_*.dart`，依赖关系强；建议小步快跑、每移 2-3 个文件一次 commit。

**预计 commits 量级：** 20-30 个。

## P3-extended — 残留违规清零

P0 spec 中 P3 = APP 余下 features 对齐 — 已在 Plan-2/3 完成。但 P1/P2 完成后还有"余波"：

- features/crons/crons_controller.dart 内 `'../mcp/index.dart'` 已经是 barrel，无需动；但 controller 内对 `mcp/index.dart` 暴露的 `McpKeywordIndexUpdateMode` 引用应当通过 `lib/app/model/cron_config.dart` 中类型透传，而不是直接 import mcp
- `lib/app/state/{settings_controller,settings_store}.dart` 与 `lib/app/model/app_settings_snapshot.dart` 中 3 处 mcp 模型 deep import（check_imports 不扫 lib/app/，但应当一并走 mcp barrel）

这些算 P3 收尾 polish，不阻塞功能交付。

## P4 — WEB feature 镜像（已完成）

见 Plan-4，已交付。

后续可选优化：
- features/<name>/state 与 hooks/ 子目录目前都是空的；当某 page 引入特有 hooks 或 state 管理时，把对应文件从 src/hooks/ 与 src/state/ 中拆到 feature 内
- src/components/ 中的通用组件保留；feature 专属组件应该后续下沉到 features/<name>/components/

## P5 — Prompt 重写

**摸底结论（2026-05-16）：** 现有 `assets/prompts/*/system_instructions.md` 已经基本符合 Claude Code 风格 — 标签化结构（`<identity>` `<workflow>` `<tool_use>`）、克制 emoji、imperative tone、禁用啰嗦副词。仅 `machine_expert/system_instructions.md`（823 行）显著大于其他 preset（default 222 / hermes 195 / programming 336 / hardness 249）。

**待做：**
1. 审查 `machine_expert` 是否可拆为基础 + 专家扩展两段，向 default 看齐
2. 抽出 4 个 preset 共有的 identity/refusal/tone 段为 `assets/prompts/_shared/` 公共片段，构建时由 `manifest.yaml` 拼装（P0 spec § 6 占位骨架）
3. 复盘各 preset 的 developer_instructions 差异，统一变量命名与例子格式
4. `common/web_search_summary.md`、`common/auto_title_system_prompt.md` 复查表达是否还能更精炼

**不要做：** 不必为了形式上的"重写"打散现有良好结构。

## P6 — 性能丝滑收尾

P0 试点已经做了一系列首屏与渲染优化（参见近期 commits：会话切换 settle 循环、content-visibility、Markdown 帧节流等）。后续 P6 可继续：

1. **flutter analyze 48 issues 清零**：剩余主要是 plugin_service / settings_view 中的 `prefer_const_constructors`、`avoid_redundant_argument_values`、`directives_ordering`，逐个轻量修正
2. **WEB 端 app.js 789KB**：vite 默认 single chunk；引入 manualChunks / 动态 import 把 page-level 代码切片
3. **mcp/widgets 5 处 widgets→service 违规**：tool_search_loaded_dialog / mcp_keyword_index_progress_dialog / mcp_stdio_dialogs 重构成 controller-callback 模式，让 UI 不直接 import service
4. **build_web.sh SKIP_IMPORT_CHECK 转默认硬约束**：等 P1/P2 完成 + check_imports 零违规后删除 SKIP 开关

## 阶段实施建议

| 顺序 | 阶段 | 工作量 | 是否需要新 Plan 文档 |
|---|---|---|---|
| 下一阶段 | P5（machine_expert 拆 + _shared 片段化） | 小 | 不必，按本 roadmap 推进 |
| 下一阶段 | P6.1（flutter analyze 48 issues 清零） | 小 | 不必 |
| 中期 | P2（home 拆解） | 中 | 建议写 Plan-6 |
| 中期 | P6.2（WEB chunking） | 小 | 不必 |
| 长期 | P1（ai 拆解） | 大 | 必须写 Plan-7，含 fixture 测试设计 |
| 长期 | P3-extended + P6.3（mcp widgets→service） | 小 | 不必 |
