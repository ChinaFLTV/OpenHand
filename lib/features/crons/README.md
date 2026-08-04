# 定时任务模块

## 职责
管理定时任务（cron jobs）：解析 cron 表达式、调度触发、执行子进程、维护执行历史。

## 对外 API
- `CronsController` — Provider 提供，含 entries / `initialize()` / `runNow()` 等
- `CronsModule.bootstrap()` / `CronsModule.providers(m)`
- `runCronHistoryCleanupOnce(...)` — 启动期单次清理（main.dart 调用）
- `CronsView` — 设置页内的 cron 编辑 widget
- barrel: `features/crons/index.dart`

## 依赖
- `app/model/cron_config.dart`（领域模型在 app/ 而非 feature 内）
- `app/support/{openhand_notification_service,safe_subprocess,silent_log}.dart`
- 跨 feature 依赖必须通过对应 feature barrel；`scripts/check_imports.dart` 会在 Web 构建脚本中强制检查。

## 不变量
- 构造同步完成；首次 `initialize()` 触发 sqlite 读取与调度启动
- isOperating 期间禁止并发触发
- 同一 id 的 cron entry 在 entries 内唯一
