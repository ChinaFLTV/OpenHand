import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'plugin_service_controller.dart';

/// Assembly point for the plugin_service feature.
///
/// Construction is synchronous; the controller's first scan happens on
/// demand from the UI (not at boot).
class PluginServiceModule {
  PluginServiceModule._({required this.controller});

  final PluginServiceController controller;

  static Future<PluginServiceModule> bootstrap() async {
    final controller = PluginServiceController();
    return PluginServiceModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(PluginServiceModule m) => [
    ChangeNotifierProvider<PluginServiceController>.value(value: m.controller),
  ];
}
