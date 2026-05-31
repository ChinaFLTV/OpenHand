import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'memory_controller.dart';

/// Assembly point for the memory feature.
///
/// Initialization stays lightweight (synchronous-in-async wrapper). `main.dart`
/// currently constructs the controller during boot and immediately schedules
/// `controller.refresh()` in the background so memory hydration does not block
/// first paint while still becoming available shortly after startup.
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
