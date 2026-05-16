# OpenHand 工程骨架重构（P0）设计

- 日期：2026-05-16
- 状态：草案 → 待用户复核
- 范围：APP 端（lib/）+ WEB 端（clients/web/src/）+ Prompt 资产骨架占位
- 基调：激进 — 允许重写超大文件、抽象层、重定义 service 边界
- 后续阶段：P1 ai 拆解 / P2 home 拆解 / P3 其余 features 对齐 / P4 WEB 收尾 / P5 Prompt 重写 / P6 性能丝滑收尾

## 1. 目标

把现有「分散得不彻底」的三层骨架升级为强制公约 + 可执行模板：
- 任意 PR 与后续子项目「按格子放东西」，结构一眼可辨。
- APP 与 WEB 在 feature 划分与命名上对齐，形成共享心智模型。
- 公约由脚本强制执行，违反即 CI fail。

## 2. APP feature 标准模板

```
lib/features/<name>/
  <name>_controller.dart   # 唯一对外 Controller（ChangeNotifier）
  <name>_module.dart       # 装配入口：Provider 工厂、初始化、dispose
  index.dart               # barrel：对外符号
  model/                   # 纯数据（immutable，无 Flutter 依赖）
  data/                    # 持久化/序列化/IO（store, repository, cache）
  service/                 # 业务服务（无 UI 依赖）
  widgets/                 # UI 组件（页面、片段）
  state/                   # 子 controller / view-model（可选）
  README.md                # 一页：职责 / 对外 API / 依赖 / 不变量
```

强制规则：
1. `widgets/` 不直接 import `service/`；UI ↔ service 必须经 Controller。
2. 跨 feature 调用一律走 `index.dart` barrel 暴露的符号，禁止深路径 import 形如 `features/ai/service/foo.dart`。
3. Controller 在 `<name>_module.dart` 装配；main.dart 仅按顺序调用 module 工厂。
4. 每个 feature 的 README.md 必须存在，列出对外 API 与不变量。

## 3. lib/shared 重组

```
lib/shared/
  core/   # Result/Outcome、disposable、错误类型、typedef
  net/    # http client、proxy、url 校验
  db/     # sqflite 封装、migration
  ui/     # 通用 widget、theme tokens、scroll physics
  util/   # 纯函数工具（字符串、时间、路径）
```

迁移规则：
- 旧 `lib/shared/widgets` → `lib/shared/ui`。
- 旧 `lib/shared/data` → 按用途拆到 `db/` 或 `core/`。
- shared 内部禁止反向 import features。

## 4. WEB 端镜像（全量）

```
clients/web/src/
  app/                 # 入口、router、theme、全局 provider
  features/<name>/     # 与 APP 同名同义（chat / settings / mcp / skills / memory / hardness / message_gateway / instructions / plugin_service / hooks / crons / home）
    components/
    state/
    api/
    hooks/
    index.ts           # barrel
  shared/
    ui/
    net/
    util/
    i18n/
```

迁移规则：
- 现有 `src/{components,pages,hooks,state,services,api,theme,utils,styles,i18n}` 按归属切到 `features/<name>/` 或 `shared/`。
- 路由集中在 `app/router.tsx`，feature 自身只暴露 page 组件与 hook。
- 跨 feature 引用一律 `import { X } from '@/features/<name>'`（走 barrel），禁止深路径 `@/features/<name>/components/...`。

## 5. CI 级深路径 import 检查

新增 `scripts/check_imports.dart`：
- 扫描 `lib/features/**/*.dart`，匹配 `import 'package:openhand/features/<other>/...'` 或相对 `../<other>/<sub>/...`，若不是 `index.dart` 一律 fail。
- 扫描 `lib/features/**/widgets/**` 中的 `import .../service/...`，fail。
- 同步扫描 `clients/web/src/features/**/*.{ts,tsx}` 中的深路径 import。

集成点：
- `scripts/build_web.sh` 末尾追加 `dart run scripts/check_imports.dart`，git commit 前必跑。
- 后续若需要可升级到 `custom_lint`，本阶段不引入第三方依赖。

## 6. Prompt 资产骨架（P0 仅占位，P5 落地）

```
assets/prompts/
  _shared/        # 公共片段：identity、tool_use、style、safety
  presets/<name>/ # 每个角色：main.md + sections/*.md
  manifest.yaml   # 角色 → 片段映射，构建时拼装
```

P0 任务：建立空目录与 `manifest.yaml` 框架，不动现有 prompt 内容；现有文件保留在原路径，P5 阶段按 Claude Code 风格逐个改写并搬入新结构。

## 7. 状态管理与装配公约

- 保留 Provider + `ChangeNotifier` 范式，不引入 Riverpod/Bloc。
- 每个 feature 的 `<name>_module.dart` 暴露：
  - `<Name>Module.bootstrap(...)`：异步初始化，返回 Controller 实例。
  - `<Name>Module.providers(...)`：返回 `List<SingleChildWidget>`，供 main.dart 装配。
- main.dart 减肥：仅做 Zone/error/proxy/log 等运行时支撑，把 controller 实例化全部下沉到各 module。

## 8. 验收标准（P0 Done 定义）

1. 12 个 APP feature 目录结构 100% 符合模板（含 `<name>_module.dart`、`index.dart`、`README.md`）。
2. `lib/shared` 完成五子目录重组，旧路径全部更新。
3. `clients/web/src` 全量迁移到 `app/` + `features/` + `shared/`，旧目录清空或删除。
4. `scripts/check_imports.dart` 实装，本地与 `build_web.sh` 内调用通过。
5. `flutter analyze` 0 error；`flutter test` 通过。
6. `scripts/build_web.sh` 一次通过。
7. 新增 `docs/architecture.md`，一页骨架说明（含目录树 + 公约要点）。

## 9. 不在 P0 范围

- 不重写 ai/、home/ 超大文件的内部实现（P1/P2 处理）。
- 不改 Prompt 文本内容（P5 处理）。
- 不引入新的状态管理库或网络框架。
- 不做性能专项优化（P6 处理）。

## 10. 风险与对策

| 风险 | 对策 |
|---|---|
| 大量文件移动导致 import 改动暴雷 | 每个 feature 单独提交；每次 commit 前跑 `flutter analyze` + `check_imports.dart` |
| WEB 全量迁移耗时长 | 在实施计划里按 feature 切片，与 APP feature 一一并行 |
| barrel 暴露过多导致循环 import | barrel 仅导出 Controller、Module、Page 三类符号；model/service 不直接对外 |
| README/module 形式主义 | 每个 README 必须含「对外 API」「不变量」两节，CI 脚本检查存在性 |

## 11. 提交节奏

- 每个 feature 一个 commit，标题：`P0 重构 <feature>：对齐模板与 barrel`。
- shared 重组一个 commit：`P0 shared/ 重组为 core/net/db/ui/util`。
- WEB features 按 feature 切片提交。
- check_imports.dart + build_web.sh 整合一个 commit。
- 全部完成后再 commit 一次 `docs/architecture.md`。
