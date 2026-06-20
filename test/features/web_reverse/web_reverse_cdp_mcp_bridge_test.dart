import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/index.dart';
import 'package:openhand/features/web_reverse/index.dart';

void main() {
  group('WebReverseCdpMcpBridge', () {
    test('cached preparing snapshot is stable before discovery starts', () {
      final bridge = WebReverseCdpMcpBridge(
        discoveryService: _FakeDiscoveryService(throwOnDiscover: true),
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

    test('drops cached catalog when live controller loses CDP port', () async {
      final discoveryService = _FakeDiscoveryService();
      final bridge = WebReverseCdpMcpBridge(discoveryService: discoveryService);
      final controller = _FakeWebReverseSessionController(
        browserAlive: true,
        port: 9223,
      );

      final first = await bridge.buildSnapshot(
        sessionId: 'session-1',
        sessionTemplateId: WebReverseCdpMcpBridge.templateId,
        controller: controller,
        existingServers: const <McpServer>[],
      );
      expect(first.diagnostic.status, WebReverseCdpMcpBridgeStatus.ready);
      expect(discoveryService.discoverCount, 1);

      controller.port = null;
      final unavailable = await bridge.buildSnapshot(
        sessionId: 'session-1',
        sessionTemplateId: WebReverseCdpMcpBridge.templateId,
        controller: controller,
        existingServers: const <McpServer>[],
      );
      expect(unavailable.servers, isEmpty);
      expect(
        unavailable.diagnostic.status,
        WebReverseCdpMcpBridgeStatus.unavailable,
      );

      controller.port = 9223;
      final rebuilt = await bridge.buildSnapshot(
        sessionId: 'session-1',
        sessionTemplateId: WebReverseCdpMcpBridge.templateId,
        controller: controller,
        existingServers: const <McpServer>[],
      );
      expect(rebuilt.diagnostic.status, WebReverseCdpMcpBridgeStatus.ready);
      expect(discoveryService.discoverCount, 2);

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
  int? port;

  @override
  bool get isBrowserAlive => browserAlive;

  @override
  int? get cdpPort => port;
}

class _FakeDiscoveryService implements McpToolDiscoveryService {
  _FakeDiscoveryService({this.throwOnDiscover = false});

  static const McpToolCatalog _readyCatalog = McpToolCatalog(
    status: McpToolCatalogStatus.ready,
    tools: <McpTool>[
      McpTool(
        id: 'navigate_page',
        name: 'navigate_page',
        description: 'Navigate the live browser through CDP.',
        inputSchema: <String, Object?>{},
      ),
    ],
  );

  final bool throwOnDiscover;
  int discoverCount = 0;

  @override
  Future<McpToolCatalog> discoverTools(McpServer server) async {
    discoverCount++;
    if (throwOnDiscover) {
      throw StateError('cachedSnapshot must not start discovery');
    }
    return _readyCatalog;
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
