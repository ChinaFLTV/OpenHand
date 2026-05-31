import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'instructions_controller.dart';

/// Assembly point for the instructions feature.
///
/// Construction is intentionally lightweight and synchronous. `main.dart`
/// currently bootstraps the module at app start, then schedules
/// `controller.refresh()` in the background so sqlite hydration stays off the
/// first-frame critical path while the feature remains ready soon after boot.
class InstructionsModule {
  InstructionsModule._({required this.controller});

  final InstructionsController controller;

  static Future<InstructionsModule> bootstrap() async {
    final controller = InstructionsController.uninitialized();
    return InstructionsModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(InstructionsModule m) => [
    ChangeNotifierProvider<InstructionsController>.value(value: m.controller),
  ];
}
