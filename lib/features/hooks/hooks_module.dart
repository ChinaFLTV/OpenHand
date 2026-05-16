import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'hooks_controller.dart';
import 'service/hooks_executor.dart';

/// Assembly point for the hooks feature.
///
/// main.dart should call [HooksModule.bootstrap] once at startup to obtain
/// the controller+executor pair, then mount [HooksModule.providers] in the
/// global provider tree.
class HooksModule {
  HooksModule._();

  static Future<({HooksController controller, HooksExecutor executor})>
  bootstrap() async {
    final controller = await HooksController.create();
    final executor = HooksExecutor(controller: controller);
    return (controller: controller, executor: executor);
  }

  static List<SingleChildWidget> providers(
    HooksController controller,
    HooksExecutor executor,
  ) => [
    ChangeNotifierProvider<HooksController>.value(value: controller),
    Provider<HooksExecutor>.value(value: executor),
  ];
}
