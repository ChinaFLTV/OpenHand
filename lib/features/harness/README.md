# Harness feature（widget-bundle 形态）

## 职责
"Harness Engineering" 工作流：把 AI 会话拆成 phase × role，编排 prompt 与 CLI 工具链。

## 形态
无自身全局 Controller；状态在 `service/harness_orchestrator` + `data/harness_session_store` 内自托管，由入口 dialog/dashboard 内部 Provider 树持有。不挂在 main.dart 全局 providers 上。

## 对外 API（barrel）
- `HarnessEngineeringDialog` — 入口对话框
- `HarnessSessionPane` / `HarnessSessionPaneController` — 会话仪表盘面板
- `HarnessOrchestrator` / `HarnessOrchestratorStatus` — service / 状态枚举
- `HarnessApiPhaseRunner` / `HarnessCliCatalog` / `HarnessPromptBuilder`
- `HarnessSessionStore` / `HarnessPhaseLogSnapshot`
- 领域模型：`HarnessPhase / HarnessRoleConfig / HarnessSessionConfig / HarnessSessionRecord / HarnessPhaseContextConfig`
- barrel: `features/harness/index.dart`

## 文件组织
- `data/harness_session_store.dart` — sqflite + 文件系统
- `service/harness_{orchestrator, api_phase_runner, cli_catalog, prompt_builder, bounded_file_io}.dart`
- `widgets/harness_engineering_dialog.dart`、`widgets/harness_cli_{install,login}_dialog.dart`
- `widgets/harness_session_dashboard.dart` 与配套 `*.part.dart` 共生
- `widgets/harness_pending_replay_badge.dart` — 列表项 badge widget
- `model/` — phase / role / session config / record 等领域模型

## 不变量
- `*.part.dart` 必须与 `harness_session_dashboard.dart` 同目录并保持 `part of` 一致
- orchestrator 为单例式状态机，不要多实例化
- session record 改动必须通过 store 串行化
