# OpenHand P0 Foundation 实施计划 · Plan-2

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 5 个小 APP feature（`instructions / memory / plugin_service / skills / crons`）迁入 Plan-1 已验证的标准模板，复用 `HooksModule` 形态。完成后 APP 端 12 feature 中 6 个对齐模板，剩余 6 个（ai/home/hardness/settings/mcp/message_gateway）留给 Plan-3+。

**Architecture:** 每个 feature 经历同样 5-step：scaffold 目录骨架 → 移动既有文件 → 修 import 深度 → 写 `<name>_module.dart` + `index.dart` + `README.md` → 改 main.dart 装配走 module。`flutter analyze` 0 errors 兜底；`check_imports` 违规数应阶段性下降。

**Tech Stack:** Dart 3.11 / Flutter / Provider 6.x（沿用 Plan-1）。

**前置依赖：** Plan-1 已完成（HEAD `296ed75`）。`HooksModule` 模板已实证，`scaffold_feature.dart` 可生成骨架，`check_imports.dart` 可校验。

参考：
- 设计：`docs/superpowers/specs/2026-05-16-openhand-foundation-design.md`
- 试点：`lib/features/hooks/` 标准模板
- Plan-1：`docs/superpowers/plans/2026-05-16-openhand-foundation-plan-1.md`

---

## 共享规约（每个 feature task 都遵守）

1. **目录布局**（缺哪个建哪个，已有的不动）：`<name>_controller.dart / <name>_module.dart / index.dart / README.md / model/ data/ service/ widgets/ state/`。
2. **模板形态**（参照 `lib/features/hooks/hooks_module.dart`）：
   - `<Name>Module` 私构 `_({required this.controller, ...})`，字段含 controller 与该 feature 的其他长生命周期对象（如 executor / worker）。
   - `static Future<<Name>Module> bootstrap()` 串行初始化所有内部依赖，返回实例。
   - `static List<SingleChildWidget> providers(<Name>Module m)` 暴露 `.value` providers（stateless service）或 `create: + dispose:`（有状态）。
3. **barrel `index.dart`** 顺序：跨 feature 领域 model 的 re-export → controller → module → service 完整 export → widgets/dialogs 用 `show` 列白名单。re-export 放第一段避开 `directives_ordering` lint。
4. **README.md** 四节：职责 / 对外 API / 依赖 / 不变量。
5. **main.dart 改造**：保留并行 `bootstrap()` Future、`await` 后用 `<Name>Module.providers(m)` 替换原内联 provider 行；删除该 feature 的旧深路径 import，换 `import 'features/<name>/index.dart';`。
6. **sibling 修复**：被迁移文件的其它 feature 引用方（如有）就地改路径，**不**借机改 barrel — 这是 Plan-3 的事。
7. **每个 feature 一个 commit**：`P0 plan-2 <name> feature 对齐标准模板`。
8. **每个 commit 前**：
   - `flutter analyze | tail -3` 必须显示 0 errors
   - `git status --short` 必须只含本 feature + main.dart + 必要 sibling
9. **commit 之间**：每完成一个 feature 跑 `dart run scripts/check_imports.dart 2>&1 | tail -1` 记录违规数下降。

---

## Task 1: Pre-flight 基线 + 任务清单

**Files:** 无新增。仅记录基线。

- [ ] **Step 1: 记录 baseline**

```bash
cd /Users/liguanda/Public/FlutterProjects/OpenHand
flutter analyze 2>&1 | tail -3
dart test scripts/test/ 2>&1 | tail -2
dart run scripts/check_imports.dart 2>&1 | tail -1
```
预期：37 issues / 0 errors / 6 tests pass / 680 violations。把数字记在脑里或纸上 — 后续 Task 7 验证下降。

- [ ] **Step 2: 确认 HooksModule 模式可复制**

打开 `lib/features/hooks/hooks_module.dart` 与 `lib/features/hooks/index.dart` 速看一眼，确认 Plan-2 每个 feature 的 module/barrel 形态对齐它。

- [ ] **Step 3: 确认 main.dart 当前 hooks 段**

打开 `lib/main.dart` 找到：
```dart
final hooksModuleFuture = HooksModule.bootstrap();
...
final hooks = await hooksModuleFuture;
...
...HooksModule.providers(hooks),
```
后续 5 个 feature 按完全相同的模式插入。

无 commit 此 Task。

---

## Task 2: instructions feature

**当前状态：** `data/instructions_store.dart`, `model/user_instruction_entry.dart`, `instructions_controller.dart`, `instructions_view.dart`. 已有 data/ model/。

**目标：** 加 `widgets/` 放 view、加 `service/.gitkeep` 与 `state/.gitkeep` 占位、加 `<name>_module.dart` / `index.dart` / `README.md`、main.dart 改装配。

- [ ] **Step 1: 建占位目录 + 移动 view**

```bash
cd /Users/liguanda/Public/FlutterProjects/OpenHand
mkdir -p lib/features/instructions/widgets lib/features/instructions/service lib/features/instructions/state
touch lib/features/instructions/service/.gitkeep lib/features/instructions/state/.gitkeep
git mv lib/features/instructions/instructions_view.dart lib/features/instructions/widgets/instructions_view.dart
```

- [ ] **Step 2: 修 view import 深度**

打开 `lib/features/instructions/widgets/instructions_view.dart`，把以下 import 增加一层 `../`：
- `'../../shared/...'` → `'../../../shared/...'`
- `'../../app/...'` → `'../../../app/...'`
- `'instructions_controller.dart'` → `'../instructions_controller.dart'`

具体几条按文件内现有 import 改。完成后 `flutter analyze 2>&1 | grep -E "error|instructions/widgets" | head` 确认无新错误。

- [ ] **Step 3: 创建 instructions_module.dart**

`lib/features/instructions/instructions_module.dart`:
```dart
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'instructions_controller.dart';

/// Assembly point for the instructions feature.
class InstructionsModule {
  InstructionsModule._({required this.controller});

  final InstructionsController controller;

  static Future<InstructionsModule> bootstrap() async {
    final controller = await InstructionsController.create();
    return InstructionsModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(InstructionsModule m) => [
    ChangeNotifierProvider<InstructionsController>.value(value: m.controller),
  ];
}
```

> 若 `InstructionsController.create()` 签名带参数（先打开看一眼），bootstrap 顺着改。

- [ ] **Step 4: 创建 index.dart + README.md**

`lib/features/instructions/index.dart`:
```dart
// Domain model re-exports（外部一次 import 即可拿到全部对外符号）
export 'model/user_instruction_entry.dart' show UserInstructionEntry;

export 'instructions_controller.dart';
export 'instructions_module.dart';
export 'widgets/instructions_view.dart' show InstructionsView;
```

> 若 `instructions_view.dart` 导出的 widget 名不是 `InstructionsView`，按实际改。

`lib/features/instructions/README.md`:
```markdown
# Instructions feature

## 职责
管理用户自定义的全局/项目指令（user_instructions），供 AI 系统提示拼接使用。

## 对外 API
- `InstructionsController` — Provider 提供，含 entries 与增删改方法
- `UserInstructionEntry` — 领域模型
- `InstructionsModule.bootstrap()` / `InstructionsModule.providers(m)`
- `InstructionsView` — 设置页中的指令编辑 widget

## 依赖
- `model/user_instruction_entry.dart`（自 barrel 再导出）
- `data/instructions_store.dart`（SQLite 持久化）

## 不变量
- 同一 id 在 entries 内唯一
- 持久化串行化由 InstructionsStore.mutationQueue 保证
```

- [ ] **Step 5: 改 main.dart 装配**

`lib/main.dart`：
1. 删除 `import 'features/instructions/instructions_controller.dart';`
2. 改/新增 `import 'features/instructions/index.dart';`
3. 在 hooks 模式后面加：
   ```dart
   final instructionsModuleFuture = InstructionsModule.bootstrap();
   // ... 后续 await ...
   final instructions = await instructionsModuleFuture;
   ```
   把原 `final instructionsController = await InstructionsController.create();`（或类似）替换。
4. provider 列表中：删除原 `ChangeNotifierProvider<InstructionsController>.value(value: instructionsController)`，替换成 `...InstructionsModule.providers(instructions),`。
5. 所有用到 `instructionsController` 的下游代码改为 `instructions.controller`。

> grep 一下 `grep -n "InstructionsController\|instructionsController" lib/main.dart` 找全。

- [ ] **Step 6: 修 sibling 引用方（如有）**

```bash
grep -rln "features/instructions/instructions_view\|features/instructions/instructions_controller" lib --include="*.dart" | grep -v "features/instructions/"
```
对每个命中文件，把深路径改为 `import 'features/instructions/index.dart';`，并删掉重复的 `UserInstructionEntry` model import（已被 barrel re-export）。

- [ ] **Step 7: flutter analyze + commit**

```bash
flutter analyze 2>&1 | tail -3   # 0 errors
git add lib/features/instructions lib/main.dart
# 若 sibling 修了，也 add
git status --short                # 仅 features/instructions/*, main.dart, 必要 sibling
git commit -m "P0 plan-2 instructions feature 对齐标准模板

- widgets/instructions_view.dart 归位
- 新增 instructions_module.dart（bootstrap + providers 实例形态）
- 新增 index.dart barrel（含 UserInstructionEntry re-export）+ README.md
- main.dart 改走 InstructionsModule.bootstrap / providers(instructions)"
```

- [ ] **Step 8: 记录 check_imports 下降**

```bash
dart run scripts/check_imports.dart 2>&1 | tail -1
```
预期违规数从 680 略降（取决于 sibling 引用情况）。

---

## Task 3: memory feature

**当前状态：** `data/memory_store.dart`, `model/user_memory_entry.dart`, `memory_controller.dart`, `memory_view.dart`. 与 instructions 同构。

完全照搬 Task 2 的 8 个 Step，把 `instructions` → `memory`、`InstructionsXxx` → `MemoryXxx`、`UserInstructionEntry` → `UserMemoryEntry`、`InstructionsView` → `MemoryView`。

- [ ] Step 1-8 同 Task 2，记忆替换。

最终 commit：
```
P0 plan-2 memory feature 对齐标准模板

- widgets/memory_view.dart 归位
- 新增 memory_module.dart / index.dart（含 UserMemoryEntry re-export）/ README.md
- main.dart 改走 MemoryModule.bootstrap / providers(memory)
```

---

## Task 4: plugin_service feature

**当前状态：** `model/plugin_info.dart` 等, `service/plugin_lifecycle_service.dart`, `service/plugin_scanner_service.dart`, `plugin_service_controller.dart`, `plugin_service_view.dart`. 已有 model/ service/，没有 data/ widgets/。

- [ ] **Step 1: 建 widgets/ + data/.gitkeep + state/.gitkeep + 移 view**

```bash
mkdir -p lib/features/plugin_service/{widgets,data,state}
touch lib/features/plugin_service/data/.gitkeep lib/features/plugin_service/state/.gitkeep
git mv lib/features/plugin_service/plugin_service_view.dart lib/features/plugin_service/widgets/plugin_service_view.dart
```

- [ ] **Step 2: 修 view import 深度**

`lib/features/plugin_service/widgets/plugin_service_view.dart`：
- shared/app 路径加层
- `'plugin_service_controller.dart'` → `'../plugin_service_controller.dart'`

- [ ] **Step 3: 写 plugin_service_module.dart**

`lib/features/plugin_service/plugin_service_module.dart`:
```dart
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'plugin_service_controller.dart';

class PluginServiceModule {
  PluginServiceModule._({required this.controller});

  final PluginServiceController controller;

  static Future<PluginServiceModule> bootstrap() async {
    final controller = await PluginServiceController.create();
    return PluginServiceModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(PluginServiceModule m) => [
    ChangeNotifierProvider<PluginServiceController>.value(value: m.controller),
  ];
}
```

> 若 controller 的 create 需要参数（如 PluginScannerService 实例），bootstrap 内部串起来即可。先 grep `grep -n "PluginServiceController.create" lib/main.dart` 看现状。

- [ ] **Step 4: index.dart + README.md**

`lib/features/plugin_service/index.dart`:
```dart
export 'model/plugin_info.dart';                  // 全量导出该 model 文件的公开符号
export 'plugin_service_controller.dart';
export 'plugin_service_module.dart';
export 'service/plugin_lifecycle_service.dart';   // 若外部用，否则用 show
export 'service/plugin_scanner_service.dart';     // 同上
export 'widgets/plugin_service_view.dart' show PluginServiceView;
```

> 如果 `plugin_lifecycle_service.dart` / `plugin_scanner_service.dart` 仅 feature 内部使用，删掉这两行 — 让 barrel 只暴露真正对外的符号。先 `grep -rln "PluginLifecycleService\|PluginScannerService" lib --include="*.dart" | grep -v "plugin_service/"` 验证。

`README.md`：四节，照搬 Plan-1 hooks 形态。

- [ ] **Step 5: main.dart 装配 + sibling 修复（同 Task 2 Step 5-6）**

- [ ] **Step 6: flutter analyze + commit**

```
P0 plan-2 plugin_service feature 对齐标准模板

- widgets/plugin_service_view.dart 归位；data/+state/ 占位
- 新增 plugin_service_module.dart / index.dart / README.md
- main.dart 改走 PluginServiceModule.bootstrap / providers
```

---

## Task 5: skills feature

**当前状态：** `data/`, `model/`, `skill_market_dialog.dart`, `skills_controller.dart`, `skills_view.dart`. 没有 service/ widgets/。`skill_market_dialog.dart` 是个独立对话框。

- [ ] **Step 1: 建 widgets/ + service/.gitkeep + state/.gitkeep + 移两个 widget**

```bash
mkdir -p lib/features/skills/{widgets,service,state}
touch lib/features/skills/service/.gitkeep lib/features/skills/state/.gitkeep
git mv lib/features/skills/skills_view.dart lib/features/skills/widgets/skills_view.dart
git mv lib/features/skills/skill_market_dialog.dart lib/features/skills/widgets/skill_market_dialog.dart
```

- [ ] **Step 2: 修两个 widget 的 import 深度**

两个 widget 都要：
- shared/app 加层
- `'skills_controller.dart'` → `'../skills_controller.dart'`

- [ ] **Step 3: 写 skills_module.dart**

`lib/features/skills/skills_module.dart`:
```dart
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'skills_controller.dart';

class SkillsModule {
  SkillsModule._({required this.controller});
  final SkillsController controller;

  static Future<SkillsModule> bootstrap() async {
    final controller = await SkillsController.create();
    return SkillsModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(SkillsModule m) => [
    ChangeNotifierProvider<SkillsController>.value(value: m.controller),
  ];
}
```

- [ ] **Step 4: index.dart + README.md**

`lib/features/skills/index.dart`:
```dart
export 'model/local_skill.dart';

export 'skills_controller.dart';
export 'skills_module.dart';
export 'widgets/skills_view.dart' show SkillsView;
export 'widgets/skill_market_dialog.dart' show SkillMarketDialog;
```

> 若 model/local_skill.dart 没有需要暴露的公共符号，删该 export。同样的 widget show 名按实际改。

`README.md`：四节，简短。

- [ ] **Step 5: main.dart 装配 + sibling 修复（同 Task 2 Step 5-6）**

- [ ] **Step 6: flutter analyze + commit**

```
P0 plan-2 skills feature 对齐标准模板

- widgets/{skills_view,skill_market_dialog}.dart 归位
- 新增 skills_module.dart / index.dart / README.md
- main.dart 改走 SkillsModule.bootstrap / providers
```

---

## Task 6: crons feature

**当前状态（最复杂）：** 6 个文件全在根 — `cron_executor.dart, cron_history_cleanup_worker.dart, cron_parser.dart, crons_controller.dart, crons_store.dart, crons_view.dart`. 无任何子目录。controller 含跨 feature deep import `mcp/model/mcp_keyword_index_update_mode.dart` —— 这条违规留给 Plan-3 mcp barrel 上线后修。

- [ ] **Step 1: 建 5 子目录 + 移 4 个文件**

```bash
cd /Users/liguanda/Public/FlutterProjects/OpenHand
mkdir -p lib/features/crons/{model,data,service,widgets,state}
touch lib/features/crons/model/.gitkeep lib/features/crons/state/.gitkeep
git mv lib/features/crons/crons_store.dart                 lib/features/crons/data/crons_store.dart
git mv lib/features/crons/cron_executor.dart               lib/features/crons/service/cron_executor.dart
git mv lib/features/crons/cron_history_cleanup_worker.dart lib/features/crons/service/cron_history_cleanup_worker.dart
git mv lib/features/crons/cron_parser.dart                 lib/features/crons/service/cron_parser.dart
git mv lib/features/crons/crons_view.dart                  lib/features/crons/widgets/crons_view.dart
```

`crons_controller.dart` 留在根。

- [ ] **Step 2: 修每个移动文件 + controller 的 import 深度**

逐文件改：
- `data/crons_store.dart`：app/shared 路径加 `../`；同 feature 引用从根的 `'crons_controller.dart'` 改为 `'../crons_controller.dart'`（如有）
- `service/cron_executor.dart`：同上；引用 `'crons_store.dart'` 改 `'../data/crons_store.dart'`、`'cron_parser.dart'` 改 `'cron_parser.dart'`（同目录）
- `service/cron_history_cleanup_worker.dart`：同上
- `service/cron_parser.dart`：纯函数模块，可能只 import dart:core，最少改动
- `widgets/crons_view.dart`：shared/app 加层；`'crons_controller.dart'` 改 `'../crons_controller.dart'`
- `crons_controller.dart`：之前在根的 sibling 文件改路径：
  - `'crons_store.dart'` → `'data/crons_store.dart'`
  - `'cron_executor.dart'` → `'service/cron_executor.dart'`
  - `'cron_history_cleanup_worker.dart'` → `'service/cron_history_cleanup_worker.dart'`
  - `'cron_parser.dart'` → `'service/cron_parser.dart'`
  - 跨 feature `'../mcp/model/...'` **保留**（Plan-3 收）

```bash
flutter analyze 2>&1 | tail -5   # 确认 0 errors
```

- [ ] **Step 3: 写 crons_module.dart**

`lib/features/crons/crons_module.dart`:
```dart
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'crons_controller.dart';
import 'service/cron_executor.dart';
import 'service/cron_history_cleanup_worker.dart';

class CronsModule {
  CronsModule._({
    required this.controller,
    required this.executor,
    required this.cleanupWorker,
  });

  final CronsController controller;
  final CronExecutor executor;
  final CronHistoryCleanupWorker cleanupWorker;

  static Future<CronsModule> bootstrap() async {
    final controller = await CronsController.create();
    final executor = CronExecutor(controller: controller);
    final cleanupWorker = CronHistoryCleanupWorker(controller: controller);
    return CronsModule._(
      controller: controller,
      executor: executor,
      cleanupWorker: cleanupWorker,
    );
  }

  static List<SingleChildWidget> providers(CronsModule m) => [
    ChangeNotifierProvider<CronsController>.value(value: m.controller),
    Provider<CronExecutor>.value(value: m.executor),
    Provider<CronHistoryCleanupWorker>.value(value: m.cleanupWorker),
  ];
}
```

> 真实构造签名先看下：`grep "class CronExecutor\|CronExecutor(" lib/features/crons/service/cron_executor.dart | head -3` 与 `grep "class CronHistoryCleanupWorker\|CronHistoryCleanupWorker(" lib/features/crons/service/cron_history_cleanup_worker.dart | head -3`。如不接 controller 参数则简化。

- [ ] **Step 4: index.dart + README.md**

`lib/features/crons/index.dart`:
```dart
export '../../app/model/cron_config.dart' show CronConfig;   // 若 CronConfig 外部用，否则删

export 'crons_controller.dart';
export 'crons_module.dart';
export 'service/cron_executor.dart' show CronExecutor;
export 'service/cron_history_cleanup_worker.dart' show CronHistoryCleanupWorker;
export 'service/cron_parser.dart';
export 'widgets/crons_view.dart' show CronsView;
```

`README.md`：四节，说明 crons feature 当前对 mcp 仍有 1 条 deep import（Plan-3 处理）。

- [ ] **Step 5: main.dart 装配 + sibling 修复**

main.dart 当前可能 import 了 `cron_executor.dart` / `cron_history_cleanup_worker.dart`（worker 在 main.dart 启动），把这些 deep import 全改 `import 'features/crons/index.dart';`，bootstrap 改 `CronsModule.bootstrap()`，downstream 全部走 `crons.controller / crons.executor / crons.cleanupWorker`。

sibling 修复：`grep -rln "features/crons/" lib --include="*.dart" | grep -v "features/crons/"` 命中文件改 import。

- [ ] **Step 6: flutter analyze + commit**

```
P0 plan-2 crons feature 对齐标准模板

- 6 文件归位：data/crons_store.dart、service/{cron_executor, cron_history_cleanup_worker, cron_parser}.dart、widgets/crons_view.dart
- 新增 crons_module.dart（含 executor + cleanupWorker 三件套）/ index.dart / README.md
- main.dart 改走 CronsModule.bootstrap / providers(crons)
- crons_controller.dart 残留 mcp 跨 feature deep import 1 条，留给 Plan-3 mcp barrel 后修"
```

---

## Task 7: 最终验收

- [ ] **Step 1: 跑全套校验**

```bash
cd /Users/liguanda/Public/FlutterProjects/OpenHand
flutter analyze 2>&1 | tail -3
dart test scripts/test/ 2>&1 | tail -2
dart run scripts/check_imports.dart 2>&1 | tail -1
SKIP_IMPORT_CHECK=1 bash scripts/build_web.sh 2>&1 | tail -3
```

预期：
- analyze 0 errors（info 数可能微变）
- 6 tests pass
- check_imports 违规数从 680 显著下降（每个 feature 通常带走数十条 sibling 深路径 import）
- build_web 通过

- [ ] **Step 2: 桌面 app 冒烟（如可行）**

```bash
flutter run -d macos
```
打开设置 → instructions / memory / skills / plugins 子页；触发一个 cron — 全部正常无崩溃。

如无法签名/启动桌面，跳过此步并在 commit 说明。

- [ ] **Step 3: 收尾 commit**

```bash
git commit --allow-empty -m "P0 plan-2 完成：5 个小 feature 对齐标准模板

- instructions / memory / plugin_service / skills / crons 全部走 <Name>Module.bootstrap + providers
- main.dart 装配统一形态；sibling 深路径 import 转 barrel
- crons 残留 mcp 跨 feature deep import 1 条，Plan-3 mcp barrel 上线后清

验收：
- flutter analyze 0 errors
- dart test scripts/test/: 6/6 PASS
- check_imports 违规：680 → <实际数字>
- build_web.sh 通过

剩余：Plan-3（mcp / message_gateway / hardness / settings 4 feature）+ Plan-4（WEB 余 10 feature）"
```

---

## Self-Review

- **Spec 覆盖**：本计划 5 feature 全部走 Plan-1 验证过的 HooksModule 模式；不引入新约定。
- **占位符**：无 TBD/TODO 步骤；只有 README 内的「说明」性文本。
- **类型一致**：`<Name>Module.bootstrap() → <Name>Module` 实例返回，`providers(m)` 接 module 实例 — 与 hooks 试点完全一致。
- **风险**：
  - 每个 feature 都涉及 main.dart 装配改造，一处错就 fail；每个 commit 前 `flutter analyze` 是必须的兜底。
  - crons 含 1 条跨 feature deep import 故意保留，Plan-3 收 — 在 commit message 与 README 显式标注，避免 Plan-3 时被遗忘。
  - sibling 修复用 grep 兜底，避免遗漏。
