import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/index.dart';
import 'package:openhand/features/web_reverse/index.dart';

void main() {
  group('WebReverseCdpMcpBridge', () {
    test('cached preparing snapshot is stable before discovery starts', () {
      final bridge = WebReverseCdpMcpBridge(
        discoveryService: _FakeDiscoveryService(),
      );
      final controller = _FakeWebReverseSessionController(
        browserAlive: true,
        port: 9223,
      );

      final first = bridge.cachedSnapshot(
        sessionId: 'session-1',
        sessionTemplateId: WebReverseCdpMcpBridge.templateId,
        controller: controller,
        existingServers: const <McpServer>[],
      );
      final second = bridge.cachedSnapshot(
        sessionId: 'session-1',
        sessionTemplateId: WebReverseCdpMcpBridge.templateId,
        controller: controller,
        existingServers: const <McpServer>[],
      );

      final firstCatalog = first.catalogsByServerName.values.single;
      final secondCatalog = second.catalogsByServerName.values.single;
      expect(first.diagnostic.status, WebReverseCdpMcpBridgeStatus.preparing);
      expect(second.diagnostic.status, WebReverseCdpMcpBridgeStatus.preparing);
      expect(firstCatalog.status, McpToolCatalogStatus.loading);
      expect(firstCatalog.lastScannedAt, isNull);
      expect(secondCatalog.lastScannedAt, isNull);
      expect(first.diagnostic.toJson(), second.diagnostic.toJson());

      bridge.dispose();
      controller.dispose();
    });
  });
}

class _FakeWebReverseSessionController extends WebReverseSessionController {
  _FakeWebReverseSessionController({
    required this.browserAlive,
    required this.port,
  }) : super(
         config: const WebReverseSessionConfig(
           targetUrl: 'https://example.com',
           objective: 'test',
           cdpPort: 9223,
           userDataDir: '/tmp/openhand-web-reverse-test',
           browserKind: WebReverseBrowserKind.chrome,
         ),
         executablePath: '/Applications/Google Chrome.app',
         artifactsRootDir: '/tmp/openhand-web-reverse-test-artifacts',
       );

  final bool browserAlive;
  final int? port;

  @override
  bool get isBrowserAlive => browserAlive;

  @override
  int? get cdpPort => port;
}

class _FakeDiscoveryService implements McpToolDiscoveryService {
  @override
  Future<McpToolCatalog> discoverTools(McpServer server) {
    throw StateError('cachedSnapshot must not start discovery');
  }

  @override
  Future<McpServerHealth> checkHealth(McpServer server) {
    throw UnimplementedError();
  }

  @override
  Future<McpToolCallResult> callTool({
    required McpServer server,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
    String? toolCallId,
    Map<String, String>? customHeaders,
  }) {
    throw UnimplementedError();
  }

  @override
  void dispose() {}
}
