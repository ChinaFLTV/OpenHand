# Skills feature

## 职责
管理本地 Claude Code skills（包含从远程市场拉取的 skill 安装/卸载）；首次访问时懒加载磁盘扫描。

## 对外 API
- `SkillsController` — Provider 提供，含 `skills / isLoading` 与 `refresh / install / uninstall` 等方法
- `LocalSkill` — 领域模型（barrel 再导出）
- `SkillsModule.bootstrap(initialStoragePath:)` / `SkillsModule.providers(m)`
- `SkillsView` / `showSkillMarketDialog` — 设置页 widget
- barrel: `features/skills/index.dart`

## 依赖
- `data/skills_repository.dart`（feature 内私有，磁盘扫描 + 安装/卸载）
- main.dart 通过 `OpenHandPaths.skillsDir` 注入 `initialStoragePath`

## 不变量
- skills 列表按 slug 字典序稳定
- 构造同步完成，首次 refresh 前 isLoading = true
- 跨实例不应共享 storagePath
