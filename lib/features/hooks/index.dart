// 统一导出 Hook 领域模型，调用方只需依赖本模块入口。
export '../../app/model/hook_config.dart' show HookEntry, HookEvent;

export 'hooks_controller.dart';
export 'hooks_module.dart';
export 'service/hooks_executor.dart';
export 'widgets/hooks_view.dart' show HooksView;
