# Plugin Service feature

## 职责
扫描、安装、更新、卸载本地插件；管理插件间依赖；通过事件向 UI 推送状态。

## 对外 API
- `PluginServiceController` — Provider 提供，含 `plugins / isLoading / isOperating / errorMessage` 与操作方法
- `PluginInfo` — 领域模型（barrel 再导出）
- `PluginServiceModule.bootstrap()` / `PluginServiceModule.providers(m)`
- `PluginServiceView` — 设置页内的插件管理 widget
- barrel: `features/plugin_service/index.dart`

## 依赖
- `service/plugin_scanner_service.dart`（feature 内私有）
- `service/plugin_lifecycle_service.dart`（feature 内私有）
- 跨 feature 依赖必须通过对应 feature barrel；`scripts/check_imports.dart` 会在 Web 构建脚本中强制检查。

## 不变量
- plugins 列表按扫描顺序稳定
- isOperating 期间禁止并发触发新操作
- 构造同步完成，不阻塞启动
