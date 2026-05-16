# Hooks feature

## 职责
管理用户配置的 hook（事件触发的本地脚本/命令），提供启用/禁用/执行能力。

## 对外 API
- `HooksController` — Provider 提供，含 `entries` 与增删改方法
- `HooksExecutor` — 监听事件并执行匹配的 hook，含 `pruneStaleTempFiles` 静态方法
- `HooksModule.bootstrap()` / `HooksModule.providers()` — 装配入口
- `HooksView` — 设置页中的 hooks 编辑 widget

## 依赖
- `app/model/hook_config.dart`
- `app/support/openhand_paths.dart`
- `shared/db/database_service.dart`
- `shared/ui/animated_dialog.dart` / `appear_once.dart` / `openhand_dialog_action_button.dart`

## 不变量
- 同一 id 的 hook 在内存 entries 中唯一
- 持久化通过 HooksStore 的 mutationQueue 串行化，禁止外部直接写表
