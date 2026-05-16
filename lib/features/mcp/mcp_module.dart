import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'data/mcp_store.dart';
import 'mcp_controller.dart';
import 'service/mcp_tool_discovery_service.dart';

/// Assembly point for the mcp feature.
///
/// Construction is synchronous via [McpController.uninitialized] — server-list
/// load happens in [McpController.refresh], kicked off from main.dart.
///
/// Bootstrap takes `initialFilePath` because the underlying lazy-init factory
/// requires it (same nuance as SkillsModule).
class McpModule {
  McpModule._({required this.controller});

  final McpController controller;

  static Future<McpModule> bootstrap({
    required String initialFilePath,
    Duration healthCheckInterval = const Duration(seconds: 30),
    int autoProbeConcurrency = McpController.defaultAutoProbeConcurrency,
    McpStore? store,
    McpToolDiscoveryService? toolDiscoveryService,
  }) async {
    final controller = McpController.uninitialized(
      initialFilePath: initialFilePath,
      store: store,
      toolDiscoveryService: toolDiscoveryService,
      healthCheckInterval: healthCheckInterval,
      autoProbeConcurrency: autoProbeConcurrency,
    );
    return McpModule._(controller: controller);
  }

  static List<SingleChildWidget> providers(McpModule m) => [
    ChangeNotifierProvider<McpController>.value(value: m.controller),
  ];
}
