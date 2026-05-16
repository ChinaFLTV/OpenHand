import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'crons_controller.dart';

/// Assembly point for the crons feature.
///
/// Construction is synchronous via [CronsController.uninitialized] — heavy
/// I/O (sqlite seed, scheduler bind, signal watcher) runs inside the
/// controller's `initialize()` method, kicked off from main.dart so boot
/// is not blocked.
class CronsModule {
  CronsModule._({required this.controller});

  final CronsController controller;

  static Future<CronsModule> bootstrap() async {
    final controller = CronsController.uninitialized();
    return CronsModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(CronsModule m) => [
    ChangeNotifierProvider<CronsController>.value(value: m.controller),
  ];
}
