// Re-export the cross-feature domain models so external callers need only one
// import for the hooks feature. HookEntry/HookEvent currently live in
// `app/model/` because they predate the feature-first reorg.
export '../../app/model/hook_config.dart' show HookEntry, HookEvent;

export 'hooks_controller.dart';
export 'hooks_module.dart';
export 'service/hooks_executor.dart';
export 'widgets/hooks_view.dart' show HooksView;
