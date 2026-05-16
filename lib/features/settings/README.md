# Settings feature（widget-bundle 形态）

## 职责
桌面应用设置页：偏好、AI 模型、命令规则、代理、内嵌工具开关、数据清理、prompt cache 等。

## 形态
本 feature 没有自身 Controller，使用 `lib/app/state/SettingsController`（全局）。
因此不提供 `SettingsModule`，仅通过 barrel 暴露入口 widget 与少量顶层 dialog 函数。

## 对外 API
- `SettingsView` — 设置页主入口
- `showAiModelEditorDialog(...)` — 顶层函数，弹出 AI 模型编辑对话框（home composer 也会用到）
- `ThreadSessionManagementDialog` — 会话管理对话框
- barrel: `features/settings/index.dart`

## 文件组织
- `widgets/settings_view.dart` — 主页面，组合 15 个 `_settings_*.dart` 片段
- `widgets/_settings_*.dart` — 内部 widget 片段（不对外暴露）
- `widgets/prompt_cache_breakpoint_bar.dart` — prompt 缓存断点 widget
- `widgets/thread_session_management_dialog.dart` — 会话管理对话框
- `data_cleanup/` — 数据清理服务 / 对话框（feature 内私有）

## 不变量
- `_settings_*.dart` 文件不被 feature 外引用
- `SettingsView` 内部组合所有片段；新增设置段落新增一个 `_settings_*.dart` 文件
- 全局 SettingsController 始终由 app 层装配，feature 仅消费
