import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'data/instructions_store.dart';
import 'instructions_controller.dart';

/// Assembly point for the instructions feature.
///
/// Initialization is intentionally lightweight (synchronous) to preserve
/// the "non-critical-path lazy init" semantics — the controller's heavy
/// store hydration happens on first access, not at app boot.
class InstructionsModule {
  InstructionsModule._({required this.controller});

  final InstructionsController controller;

  static Future<InstructionsModule> bootstrap({
    InstructionsStore? store,
  }) async {
    final controller = InstructionsController.uninitialized(store: store);
    return InstructionsModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(InstructionsModule m) => [
    ChangeNotifierProvider<InstructionsController>.value(value: m.controller),
  ];
}
