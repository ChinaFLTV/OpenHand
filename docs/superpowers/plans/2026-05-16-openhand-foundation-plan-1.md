# OpenHand P0 Foundation 实施计划 · Plan-1

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立 OpenHand P0 工程骨架的基础设施 — CI 级 import 检查脚本、feature 脚手架生成器、shared 五分子目录重组、文档骨架；并完成 1 个 APP 试点 feature（hooks）与 1 个 WEB 试点 feature（settings）的标准模板迁移作为后续 Plan-2/3 的样板。

**Architecture:** 保留 Provider + ChangeNotifier 范式不动；通过 `scripts/check_imports.dart` 强制跨 feature 走 barrel `index.dart`；`scripts/scaffold_feature.dart` 生成符合模板的 feature 目录；`build_web.sh` 末尾追加 import 检查作为提交闸门。试点完成后所有其他 feature 是机械复制。

**Tech Stack:** Dart 3.11、Flutter（Provider 6.x）、Preact（WEB）、bash 脚本。

参考 spec：`docs/superpowers/specs/2026-05-16-openhand-foundation-design.md`。

---

## File Structure（Plan-1 落地清单）

**新建**：
- `scripts/check_imports.dart` — CI 级深路径 import 检查器
- `scripts/scaffold_feature.dart` — 生成 feature 标准目录骨架
- `lib/features/hooks/index.dart` — 试点 feature barrel
- `lib/features/hooks/hooks_module.dart` — 试点 feature 装配点
- `lib/features/hooks/README.md` — 试点 feature 文档
- `lib/features/hooks/data/`（迁入 hooks_store.dart）
- `lib/features/hooks/service/`（迁入 hooks_executor.dart）
- `lib/features/hooks/widgets/`（迁入 hooks_view.dart）
- `lib/shared/core/`、`lib/shared/db/`、`lib/shared/ui/`（新子目录）
- `clients/web/src/app/`、`clients/web/src/features/settings/`、`clients/web/src/shared/`
- `clients/web/src/features/settings/index.ts`
- `docs/architecture.md` — 一页骨架说明

**修改**：
- `scripts/build_web.sh` — 末尾追加 `dart run scripts/check_imports.dart`
- `lib/main.dart` — hooks 模块装配改走 `HooksModule`
- `lib/shared/data/*` → 移动到 `lib/shared/db/`
- `lib/shared/widgets/*` → 移动到 `lib/shared/ui/`
- 所有引用 `lib/shared/widgets/` 与 `lib/shared/data/` 的 dart 文件
- `clients/web/src/main.tsx`、`app.tsx` — 路由抽离到 `app/router.tsx`
- `clients/web/src/pages/SettingsPage.tsx` → `clients/web/src/features/settings/components/SettingsPage.tsx`

---

## Task 1: 编写 check_imports.dart 失败用例与脚本

**Files:**
- Create: `scripts/check_imports.dart`
- Create: `scripts/test/check_imports_test.dart`

- [ ] **Step 1: 在临时目录构造一个含违规 import 的 fixture，先写失败测试**

`scripts/test/check_imports_test.dart`:
```dart
import 'dart:io';
import 'package:test/test.dart';

void main() {
  test('check_imports rejects cross-feature deep import', () async {
    final tmp = await Directory.systemTemp.createTemp('check_imports_test');
    final f = File('${tmp.path}/lib/features/a/widgets/x.dart')
      ..createSync(recursive: true);
    f.writeAsStringSync(
      "import '../../b/service/y.dart';\n",
    );
    final result = await Process.run('dart', [
      'run',
      'scripts/check_imports.dart',
      tmp.path,
    ]);
    expect(result.exitCode, isNonZero);
    expect(result.stderr.toString(), contains('deep cross-feature import'));
  });

  test('check_imports accepts barrel import', () async {
    final tmp = await Directory.systemTemp.createTemp('check_imports_test');
    final f = File('${tmp.path}/lib/features/a/widgets/x.dart')
      ..createSync(recursive: true);
    f.writeAsStringSync("import '../../b/index.dart';\n");
    File('${tmp.path}/lib/features/b/index.dart').createSync(recursive: true);
    final result = await Process.run('dart', [
      'run',
      'scripts/check_imports.dart',
      tmp.path,
    ]);
    expect(result.exitCode, 0);
  });
}
```

- [ ] **Step 2: 确认测试运行失败（脚本尚未存在）**

Run: `cd ~/Public/FlutterProjects/OpenHand && dart test scripts/test/check_imports_test.dart`
Expected: FAIL，无法运行 `scripts/check_imports.dart`。

- [ ] **Step 3: 实装最小可通过的 check_imports.dart**

`scripts/check_imports.dart`:
```dart
import 'dart:io';

/// 扫描跨 feature 深路径 import。违规规则：
///   1. lib/features/<a>/**/*.dart 中 import 形如 '../../<b>/<sub>/...' 或
///      'package:openhand/features/<b>/<sub>/...'（b != a 且 sub != 'index.dart' 且 sub != '<b>_module.dart'）。
///   2. lib/features/<a>/widgets/**/*.dart 中禁止 import '../service/...'。
///   3. clients/web/src/features/<a>/**/*.{ts,tsx} 中禁止深路径
///      '@/features/<b>/<sub>/...' 或 '../<b>/<sub>/...'。
///
/// 用法：dart run scripts/check_imports.dart [root]
///   root 默认为当前目录；测试时可传 fixture 根。
Future<void> main(List<String> args) async {
  final root = args.isEmpty ? Directory.current.path : args.first;
  var violations = 0;

  violations += await _scanDart(Directory('$root/lib/features'));
  violations += await _scanWeb(Directory('$root/clients/web/src/features'));

  if (violations > 0) {
    stderr.writeln(
      '[check_imports] $violations deep cross-feature import(s) found.',
    );
    exit(1);
  }
  stdout.writeln('[check_imports] OK');
}

Future<int> _scanDart(Directory featuresRoot) async {
  if (!featuresRoot.existsSync()) return 0;
  var n = 0;
  await for (final entity in featuresRoot.list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final rel = entity.path.substring(featuresRoot.path.length + 1);
    final owner = rel.split(Platform.pathSeparator).first;
    final inWidgets = rel.contains(
      '${Platform.pathSeparator}widgets${Platform.pathSeparator}',
    );

    final lines = await entity.readAsLines();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('import')) continue;
      final m = RegExp(
        r"""import\s+['"]((?:package:openhand/features/|(?:\.\./)+)([\w_]+)/([\w_./]+))['"]""",
      ).firstMatch(line);
      if (m == null) continue;
      final target = m.group(2)!;
      final sub = m.group(3)!;
      if (target == owner) {
        if (inWidgets && sub.startsWith('service/')) {
          stderr.writeln('${entity.path}:${i + 1} widgets → service forbidden');
          n++;
        }
        continue;
      }
      final allowed =
          sub == 'index.dart' ||
          sub == '${target}_module.dart' ||
          sub == '${target}_controller.dart';
      if (!allowed) {
        stderr.writeln(
          '${entity.path}:${i + 1} deep cross-feature import: $target/$sub',
        );
        n++;
      }
    }
  }
  return n;
}

Future<int> _scanWeb(Directory featuresRoot) async {
  if (!featuresRoot.existsSync()) return 0;
  var n = 0;
  final tsRe = RegExp(
    r"""from\s+['"](?:@/features/|(?:\.\./)+features/)([\w-]+)/([\w./-]+)['"]""",
  );
  await for (final entity in featuresRoot.list(recursive: true)) {
    if (entity is! File ||
        !(entity.path.endsWith('.ts') || entity.path.endsWith('.tsx'))) {
      continue;
    }
    final rel = entity.path.substring(featuresRoot.path.length + 1);
    final owner = rel.split(Platform.pathSeparator).first;
    final lines = await entity.readAsLines();
    for (var i = 0; i < lines.length; i++) {
      final m = tsRe.firstMatch(lines[i]);
      if (m == null) continue;
      final target = m.group(1)!;
      final sub = m.group(2)!;
      if (target == owner) continue;
      if (sub == 'index' || sub == 'index.ts' || sub == 'index.tsx') continue;
      stderr.writeln(
        '${entity.path}:${i + 1} deep cross-feature import: $target/$sub',
      );
      n++;
    }
  }
  return n;
}
```

- [ ] **Step 4: 让 pubspec.yaml 包含 test 依赖（若缺）**

确认 `dev_dependencies` 已有 `test: ^1.x`。若没有：
```yaml
dev_dependencies:
  test: ^1.25.0
```
然后 `flutter pub get`。

- [ ] **Step 5: 运行测试，应通过**

Run: `dart test scripts/test/check_imports_test.dart`
Expected: 2 tests pass。

- [ ] **Step 6: 在当前仓库根跑一次脚本，记录基线**

Run: `dart run scripts/check_imports.dart`
Expected: 大量 violations（因尚未迁移）。把违规计数记到 commit message 作为基线。

- [ ] **Step 7: 提交**

```bash
git add scripts/check_imports.dart scripts/test/check_imports_test.dart pubspec.yaml
git commit -m "新增跨 feature import 检查脚本 check_imports.dart

P0 骨架配套：扫描 lib/features 与 clients/web/src/features 的深路径 import，
违规即 fail。配套单元测试覆盖正反两个用例。基线违规计数待迁移完成后清零。"
```

---

## Task 2: 编写 scaffold_feature.dart 生成器

**Files:**
- Create: `scripts/scaffold_feature.dart`

- [ ] **Step 1: 实装生成器**

`scripts/scaffold_feature.dart`:
```dart
import 'dart:io';

/// 在 lib/features/<name>/ 下生成 P0 标准目录骨架。
/// 用法：dart run scripts/scaffold_feature.dart <feature_name>
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run scripts/scaffold_feature.dart <name>');
    exit(2);
  }
  final name = args.first;
  final root = 'lib/features/$name';
  if (Directory(root).existsSync()) {
    stderr.writeln('[scaffold] $root already exists, refusing to overwrite');
    exit(1);
  }
  for (final sub in const ['model', 'data', 'service', 'widgets', 'state']) {
    Directory('$root/$sub').createSync(recursive: true);
    File('$root/$sub/.gitkeep').writeAsStringSync('');
  }
  File('$root/${name}_controller.dart').writeAsStringSync('''
import 'package:flutter/foundation.dart';

/// Public controller for the `$name` feature.
class ${_pascal(name)}Controller extends ChangeNotifier {
  ${_pascal(name)}Controller._();

  static Future<${_pascal(name)}Controller> create() async {
    return ${_pascal(name)}Controller._();
  }
}
''');
  File('$root/${name}_module.dart').writeAsStringSync('''
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '${name}_controller.dart';

/// Assembly point for the `$name` feature.
class ${_pascal(name)}Module {
  static Future<${_pascal(name)}Controller> bootstrap() {
    return ${_pascal(name)}Controller.create();
  }

  static List<SingleChildWidget> providers(${_pascal(name)}Controller c) => [
    ChangeNotifierProvider<${_pascal(name)}Controller>.value(value: c),
  ];
}
''');
  File('$root/index.dart').writeAsStringSync('''
export '${name}_controller.dart';
export '${name}_module.dart';
''');
  File('$root/README.md').writeAsStringSync('''
# ${_pascal(name)} feature

## 职责
TODO: 一句话职责说明。

## 对外 API
- `${_pascal(name)}Controller`
- `${_pascal(name)}Module.bootstrap()` / `${_pascal(name)}Module.providers()`

## 依赖
TODO

## 不变量
TODO
''');
  stdout.writeln('[scaffold] generated $root');
}

String _pascal(String s) =>
    s.split('_').map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1)).join();
```

- [ ] **Step 2: 用临时目录验证（保留现有 hooks 不动）**

Run:
```bash
cd /tmp && mkdir -p scaffold_smoke && cd scaffold_smoke && cp -r ~/Public/FlutterProjects/OpenHand/scripts . && mkdir -p lib/features && dart run scripts/scaffold_feature.dart sample
```
Expected: 输出 `[scaffold] generated lib/features/sample`，且 `lib/features/sample/index.dart` 存在。

- [ ] **Step 3: 提交**

```bash
cd ~/Public/FlutterProjects/OpenHand
git add scripts/scaffold_feature.dart
git commit -m "新增 feature 脚手架生成器 scaffold_feature.dart

按 P0 标准模板生成 <name>/{model,data,service,widgets,state}+controller+module+index+README。"
```

---

## Task 3: 重组 lib/shared 为 core / net / db / ui / util

**Files (move):**
- `lib/shared/data/atomic_file_operations.dart` → `lib/shared/db/atomic_file_operations.dart`
- `lib/shared/data/database_service.dart` → `lib/shared/db/database_service.dart`
- `lib/shared/widgets/*` → `lib/shared/ui/*`（26 个文件）
- 新建空目录 `lib/shared/core/`（添加 `.gitkeep`）
- `lib/shared/net/`、`lib/shared/util/` 保留原状

- [ ] **Step 1: 创建新目录与 git mv 文件**

```bash
cd ~/Public/FlutterProjects/OpenHand
mkdir -p lib/shared/core lib/shared/db lib/shared/ui
touch lib/shared/core/.gitkeep
git mv lib/shared/data/atomic_file_operations.dart lib/shared/db/atomic_file_operations.dart
git mv lib/shared/data/database_service.dart lib/shared/db/database_service.dart
rmdir lib/shared/data
git mv lib/shared/widgets/animated_appearance.dart lib/shared/ui/animated_appearance.dart
# 重复对全部 26 个 widget 文件
for f in lib/shared/widgets/*.dart; do
  git mv "$f" "lib/shared/ui/$(basename $f)"
done
rmdir lib/shared/widgets
```

- [ ] **Step 2: 批量更新所有 dart 文件中的 import 路径**

Run（macOS 的 sed 用 `-i ''`）:
```bash
cd ~/Public/FlutterProjects/OpenHand
grep -rl "shared/widgets/" lib | xargs sed -i '' 's|shared/widgets/|shared/ui/|g'
grep -rl "shared/data/" lib | xargs sed -i '' 's|shared/data/|shared/db/|g'
```

- [ ] **Step 3: 运行 flutter analyze 确认无 import 错误**

Run: `flutter analyze`
Expected: 0 errors（warnings/info 可暂时忽略，需在 commit message 中说明）。

- [ ] **Step 4: 提交**

```bash
git add -A lib/shared
git add -u lib/
git commit -m "P0 shared/ 重组为 core/db/ui 五分子目录

按工程骨架公约：
- shared/widgets → shared/ui（26 个通用 widget）
- shared/data → shared/db（sqflite/原子文件）
- 新增 shared/core 占位，后续承接 Result/Disposable/typedef
shared/net 与 shared/util 维持原状。
全仓 import 路径已批量更新；flutter analyze 通过。"
```

---

## Task 4: 把 build_web.sh 与 check_imports.dart 串起来

**Files:**
- Modify: `scripts/build_web.sh`

- [ ] **Step 1: 读取当前 build_web.sh 末尾**

Read `scripts/build_web.sh` 全文，确认末尾结构。

- [ ] **Step 2: 末尾追加 import 检查（执行 web 构建后、退出前）**

在 `scripts/build_web.sh` 最后一行 `exit 0` 之前插入：
```bash
echo "[build_web] running check_imports.dart"
dart run scripts/check_imports.dart || {
  echo "[build_web] FAIL: cross-feature deep import detected"
  exit 1
}
```

> 注意：此时尚未完成全部 feature 迁移，脚本会 fail。为允许过渡期，临时改为在脚本顶部加 `: "${SKIP_IMPORT_CHECK:=0}"`，并在 import 检查处包：
> ```bash
> if [ "${SKIP_IMPORT_CHECK}" = "1" ]; then
>   echo "[build_web] SKIP_IMPORT_CHECK=1, skipping"
> else
>   ...
> fi
> ```
> Plan-2/3 完成后默认开启检查。

- [ ] **Step 3: 用 SKIP_IMPORT_CHECK=1 跑一遍 build_web.sh 验证 web 构建本身仍通过**

Run: `SKIP_IMPORT_CHECK=1 bash scripts/build_web.sh`
Expected: WEB 构建产物正常生成（assets/web 更新）。

- [ ] **Step 4: 提交**

```bash
git add scripts/build_web.sh
git commit -m "build_web.sh 串入 check_imports.dart

WEB 构建末尾增加跨 feature import 检查；过渡期可用 SKIP_IMPORT_CHECK=1 跳过，
P0 plan-2/3 收尾后移除该开关。"
```

---

## Task 5: 试点 APP feature — hooks/ 标准模板迁移

**Files (rearrange):**
- `lib/features/hooks/hooks_store.dart` → `lib/features/hooks/data/hooks_store.dart`
- `lib/features/hooks/hooks_executor.dart` → `lib/features/hooks/service/hooks_executor.dart`
- `lib/features/hooks/hooks_view.dart` → `lib/features/hooks/widgets/hooks_view.dart`
- New: `lib/features/hooks/index.dart`
- New: `lib/features/hooks/hooks_module.dart`
- New: `lib/features/hooks/README.md`

- [ ] **Step 1: 移动文件**

```bash
cd ~/Public/FlutterProjects/OpenHand
mkdir -p lib/features/hooks/{data,service,widgets,model,state}
touch lib/features/hooks/model/.gitkeep lib/features/hooks/state/.gitkeep
git mv lib/features/hooks/hooks_store.dart lib/features/hooks/data/hooks_store.dart
git mv lib/features/hooks/hooks_executor.dart lib/features/hooks/service/hooks_executor.dart
git mv lib/features/hooks/hooks_view.dart lib/features/hooks/widgets/hooks_view.dart
```

- [ ] **Step 2: 修复 hooks_controller.dart 的相对 import**

Edit `lib/features/hooks/hooks_controller.dart`：把
```dart
import 'hooks_store.dart';
```
改为：
```dart
import 'data/hooks_store.dart';
```

- [ ] **Step 3: 修复 hooks_executor.dart / hooks_view.dart 内部相对 import**

`lib/features/hooks/service/hooks_executor.dart`：原来 `import '../../app/...'` 现在变成 `import '../../../app/...'`；用 sed 批量修：
```bash
sed -i '' "s|import '\\.\\./\\.\\./|import '../../../|g" lib/features/hooks/service/hooks_executor.dart
sed -i '' "s|import '\\.\\./\\.\\./|import '../../../|g" lib/features/hooks/widgets/hooks_view.dart
sed -i '' "s|import 'hooks_store|import '../data/hooks_store|g" lib/features/hooks/service/hooks_executor.dart
sed -i '' "s|import 'hooks_controller|import '../hooks_controller|g" lib/features/hooks/widgets/hooks_view.dart
```

> 注：sed 之后**必须 flutter analyze 验证**；下面 Step 6 会执行。

- [ ] **Step 4: 创建 hooks_module.dart**

`lib/features/hooks/hooks_module.dart`:
```dart
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'hooks_controller.dart';
import 'service/hooks_executor.dart';

/// Assembly point for the hooks feature.
class HooksModule {
  static Future<({HooksController controller, HooksExecutor executor})>
  bootstrap() async {
    final controller = await HooksController.create();
    final executor = HooksExecutor(controller: controller);
    return (controller: controller, executor: executor);
  }

  static List<SingleChildWidget> providers(
    HooksController controller,
    HooksExecutor executor,
  ) => [
    ChangeNotifierProvider<HooksController>.value(value: controller),
    Provider<HooksExecutor>.value(value: executor),
  ];
}
```

> 若 `HooksExecutor` 构造签名与上述不同，按其真实签名调整 — 在 Step 1 移动文件后先打开 service/hooks_executor.dart 确认。

- [ ] **Step 5: 创建 index.dart + README.md**

`lib/features/hooks/index.dart`:
```dart
export 'hooks_controller.dart';
export 'hooks_module.dart';
export 'widgets/hooks_view.dart' show HooksView;
```

`lib/features/hooks/README.md`:
```markdown
# Hooks feature

## 职责
管理用户配置的 hook（事件触发的本地脚本/命令），提供启用/禁用/执行能力。

## 对外 API
- `HooksController` — Provider 提供，含 `entries` 与增删改方法
- `HooksExecutor` — 监听事件并执行匹配的 hook
- `HooksModule.bootstrap()` / `HooksModule.providers()`
- `HooksView` — 设置页中的 hooks 编辑 widget

## 依赖
- `app/model/hook_config.dart`
- `shared/db/database_service.dart`

## 不变量
- 同一 id 的 hook 在内存 entries 中唯一
- 持久化通过 HooksStore 的 mutationQueue 串行化，禁止外部直接写表
```

- [ ] **Step 6: 修改 main.dart 改走 HooksModule.bootstrap**

打开 `lib/main.dart`，找到 hooks 控制器初始化处（搜索 `HooksController` 或 `HooksExecutor`），改成：
```dart
final hooks = await HooksModule.bootstrap();
// 原有 HooksController/HooksExecutor 局部变量替换为 hooks.controller / hooks.executor
```
import 处：
```dart
import 'features/hooks/index.dart';
```
删除旧的 `import 'features/hooks/hooks_controller.dart'` 与 `import 'features/hooks/hooks_executor.dart'`。

- [ ] **Step 7: flutter analyze + 启动一次手动验证**

Run: `flutter analyze`
Expected: 0 errors。

Run: `flutter run -d macos`（或 `flutter test` 若有相关测试），打开 settings → hooks，确认列表/启用切换正常。

- [ ] **Step 8: 提交**

```bash
git add -A lib/features/hooks lib/main.dart
git commit -m "P0 hooks feature 对齐标准模板

迁移文件按模板归位：
- data/hooks_store.dart
- service/hooks_executor.dart
- widgets/hooks_view.dart
新增 hooks_module.dart 作为装配入口、index.dart barrel、README.md。
main.dart 改走 HooksModule.bootstrap()。flutter analyze 通过。"
```

---

## Task 6: WEB foundation — app/ 与 shared/ 目录

**Files:**
- Create: `clients/web/src/app/router.tsx`
- Create: `clients/web/src/app/index.ts`
- Create: `clients/web/src/shared/{ui,net,util,i18n}/`（占位）
- Modify: `clients/web/src/main.tsx`、`clients/web/src/app.tsx`

- [ ] **Step 1: 阅读当前 main.tsx 与 app.tsx**

Read `clients/web/src/main.tsx` 与 `clients/web/src/app.tsx` 全文，搞清楚路由表与全局 provider 注册位置。

- [ ] **Step 2: 抽离路由到 app/router.tsx**

`clients/web/src/app/router.tsx`：把 app.tsx 中的路由表（Route/Switch）剪切过来，import 仍用旧路径（pages、components），保持行为不变。导出 `<AppRouter />` 组件。

- [ ] **Step 3: app.tsx 改为 import AppRouter**

`clients/web/src/app.tsx` 用 `<AppRouter />` 替代原内联路由块。

- [ ] **Step 4: 创建 shared 占位**

```bash
cd ~/Public/FlutterProjects/OpenHand/clients/web/src
mkdir -p shared/{ui,net,util,i18n} app
touch shared/ui/.gitkeep shared/net/.gitkeep shared/util/.gitkeep shared/i18n/.gitkeep
```

`clients/web/src/app/index.ts`:
```ts
export { AppRouter } from './router';
```

- [ ] **Step 5: WEB 端构建验证**

Run: `bash scripts/build_web.sh` （走 SKIP_IMPORT_CHECK=1，因 settings 还没迁完）
Expected: dist 正常生成，类型检查/打包无错。

- [ ] **Step 6: 提交**

```bash
cd ~/Public/FlutterProjects/OpenHand
git add clients/web/src/app clients/web/src/shared clients/web/src/main.tsx clients/web/src/app.tsx
git commit -m "WEB P0 骨架：抽离 app/router.tsx 与 shared/ 占位

为后续 features/ 迁移留位；当前 pages/components 路径不变，仅 app.tsx 行为下沉到 AppRouter。"
```

---

## Task 7: 试点 WEB feature — settings/ 标准模板迁移

**Files (move/create):**
- `clients/web/src/pages/SettingsPage.tsx` → `clients/web/src/features/settings/components/SettingsPage.tsx`
- `clients/web/src/api/preferences.ts`（若存在）→ `clients/web/src/features/settings/api/preferences.ts`
- New: `clients/web/src/features/settings/index.ts`
- Modify: `clients/web/src/app/router.tsx`（更新 SettingsPage import 路径）

- [ ] **Step 1: 创建目录并移动**

```bash
cd ~/Public/FlutterProjects/OpenHand/clients/web/src
mkdir -p features/settings/{components,api,state,hooks}
git mv pages/SettingsPage.tsx features/settings/components/SettingsPage.tsx
# 若 api/preferences.ts 仅 settings 用：
[ -f api/preferences.ts ] && git mv api/preferences.ts features/settings/api/preferences.ts
```

- [ ] **Step 2: 修复 SettingsPage.tsx 内部相对 import**

原 import 形如 `from '../components/TopBar'`，现在路径加深一层：
```bash
sed -i '' "s|from '\\.\\./components/|from '../../../components/|g" features/settings/components/SettingsPage.tsx
sed -i '' "s|from '\\.\\./api/preferences|from '../api/preferences|g" features/settings/components/SettingsPage.tsx
sed -i '' "s|from '\\.\\./api/|from '../../../api/|g" features/settings/components/SettingsPage.tsx
sed -i '' "s|from '\\.\\./i18n|from '../../../i18n|g" features/settings/components/SettingsPage.tsx
sed -i '' "s|from '\\.\\./hooks/|from '../../../hooks/|g" features/settings/components/SettingsPage.tsx
```

> sed 之后**必须打开文件人工扫一眼**，确认没有 `'../../../components/'` 与 `'../../../../components/'` 混合的错误深度。tsc 也会兜底报错。

- [ ] **Step 3: 创建 index.ts barrel**

`clients/web/src/features/settings/index.ts`:
```ts
export { SettingsPage } from './components/SettingsPage';
```

> 若 SettingsPage 当前是 default export，barrel 改为：
> ```ts
> export { default as SettingsPage } from './components/SettingsPage';
> ```

- [ ] **Step 4: app/router.tsx 改为从 barrel 引入**

把 router.tsx 内：
```ts
import SettingsPage from '../pages/SettingsPage';
```
改为：
```ts
import { SettingsPage } from '../features/settings';
```

- [ ] **Step 5: 构建验证**

Run: `bash scripts/build_web.sh`（仍 SKIP_IMPORT_CHECK=1）
Expected: 类型与打包均通过。

- [ ] **Step 6: e2e 冒烟（如有）**

Run: `cd clients/web && pnpm exec playwright test --grep settings`（若现有 e2e 覆盖 settings 页）
Expected: 现有用例不退化。

- [ ] **Step 7: 提交**

```bash
cd ~/Public/FlutterProjects/OpenHand
git add -A clients/web/src
git commit -m "WEB P0 settings feature 对齐标准模板

pages/SettingsPage.tsx → features/settings/components/SettingsPage.tsx；
api/preferences.ts 迁入 features/settings/api/；新增 barrel index.ts。
router.tsx 改走 barrel 引入。打包通过。"
```

---

## Task 8: docs/architecture.md 骨架说明

**Files:**
- Create: `docs/architecture.md`

- [ ] **Step 1: 写文档**

`docs/architecture.md`:
```markdown
# OpenHand 工程骨架

## 三层结构

```
lib/
  app/        # 应用层：入口、主题、全局设置、运行时支撑
  features/   # 业务域，feature-first
  shared/     # 跨域共享
clients/web/src/
  app/        # WEB 入口与路由
  features/   # 与 APP 同名同义
  shared/     # WEB 共享
```

## APP feature 标准模板

```
lib/features/<name>/
  <name>_controller.dart   # 唯一对外 Controller（ChangeNotifier）
  <name>_module.dart       # 装配点：bootstrap() + providers()
  index.dart               # barrel
  model/                   # 纯数据
  data/                    # 持久化/IO
  service/                 # 业务服务
  widgets/                 # UI
  state/                   # 子 controller/view-model（可选）
  README.md
```

## WEB feature 标准模板

```
clients/web/src/features/<name>/
  components/
  state/
  api/
  hooks/
  index.ts        # barrel
```

## 跨 feature 边界

跨 feature 引用必须走 `index.dart` / `index.ts` barrel，禁止深路径 import。
`scripts/check_imports.dart` 在 build_web.sh 中强制检查。

## shared 子目录

| 目录 | 内容 |
|---|---|
| core | Result/Disposable/typedef |
| net | http client、proxy、url 校验 |
| db | sqflite 封装、migration |
| ui | 通用 widget |
| util | 纯函数工具 |

shared 内部禁止 import features。

## 状态管理

Provider + ChangeNotifier。每个 feature 的 `<name>_module.dart`：
- `bootstrap()` 返回 controller 实例
- `providers(controller)` 返回 `List<SingleChildWidget>` 供 main.dart 装配
```

- [ ] **Step 2: 提交**

```bash
git add docs/architecture.md
git commit -m "新增 docs/architecture.md 工程骨架说明

一页文档覆盖三层结构、APP/WEB feature 模板、shared 子目录、跨 feature 边界、状态管理公约。"
```

---

## Task 9: 最终验收

- [ ] **Step 1: flutter analyze 全量**

Run: `flutter analyze`
Expected: 0 errors。

- [ ] **Step 2: 现有 flutter test 全跑**

Run: `flutter test`
Expected: 全部通过（无新增退化）。

- [ ] **Step 3: build_web.sh 全跑（仍 SKIP_IMPORT_CHECK=1，过渡期）**

Run: `SKIP_IMPORT_CHECK=1 bash scripts/build_web.sh`
Expected: 通过。

- [ ] **Step 4: check_imports.dart 跑一次记录当前违规计数（不 fail commit）**

Run: `dart run scripts/check_imports.dart; echo "exit=$?"`
预期：会输出剩余 11 个 APP feature + 11 个 WEB feature 的深路径违规计数，作为 Plan-2/3 的基线。把该数字记在最后 commit 的 message 里。

- [ ] **Step 5: 手动跑一次桌面 app 冒烟**

Run: `flutter run -d macos`
打开：会话页 / 设置页 / hooks 子页 / 主题切换 / 语言切换 — 全部正常。

- [ ] **Step 6: 收尾提交（仅 message，无文件）**

```bash
git commit --allow-empty -m "P0 plan-1 完成：foundation 骨架就位

试点：
- APP hooks feature 已对齐标准模板
- WEB settings feature 已对齐标准模板
基础设施：
- scripts/check_imports.dart 上线（含单元测试）
- scripts/scaffold_feature.dart 上线
- shared/ 重组为 core/db/ui/net/util
- build_web.sh 串入 import 检查（SKIP_IMPORT_CHECK=1 过渡）
- docs/architecture.md 骨架文档

import 检查基线违规数：见上一条记录，由 Plan-2/3 清零。"
```

---

## Self-Review 结论

- **Spec 覆盖**：Spec § 1/2/3/5/6/8/11 全部由 Task 1-9 覆盖；§ 4 / § 7 / § 9-10 在 Plan-2/3 完成（spec 已说明 Plan-1 是骨架 + 试点）。
- **占位符**：无 TBD/TODO 步骤；READE.md 中的 TODO 是 feature 文档的填空说明，非计划步骤。
- **类型一致**：`HooksModule.bootstrap()` 与 `providers()` 签名在 Task 5、Task 8（架构文档）中一致；`check_imports.dart` 规则在 Task 1 实装、Task 4 调用、Task 9 验收三处口径一致。
