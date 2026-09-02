import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_server_health.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_tool_discovery_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('后台刷新期间保留已有失败提示', () async {
    final directory = await Directory.systemTemp.createTemp(
      'openhand-mcp-controller-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final configFile = File('${directory.path}/mcp_servers.json');
    await configFile.writeAsString('''
{
  "mcpServers": {
    "测试服务": {
      "enabled": true,
      "probeEnabled": true,
      "type": "streamable_http",
      "url": "https://example.com/mcp"
    }
  }
}
''');
    final discovery = _ControlledDiscoveryService();
    final controller = await McpController.create(
      initialFilePath: configFile.path,
      toolDiscoveryService: discovery,
    );
    addTearDown(controller.shutdown);

    discovery.completeNext(_failedCatalog('首次失败'));
    await controller.refreshServerTools('测试服务');
    expect(controller.toolCatalogFor('测试服务').errorMessage, '首次失败');

    final refresh = controller.refreshServerTools(
      '测试服务',
      clearCachedTools: false,
    );
    await Future<void>.delayed(Duration.zero);
    final duringRefresh = controller.toolCatalogFor('测试服务');
    expect(duringRefresh.status, McpToolCatalogStatus.failed);
    expect(duringRefresh.errorMessage, '首次失败');

    discovery.completeNext(_failedCatalog('再次失败'));
    await refresh;
    expect(controller.toolCatalogFor('测试服务').errorMessage, '再次失败');
  });
}

McpToolCatalog _failedCatalog(String message) {
  return McpToolCatalog(
    status: McpToolCatalogStatus.failed,
    errorMessage: message,
    lastScannedAt: DateTime.now().toUtc(),
  );
}

class _ControlledDiscoveryService implements McpToolDiscoveryService {
  final List<Completer<McpToolCatalog>> _requests = [];
  final List<McpToolCatalog> _pendingResults = [];

  void completeNext(McpToolCatalog catalog) {
    if (_requests.isEmpty) {
      _pendingResults.add(catalog);
      return;
    }
    _requests.removeAt(0).complete(catalog);
  }

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) {
    if (_pendingResults.isNotEmpty) {
      return Future.value(_pendingResults.removeAt(0));
    }
    final completer = Completer<McpToolCatalog>();
    _requests.add(completer);
    return completer.future;
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) async {
    return const McpServerHealth(status: McpServerHealthStatus.healthy);
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const {},
    String? toolCallId,
    Map<String, String>? customHeaders,
    Future<void>? cancelSignal,
  }) async {
    return const McpToolCallResult(outputText: '');
  }

  @override
  void dispose() {}
}
