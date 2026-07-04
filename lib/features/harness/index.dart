// harness is a widget-bundle feature (no Controller).
// barrel exposes 入口 widget、领域模型与 home/main 需要的 service 类型。
export 'data/harness_session_store.dart';
export 'model/harness_phase.dart';
export 'model/harness_phase_context_config.dart';
export 'model/harness_role_config.dart';
export 'model/harness_session_config.dart';
export 'model/harness_session_record.dart';
export 'service/harness_api_phase_runner.dart';
export 'service/harness_cli_catalog.dart';
export 'service/harness_orchestrator.dart';
export 'service/harness_prompt_builder.dart';
export 'widgets/harness_engineering_dialog.dart' show HarnessEngineeringDialog;
export 'widgets/harness_session_dashboard.dart'
    show HarnessSessionPane, HarnessSessionPaneController;
