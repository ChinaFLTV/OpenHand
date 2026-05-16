// hardness is a widget-bundle feature (no Controller).
// barrel exposes 入口 widget、领域模型与 home/main 需要的 service 类型。
export 'data/hardness_session_store.dart';
export 'model/hardness_phase.dart';
export 'model/hardness_phase_context_config.dart';
export 'model/hardness_role_config.dart';
export 'model/hardness_session_config.dart';
export 'model/hardness_session_record.dart';
export 'service/hardness_api_phase_runner.dart';
export 'service/hardness_cli_catalog.dart';
export 'service/hardness_orchestrator.dart';
export 'service/hardness_prompt_builder.dart';
export 'widgets/hardness_engineering_dialog.dart'
    show HardnessEngineeringDialog, showHardnessEngineeringDialog;
export 'widgets/hardness_session_dashboard.dart'
    show
        HardnessSessionDashboard,
        HardnessSessionPane,
        HardnessSessionPaneController;
