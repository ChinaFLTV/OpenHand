# OpenHand 工程骨架

## 三层结构

```
lib/                          # Flutter APP
  app/        # 应用层：入口、主题、全局设置、运行时支撑
  features/   # 业务域，feature-first
  shared/     # 跨域共享

clients/web/src/              # Preact WEB 控制面板
  app/        # 入口与路由
  features/   # 与 APP 同名同义
  shared/     # 跨域共享
```

## APP feature 标准模板

```
lib/features/<name>/
  <name>_controller.dart   # 唯一对外 Controller（ChangeNotifier）
  <name>_module.dart       # 装配点：bootstrap() + providers(instance)
  index.dart               # barrel
  model/                   # 纯数据
  data/                    # 持久化 / IO
  service/                 # 业务服务（无 UI）
  widgets/                 # UI
  state/                   # 子 controller / view-model（可选）
  README.md
```

`<name>_module.dart` 暴露实例形态：

```dart
class <Name>Module {
  <Name>Module._({required this.controller, required this.<other>});
  final <Name>Controller controller;
  final <OtherType> <other>;

  static Future<<Name>Module> bootstrap() async { ... }
  static List<SingleChildWidget> providers(<Name>Module m) => [...];
}
```

main.dart 用法：
```dart
final fooModuleFuture = FooModule.bootstrap();
// ... 并行其他 bootstrap ...
final foo = await fooModuleFuture;
// providers list:
...FooModule.providers(foo),
```

约定：
- `Provider<T>.value` 仅用于 stateless service。有状态 service（含 stream/timer/subscription）改用 `Provider<T>(create:, dispose:)`，把 dispose 钩子写进模板 README。
- 跨 feature 的领域 model 通过 barrel `index.dart` re-export，调用方一次 import 拿到全部对外符号。
- `widgets/` 不直接 import `service/`；UI ↔ service 必须经 Controller。

## WEB feature 标准模板

```
clients/web/src/features/<name>/
  components/
  state/
  api/
  hooks/
  index.ts        # barrel：仅导出对外 page / hook
```

约定：
- 路由集中在 `clients/web/src/app/router.tsx`，feature 只导出 page 组件。
- 跨 feature 引用一律 `from '@/features/<name>'`（走 barrel），禁止深路径 `from '@/features/<name>/components/...'`。

## 跨 feature 边界（强制）

`scripts/check_imports.dart` 在 `scripts/build_web.sh` 末尾执行，规则：
1. `lib/features/<a>/**/*.dart` 中 import `features/<b>/<sub>`（b != a）只允许 `index.dart` / `<b>_module.dart` / `<b>_controller.dart`。
2. `lib/features/<a>/widgets/**` 禁止 import `service/...`。
3. `clients/web/src/features/<a>/**/*.{ts,tsx}` 中 import `@/features/<b>/<sub>` 只允许 sub 以 `index` 开头。

过渡期可 `SKIP_IMPORT_CHECK=1` 跳过。Plan-2/3 清零违规后该开关移除。

## shared 子目录

| 目录 | 内容 |
|---|---|
| `core/` | Result/Disposable/typedef（P1 落地） |
| `net/` | http client、proxy、url 校验 |
| `db/` | sqflite 封装、原子文件 |
| `ui/` | 通用 widget |
| `util/` | 纯函数工具 |

shared 内部禁止 import features。

## 状态管理

Provider + ChangeNotifier。controller 暴露 `entries`/`state` 与变更方法，UI 通过 `context.select`/`context.read` 订阅，service 与 store 不直接被 UI 引用。

## 装配链

```
main.dart
  ├── 各 <Name>Module.bootstrap() 并行启动（Future）
  ├── runZonedGuarded 包裹错误处理
  └── runApp(MultiProvider(providers: [
        ...HooksModule.providers(hooks),
        ...其他 module.providers(...),
        ChangeNotifierProvider<SettingsController>.value(...),
      ], child: OpenHandApp()))
```

## 脚手架与脚本

| 脚本 | 用途 |
|---|---|
| `scripts/scaffold_feature.dart <name>` | 按模板生成 APP feature 目录骨架 |
| `scripts/check_imports.dart [root]` | 扫描跨 feature 深路径 import，CI 闸门 |
| `scripts/build_web.sh` | 构建 WEB 产物到 assets/web/，末尾跑 check_imports |

## 阶段地图

| 阶段 | 范围 |
|---|---|
| P0 (本文档) | 骨架公约 + 脚手架 + shared 重组 + APP/WEB 试点 |
| P1 | `features/ai` 拆解（6.2 万行 → 子模块） |
| P2 | `features/home` 拆解（5.6 万行） |
| P3 | APP 余下 11 个 feature 对齐模板 |
| P4 | WEB 余下 11 个 feature 对齐 features/ 镜像 |
| P5 | 内置 Prompt 按 Claude Code 风格重写 |
| P6 | 性能丝滑收尾（虚拟化、帧节流、content-visibility） |
