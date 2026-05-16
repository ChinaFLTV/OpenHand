import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'hooks_controller.dart';
import 'service/hooks_executor.dart';

/// Assembly point for the hooks feature.
///
/// Usage:
///   final hooks = await HooksModule.bootstrap();
///   // ... build provider tree ...
///   ...HooksModule.providers(hooks),
class HooksModule {
  HooksModule._({required this.controller, required this.executor});

  final HooksController controller;
  final HooksExecutor executor;

  static Future<HooksModule> bootstrap() async {
    final controller = await HooksController.create();
    final executor = HooksExecutor(controller: controller);
    return HooksModule._(controller: controller, executor: executor);
  }

  static List<SingleChildWidget> providers(HooksModule hooks) => [
    ChangeNotifierProvider<HooksController>.value(value: hooks.controller),
    // HooksExecutor is stateless (subprocesses are scoped per executeEvent);
    // no dispose hook needed. Stateful services should use
    // `Provider<T>(create: ..., dispose: ...)` instead of `.value`.
    Provider<HooksExecutor>.value(value: hooks.executor),
  ];
}
