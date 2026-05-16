import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'memory_controller.dart';

/// Assembly point for the memory feature.
///
/// Initialization is intentionally lightweight (synchronous-in-async wrapper)
/// to preserve the "non-critical-path lazy init" semantics — store hydration
/// happens on first `refresh()` / mutation, not at boot.
class MemoryModule {
  MemoryModule._({required this.controller});

  final MemoryController controller;

  static Future<MemoryModule> bootstrap() async {
    final controller = MemoryController.uninitialized();
    return MemoryModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(MemoryModule m) => [
    ChangeNotifierProvider<MemoryController>.value(value: m.controller),
  ];
}
