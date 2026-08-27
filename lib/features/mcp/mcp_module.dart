import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'data/mcp_store.dart';
import 'mcp_controller.dart';
import 'service/mcp_tool_discovery_service.dart';

/// 模块构造保持轻量；`main.dart` 通过 [McpController.refresh] 后台加载服务列表。
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
