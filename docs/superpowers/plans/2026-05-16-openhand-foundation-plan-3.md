# OpenHand P0 Foundation 实施计划 · Plan-3

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把剩余 4 个复杂 APP feature（`mcp / message_gateway / hardness / settings`）迁入 P0 模板。完成后 APP 端 12 feature 中除 `ai`（P1）与 `home`（P2）外的 10 个全部对齐。

**Architecture:** Plan-1/2 已确立两件事：(a) `HooksModule` 实例形态被 4 feature 复用稳定；(b) `check_imports.dart` 经 path-resolve 重写后真实反映状态。Plan-3 在两件事基础上推进，并**新增「widget-bundle」轻量形态**应对 hardness/settings 这类无 Controller 的 feature。

**Tech Stack:** 沿用 Plan-1/2（Dart 3.11 / Flutter / Provider 6.x）。

**前置：** Plan-2 完成（HEAD `134c15c`）。真实 check_imports baseline = **153**。

参考：
- 设计：`docs/superpowers/specs/2026-05-16-openhand-foundation-design.md`
- 模板：`lib/features/hooks/`（controller-bearing 形态），后续也将以 mcp 验证后的样板为参照
- Plan-1：`docs/superpowers/plans/2026-05-16-openhand-foundation-plan-1.md`
- Plan-2：`docs/superpowers/plans/2026-05-16-openhand-foundation-plan-2.md`

---

## 两种 feature 形态

### 形态 A — Controller-bearing（mcp, message_gateway）

完整套用 Plan-2 已确立模板：
```
lib/features/<name>/
  <name>_controller.dart
  <name>_module.dart    ← bootstrap + providers
  index.dart
  README.md
  model/ data/ service/ widgets/ state/
```
main.dart 通过 `<Name>Module.bootstrap()` 装配。

### 形态 B — Widget-bundle（hardness, settings）

无 Controller、无 main.dart 装配。只统一目录与 barrel：
```
lib/features/<name>/
  <name>.dart           ← 仅顶层入口 widget（如 SettingsView / HardnessSessionDashboard）保留在根
  index.dart            ← barrel：export 顶层 widget + 必要 public 类型
  README.md
  model/ widgets/ service/ data/ state/   ← 把根目录散落文件按职责归位
```
**禁用 `<name>_module.dart`** — 没有 Controller 不强造 module。Barrel 用法：home_page.dart 等调用方 `import 'features/<name>/index.dart';` 拿到 `SettingsView` / `HardnessEngineeringDialog`。

无 module 的代价：跨 feature 引用方必须用 barrel；plug-and-play 装配链不涉及它们。

---

## 共享规约（所有 Task）

1. **Barrel 顺序**：跨 feature 领域 model re-export → controller（若有）→ module（若有）→ service 选择性 export → widgets 用 `show` 列白名单。第一段 re-export 摆头避开 `directives_ordering`。
2. **形态 A** 走并行 future 模式，main.dart 同 Plan-2。
3. **形态 B** 不动 main.dart 装配链；调用方（如 `home/openhand_home_page.dart`）改走 barrel。
4. **每个 feature 一个 commit**。
5. **commit 前**：`flutter analyze | tail -3` 0 errors；`git status --short` 仅包含本 feature 与必要 sibling。
6. **每个 feature 后跑** `dart run scripts/check_imports.dart 2>&1 | tail -1` 记录违规削减。

---

## Task 1: mcp feature（形态 A，barrel 上线 + caller sweep）

**关键性：** mcp 是当前 153 条违规中**最大的源**。barrel 一上线，crons / plugin_service / message_gateway / skills / home_page 多条 `mcp/...` 深路径可立即切换。

### Step 1 — 摸 mcp 现状

```bash
ls lib/features/mcp/
ls lib/features/mcp/{data,model,service,widgets}/
grep -rln "features/mcp/" lib --include="*.dart" | grep -v "features/mcp/"
grep "^import" lib/features/mcp/mcp_controller.dart | head -20
```
记录现有子目录、根级文件、sibling 调用文件清单。

### Step 2 — 整理目录

`mcp_controller.dart` 与 `mcp_view.dart` 留在根。检查 `lib/features/mcp/mcp_view.dart`：若已经在根需移到 `widgets/`：

```bash
cd /Users/liguanda/Public/FlutterProjects/OpenHand
[ -f lib/features/mcp/mcp_view.dart ] && git mv lib/features/mcp/mcp_view.dart lib/features/mcp/widgets/mcp_view.dart
mkdir -p lib/features/mcp/state
touch lib/features/mcp/state/.gitkeep
```

`widgets/mcp_view.dart` 内 `'../shared/...'`/`'../app/...'`/`'../l10n/...'` 之类 import 加一层 `../`。`'mcp_controller.dart'` → `'../mcp_controller.dart'`，model/service 路径加一层。

### Step 3 — 创建 `mcp_module.dart`

阅读 `mcp_controller.dart` 现有 `create()` 工厂（如有）或构造签名。注意 controller 已 import 多个 service —— bootstrap 内串起这些依赖。

`lib/features/mcp/mcp_module.dart`:
```dart
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'mcp_controller.dart';

class McpModule {
  McpModule._({required this.controller});

  final McpController controller;

  static Future<McpModule> bootstrap() async {
    final controller = await McpController.create();   // 或 McpController.uninitialized()，按实际
    return McpModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(McpModule m) => [
    ChangeNotifierProvider<McpController>.value(value: m.controller),
  ];
}
```

> 若 `McpController.create()` 需要参数（数据库、settings…）由 main.dart 当前传入，把这些参数放进 `bootstrap()` 形参。

### Step 4 — `index.dart` + README.md

`lib/features/mcp/index.dart`:
```dart
// Domain model re-exports — sibling features拿到 McpServer / McpTool 等只需 import 'features/mcp/index.dart'.
export 'model/mcp_server.dart';
export 'model/mcp_tool.dart';
export 'model/mcp_server_health.dart';
export 'model/mcp_keyword_index_update_mode.dart' show McpKeywordIndexUpdateMode;

export 'mcp_controller.dart';
export 'mcp_module.dart';
export 'widgets/mcp_view.dart' show McpView;
```

`README.md`：四节，列出对外 API（McpController、McpServer/Tool 等）与 stdio process manager / keyword index 等内部服务（feature 内私有）。

### Step 5 — main.dart 接 McpModule

仿 Plan-2 模式：早 kick-off + await + providers 展开。原有 `mcpController` 引用全部 → `mcp.controller`。

### Step 6 — Caller sweep（**Task 1 的最大收益点**）

逐文件改用 barrel。预期命中文件（按 Step 1 grep 结果实际为准）：
- `lib/features/crons/crons_controller.dart` — `'../mcp/model/mcp_keyword_index_update_mode.dart'` → `'../mcp/index.dart'`
- `lib/features/plugin_service/widgets/plugin_service_view.dart` — `'../../mcp/mcp_controller.dart'` 与 `'../../mcp/model/mcp_server.dart'` → `'../../mcp/index.dart'`
- `lib/features/message_gateway/message_gateway_controller.dart` — `'../mcp/mcp_controller.dart'` → `'../mcp/index.dart'`（注意 message_gateway 仍未 Plan-3 化，此处只换 mcp 那条 import）
- `lib/features/home/openhand_home_page.dart`（若有）
- 其它 sibling

每次替换后若原文件还有同 feature 多条深路径（e.g. `mcp_controller.dart` + `mcp/model/foo.dart`），合并成单条 barrel import 并删冗余。

### Step 7 — 验收 + commit

```bash
flutter analyze 2>&1 | tail -3            # 0 errors
dart run scripts/check_imports.dart 2>&1 | tail -1   # 显著下降（预计削掉 30-60+ 条）
git status --short                        # 列出本 feature + sweep 命中文件
git add -A lib/features/mcp lib/main.dart <sweep 命中文件>
git commit -m "P0 plan-3 mcp feature 对齐标准模板 + barrel 全仓接入

- widgets/mcp_view.dart 归位；state/ 占位
- 新增 mcp_module.dart（bootstrap + providers）
- 新增 index.dart barrel（re-export McpServer/McpTool/McpKeywordIndexUpdateMode 等领域模型）+ README.md
- main.dart 改走 mcpModuleFuture / providers(mcp)
- caller sweep：crons / plugin_service / message_gateway / home_page 等深路径切到 barrel
check_imports 违规：153 → <实际数字>"
```

---

## Task 2: message_gateway feature（形态 A，依赖 Task 1 mcp barrel）

### 上下文

`message_gateway_controller.dart` 是个跨 feature 协调器，import 链路（Task 1 完成后状态）：
- `'../ai/ai_session_controller.dart'`、`'../ai/model/ai_thread_template.dart'`、`'../ai/service/ai_bash_tool_service.dart' show ...`、`'../ai/service/ai_image_generation_service.dart'`（4 条）— `ai` 留 P1 不动，仍是深路径
- `'../crons/index.dart'`、`'../instructions/index.dart'`、`'../memory/index.dart'`、`'../mcp/index.dart'`、`'../plugin_service/index.dart'`、`'../skills/index.dart'` — 已 barrel 化
- `'../../app/...'`、`'data/...'`、`'model/...'`、`'service/...'` — feature 内

**注意：** Task 1 caller sweep 已把 message_gateway 内对 mcp 的 deep import 换成 barrel；此 Task 不再二次处理。

### Step 1 — 现状摸底
```bash
ls lib/features/message_gateway/
grep "^import" lib/features/message_gateway/message_gateway_controller.dart | head -25
grep -rln "features/message_gateway/" lib --include="*.dart" | grep -v "features/message_gateway/"
```

### Step 2 — 移动 view + state/.gitkeep

```bash
cd /Users/liguanda/Public/FlutterProjects/OpenHand
mkdir -p lib/features/message_gateway/{widgets,state}
touch lib/features/message_gateway/state/.gitkeep
git mv lib/features/message_gateway/message_gateway_view.dart lib/features/message_gateway/widgets/message_gateway_view.dart
```

### Step 3 — Fix view import depth

`widgets/message_gateway_view.dart` 的 shared/app/l10n 都加一层 `../`；同 feature 引用变 `'../message_gateway_controller.dart'`、`'../data/...'`、`'../model/...'`、`'../service/...'`。

flutter analyze 校验 0 errors。

### Step 4 — `message_gateway_module.dart`

```dart
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'message_gateway_controller.dart';

class MessageGatewayModule {
  MessageGatewayModule._({required this.controller});

  final MessageGatewayController controller;

  static Future<MessageGatewayModule> bootstrap({
    required <依赖>,   // 视 controller 构造签名而定
  }) async {
    final controller = MessageGatewayController(/* 注入依赖 */);
    return MessageGatewayModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(MessageGatewayModule m) => [
    ChangeNotifierProvider<MessageGatewayController>.value(value: m.controller),
  ];
}
```

> Controller 当前在 main.dart 是怎么构造的？打开 main.dart 看一眼，把所有 `MessageGatewayController(...)` 的命名参数直接挪进 `bootstrap()` 形参，再原样转发。这是注入式 module，不要在 module 内自创依赖。

### Step 5 — `index.dart` + README

`lib/features/message_gateway/index.dart`:
```dart
export 'model/web_message_platform_config.dart';      // 若外部需要
export 'message_gateway_controller.dart';
export 'message_gateway_module.dart';
export 'widgets/message_gateway_view.dart' show MessageGatewayView;
```

README 四节，**显式标注**：message_gateway 当前仍直接 import `features/ai/...` 4 条 deep paths，保留至 P1 ai 拆解。

### Step 6 — main.dart 装配

替换 main.dart 中 `final messageGatewayController = MessageGatewayController(...)` 为：
- 把所有 `MessageGatewayController(...)` 的命名参数移到 `MessageGatewayModule.bootstrap(...)` 调用。
- 由于 controller 注入了 hooks/instructions/memory/skills/crons/mcp/plugin_service 等多个 controller，**bootstrap 的 await 必须排在那些 await 之后**——把 `messageGatewayModuleFuture` 的声明与 await 都放在原 controller 构造点。无法早 kick-off。
- 注释说明：「coordinator 依赖其他 feature controller，需顺序构造」。

### Step 7 — Sibling cleanup
仅命中文件按 barrel 切。

### Step 8 — Commit
```
P0 plan-3 message_gateway feature 对齐标准模板

- widgets/message_gateway_view.dart 归位；state/ 占位
- 新增 message_gateway_module.dart（注入式 bootstrap，依赖其他 feature controller 顺序构造）
- 新增 index.dart barrel + README.md
- main.dart 改走 MessageGatewayModule.bootstrap，message_gateway 段保留顺序构造（无法早 kick-off）
- 残留：直接 import features/ai/* 4 条 deep path 保留至 P1 ai 拆解后清除
check_imports 违规：<前值> → <新值>
```

---

## Task 3: settings feature（形态 B，widget-bundle）

### 上下文

无 Controller（`SettingsController` 在 `app/state/`）。15 个 `_settings_*.dart` 是私有式 widget 子片段（以下划线开头表示约定为 settings 内部用）。`data_cleanup/` 已是子目录。`thread_session_management_dialog.dart` 是独立对话框。`widgets/` 已存在但目前只放了什么需进文件夹看。

### Step 1 — 摸现状
```bash
ls lib/features/settings/
ls lib/features/settings/{widgets,data_cleanup}/  
grep -rln "features/settings/" lib --include="*.dart" | grep -v "features/settings/"
```
应该只有 home 等少数地方引用。

### Step 2 — 子目录决策

按职责分类 15 个 `_settings_*.dart`：
- 全部是 widget 片段（编辑器、对话框、表单段落）→ 全部进 `widgets/`
- `_settings_data_cleanup.dart` 与 `data_cleanup/` 重叠 → 把 `_settings_data_cleanup.dart` 也进 `widgets/`，与 `data_cleanup/` 子目录共存。
- `_settings_helper_widgets.dart` → `widgets/_settings_helper_widgets.dart`
- `thread_session_management_dialog.dart` → `widgets/thread_session_management_dialog.dart`

`data_cleanup/` 子目录（已存在）保留原状，里面应是与数据清理对应的辅助/服务文件 — 不动。

### Step 3 — Batch move
```bash
cd /Users/liguanda/Public/FlutterProjects/OpenHand
mkdir -p lib/features/settings/{model,data,service,state}
touch lib/features/settings/model/.gitkeep lib/features/settings/state/.gitkeep lib/features/settings/data/.gitkeep lib/features/settings/service/.gitkeep
for f in lib/features/settings/_settings_*.dart; do
  git mv "$f" "lib/features/settings/widgets/$(basename $f)"
done
git mv lib/features/settings/thread_session_management_dialog.dart lib/features/settings/widgets/thread_session_management_dialog.dart
git mv lib/features/settings/settings_view.dart lib/features/settings/widgets/settings_view.dart
```

### Step 4 — Fix import depths

每个 `widgets/_settings_*.dart` 与 `widgets/settings_view.dart`、`widgets/thread_session_management_dialog.dart`：
- shared/app/l10n 加一层 `../`
- 同 feature 兄弟 widget：现在都在 `widgets/`，相互 import 改成 `'./xxx.dart'`（或保留 `'xxx.dart'` 也行，Dart 支持）
- `data_cleanup/...` → `'../data_cleanup/...'`

逐个手工修；批量 sed 会误伤复杂场景。完成后 `flutter analyze 2>&1 | grep "error" | grep "settings"` 必须空。

### Step 5 — index.dart + README

`lib/features/settings/index.dart`:
```dart
export 'widgets/settings_view.dart' show SettingsView;
export 'widgets/thread_session_management_dialog.dart' show ThreadSessionManagementDialog;
```

> 不导出 `_settings_*.dart` —— 它们是 feature 内部 widget 片段，由 `settings_view.dart` 内部 import。

`README.md`:
```markdown
# Settings feature（widget-bundle 形态）

## 职责
桌面应用设置页：偏好、AI 模型、命令规则、代理、内嵌工具开关、数据清理等。

## 形态
本 feature 没有自身 Controller，使用 `app/state/SettingsController`（全局）。
因此不提供 `SettingsModule`，只通过 barrel 暴露入口 widget。

## 对外 API
- `SettingsView` — 设置页主入口
- `ThreadSessionManagementDialog` — 会话管理对话框
- barrel: `features/settings/index.dart`

## 依赖
- `app/state/SettingsController`（全局，外部装配）
- `app/model/*`（领域模型）
- 15 个 `widgets/_settings_*.dart` 内部片段（不对外暴露）
- `data_cleanup/`（feature 内私有清理服务）

## 不变量
- `_settings_*` 文件不被 feature 外引用（约定）
- `SettingsView` 内部组合所有片段；新增设置段落新增一个 `_settings_*.dart` 文件
```

### Step 6 — Caller sweep

```bash
grep -rln "features/settings/" lib --include="*.dart" | grep -v "features/settings/"
```
每个命中文件的 `'features/settings/settings_view.dart'` / `'features/settings/thread_session_management_dialog.dart'` 改 `'features/settings/index.dart'`。

main.dart 若有 settings 相关 import 也要 barrel 化。

### Step 7 — flutter analyze + commit
```
P0 plan-3 settings feature 对齐 widget-bundle 形态

- 15 个 _settings_*.dart + settings_view + thread_session_management_dialog 全归 widgets/
- model/+data/+service/+state/ 占位
- 新增 index.dart barrel（仅导出 SettingsView 与 ThreadSessionManagementDialog）+ README.md
- 不引入 SettingsModule：本 feature 无自身 Controller，全局 SettingsController 在 app/state/ 装配
- caller sweep：home 等深路径切到 barrel
check_imports 违规：<前值> → <新值>
```

---

## Task 4: hardness feature（形态 B，23 part 文件）

### 上下文

无 Controller，无 main.dart 装配。30 文件构成：
- 1 个 store：`hardness_session_store.dart`
- 7 个 service/dialog：`hardness_api_phase_runner / hardness_cli_catalog / hardness_cli_install_dialog / hardness_cli_login_dialog / hardness_engineering_dialog / hardness_orchestrator / hardness_prompt_builder`
- 14 个 dashboard part 文件：`hardness_session_dashboard.dart` + `hardness_session_dashboard.*.part.dart` ×13
- `model/`、`widgets/` 子目录已存在

`*.part.dart` 文件用 `part of 'hardness_session_dashboard.dart';` 跟 dashboard 主文件绑定 —— **它们必须与主文件保持同目录**，否则 `part of` 路径会断。

### Step 1 — 摸现状
```bash
ls lib/features/hardness/
ls lib/features/hardness/{model,widgets}/
head -3 lib/features/hardness/hardness_session_dashboard.composer.part.dart   # 看 part of 写法
grep -l "^part of " lib/features/hardness/*.part.dart | wc -l                  # part 文件计数
grep -rln "features/hardness/" lib --include="*.dart" | grep -v "features/hardness/"
```

### Step 2 — 子目录决策

**dashboard 主文件 + 13 个 part 文件** 一起放进 `widgets/`：所有 part 与 main 一起 git mv，保持 part of 语义不变（part of 引用同名相对路径）。

**其它 7 个根级文件**：
- `hardness_session_store.dart` → `data/`
- `hardness_orchestrator.dart` → `service/`
- `hardness_api_phase_runner.dart` → `service/`
- `hardness_cli_catalog.dart` → `service/`
- `hardness_prompt_builder.dart` → `service/`
- `hardness_engineering_dialog.dart` → `widgets/`
- `hardness_cli_install_dialog.dart` → `widgets/`
- `hardness_cli_login_dialog.dart` → `widgets/`

### Step 3 — Move
```bash
cd /Users/liguanda/Public/FlutterProjects/OpenHand
mkdir -p lib/features/hardness/{data,service,state}
touch lib/features/hardness/state/.gitkeep

git mv lib/features/hardness/hardness_session_store.dart       lib/features/hardness/data/hardness_session_store.dart

git mv lib/features/hardness/hardness_orchestrator.dart        lib/features/hardness/service/hardness_orchestrator.dart
git mv lib/features/hardness/hardness_api_phase_runner.dart    lib/features/hardness/service/hardness_api_phase_runner.dart
git mv lib/features/hardness/hardness_cli_catalog.dart         lib/features/hardness/service/hardness_cli_catalog.dart
git mv lib/features/hardness/hardness_prompt_builder.dart      lib/features/hardness/service/hardness_prompt_builder.dart

git mv lib/features/hardness/hardness_engineering_dialog.dart  lib/features/hardness/widgets/hardness_engineering_dialog.dart
git mv lib/features/hardness/hardness_cli_install_dialog.dart  lib/features/hardness/widgets/hardness_cli_install_dialog.dart
git mv lib/features/hardness/hardness_cli_login_dialog.dart    lib/features/hardness/widgets/hardness_cli_login_dialog.dart

# dashboard main + all parts 必须一起移到 widgets/
git mv lib/features/hardness/hardness_session_dashboard.dart                       lib/features/hardness/widgets/hardness_session_dashboard.dart
for f in lib/features/hardness/hardness_session_dashboard.*.part.dart; do
  git mv "$f" "lib/features/hardness/widgets/$(basename $f)"
done
```

### Step 4 — Fix imports

逐文件改深度（所有 `'../../app/...'` 等加一层 `../`；同 feature 兄弟引用按新路径）：

- `data/hardness_session_store.dart`：shared/app/l10n 加一层；`'model/...'` → `'../model/...'`
- 4 个 service：service 间相互 import 同目录写文件名即可；model 加 `'../model/...'`；shared/app/l10n 加一层
- 3 个 widget dialog：widgets 间相互 import 写文件名；shared/app/l10n 加一层；service/data/model 加 `'../service/...'` 等
- `widgets/hardness_session_dashboard.dart` 主文件：part 引用维持 `part 'hardness_session_dashboard.composer.part.dart';` 等同目录写法不变；其它 import 加 `../`
- 14 个 `.part.dart`：`part of 'hardness_session_dashboard.dart';` **不需改**（part of 用文件名而非路径，同目录 OK）

注意 service 内部相互 import：例如 orchestrator import api_phase_runner / cli_catalog / prompt_builder —— 现在都在 service/ 同目录，相对 import 写 `'hardness_api_phase_runner.dart'`。

完成后 `flutter analyze 2>&1 | tail -3` 0 errors。

> **强力建议** Step 4 分两个 commit 推进：先 git mv 再 `flutter analyze` 看哪些断；再批改 import。28 文件挪动 + 数十个 import 改，一次性容易出错。

### Step 5 — `index.dart` + README

`lib/features/hardness/index.dart`:
```dart
// Domain model re-exports if needed
export 'model/hardness_phase.dart';
export 'model/hardness_role_config.dart';
export 'model/hardness_session_config.dart';

// 入口 widget（外部唯一可见）
export 'widgets/hardness_engineering_dialog.dart' show HardnessEngineeringDialog;
export 'widgets/hardness_session_dashboard.dart' show HardnessSessionDashboard;
```

> 23 个 part 文件全部 feature 内部用；不导出。Orchestrator、prompt_builder 等 service 同样 feature 内部用 —— 不导出。

`README.md`:
```markdown
# Hardness feature（widget-bundle 形态）

## 职责
"Hardness Engineering" 工作流：把 AI 会话拆成 phase × role，编排 prompt 与 CLI 工具链。

## 形态
无自身 Controller；状态在 service/hardness_orchestrator + data/hardness_session_store 内自托管，由入口 dialog/dashboard 内部 Provider 树持有。不挂在 main.dart 全局 providers 上。

## 对外 API
- `HardnessEngineeringDialog` — 触发硬度工程会话的入口对话框
- `HardnessSessionDashboard` — 会话仪表盘 widget
- 领域模型：`HardnessPhase / HardnessRoleConfig / HardnessSessionConfig` 等（barrel 再导出）
- barrel: `features/hardness/index.dart`

## 文件组织
- `data/` — session store（sqflite + 文件系统）
- `service/` — orchestrator、prompt_builder、CLI catalog、API phase runner
- `widgets/` — 入口 dialog + dashboard 主页 + 13 个 part 子片段 + 2 个 CLI 对话框
- `model/` — phase / role / session config 等领域模型

## 不变量
- 23 个 `*.part.dart` 与 `hardness_session_dashboard.dart` 共生：必须同目录、part of 引用同文件名
- service/orchestrator 是单例式状态机；不要多实例化
```

### Step 6 — Caller sweep

```bash
grep -rln "features/hardness/" lib --include="*.dart" | grep -v "features/hardness/"
```
（survey 显示当前 0 sibling caller，但 git mv 后可能有 main.dart 或 home_page 引用浮现）。

### Step 7 — Commit
```
P0 plan-3 hardness feature 对齐 widget-bundle 形态

- 28 文件归位：data/hardness_session_store.dart、service/{orchestrator,prompt_builder,cli_catalog,api_phase_runner}.dart、widgets/{engineering_dialog,cli_install_dialog,cli_login_dialog,session_dashboard}.dart、widgets/hardness_session_dashboard.*.part.dart ×13
- state/ 占位
- 新增 index.dart barrel（仅导出 HardnessEngineeringDialog、HardnessSessionDashboard 与领域模型）+ README.md
- 不引入 HardnessModule：本 feature 无 main.dart 装配，状态在入口 widget 内部 Provider 托管
- part of 维持同文件名引用（无需改）
check_imports 违规：<前值> → <新值>
```

---

## Task 5: 最终验收

### Step 1 — 全套校验
```bash
cd /Users/liguanda/Public/FlutterProjects/OpenHand
flutter analyze 2>&1 | tail -3
dart test scripts/test/ 2>&1 | tail -3
dart run scripts/check_imports.dart 2>&1 | tail -1
SKIP_IMPORT_CHECK=1 bash scripts/build_web.sh 2>&1 | tail -3
```

预期：
- analyze 0 errors
- 6 tests pass
- check_imports 显著下降；剩余应主要来自 features/ai/* 与 features/home/* 引用（P1/P2 处理）
- build_web 通过

### Step 2 — 关闭 SKIP_IMPORT_CHECK 评估

若剩余违规 < 20 且都集中在 ai/home：考虑直接关闭 `SKIP_IMPORT_CHECK=1` 过渡开关，让 build_web 在违规时硬 fail —— Plan-4 与 P1 强制清零。

若违规仍 ≥ 50：保留过渡开关，commit message 标注。

### Step 3 — 桌面 app 冒烟（如可行）

`flutter run -d macos` → 打开 设置 / mcp / hardness engineering 各页 → 触发 message gateway → 无崩溃。

### Step 4 — 收尾 commit
```
P0 plan-3 完成：mcp / message_gateway / hardness / settings 全部对齐

- 形态 A（controller-bearing）：mcp + message_gateway 走 <Name>Module.bootstrap / providers
- 形态 B（widget-bundle）：hardness + settings 仅统一目录 + barrel，无 module
- caller sweep 大幅削减跨 feature 深路径 import

验收：
- flutter analyze 0 errors
- dart test scripts/test/: 6/6 PASS
- check_imports: 153 → <最终值>
- build_web 通过

P0 阶段 APP 端剩余：ai（P1 拆解）+ home（P2 拆解）。
P0 阶段 WEB 端剩余：Plan-4（chat / sessions / plugins / files / ops / logs / toolbox / hardness / home / login 10 个 feature 镜像）。
```

---

## Self-Review

- **Spec 覆盖**：Plan-3 覆盖 4 个 feature 全部，并显式拓展「widget-bundle」形态 — 符合 P0 spec § 2「目录布局」的 spirit（不强加 Module）。
- **占位符**：无 TBD/TODO；只有 README 中的「说明」性文本与 commit message 里的 `<新值>` 占位（实施时填）。
- **类型一致**：形态 A 的 module 命名/返回类型一致（McpModule / MessageGatewayModule），bootstrap 与 providers 签名对齐 Plan-2。
- **风险与对策**：
  - mcp barrel 触发 caller sweep — 单 commit 改动文件多，每改一个文件后 `flutter analyze` 兜底。
  - message_gateway 强依赖其他 feature controller — bootstrap 必须串行而非并行。README 显式标注 ai 残留 deep import。
  - hardness 14 个 part 文件必须与主文件同目录 — `part of '<filename>.dart'` 写法保留。
  - settings 15 个 `_settings_*` 文件相互 import — 全在 widgets/ 同目录后写文件名 OK。
