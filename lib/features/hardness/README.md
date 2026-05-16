# Hardness feature（widget-bundle 形态）

## 职责
"Hardness Engineering" 工作流：把 AI 会话拆成 phase × role，编排 prompt 与 CLI 工具链。

## 形态
无自身全局 Controller；状态在 `service/hardness_orchestrator` + `data/hardness_session_store` 内自托管，由入口 dialog/dashboard 内部 Provider 树持有。不挂在 main.dart 全局 providers 上。

## 对外 API（barrel）
- `HardnessEngineeringDialog` / `showHardnessEngineeringDialog` — 入口对话框
- `HardnessSessionDashboard` — 会话仪表盘
- `HardnessOrchestrator` / `HardnessOrchestratorStatus` — service / 状态枚举
- `HardnessApiPhaseRunner` / `HardnessCliCatalog` / `HardnessPromptBuilder`
- `HardnessSessionStore` / `HardnessPhaseLogSnapshot`
- 领域模型：`HardnessPhase / HardnessRoleConfig / HardnessSessionConfig / HardnessSessionRecord / HardnessPhaseContextConfig`
- barrel: `features/hardness/index.dart`

## 文件组织
- `data/hardness_session_store.dart` — sqflite + 文件系统
- `service/hardness_{orchestrator, api_phase_runner, cli_catalog, prompt_builder}.dart`
- `widgets/hardness_engineering_dialog.dart`、`widgets/hardness_cli_{install,login}_dialog.dart`
- `widgets/hardness_session_dashboard.dart` 与 13 个 `*.part.dart` 共生（同目录、part of 同文件名）
- `widgets/hardness_pending_replay_badge.dart` — 列表项 badge widget
- `model/` — phase / role / session config / record 等领域模型

## 不变量
- 13 个 `*.part.dart` 必须与 `hardness_session_dashboard.dart` 同目录
- orchestrator 为单例式状态机，不要多实例化
- session record 改动必须通过 store 串行化
