import 'dart:async';

import '../../app/support/silent_log.dart';
import '../mcp/index.dart';
import 'web_reverse_session_controller.dart';

class WebReverseTransientMcpSnapshot {
  const WebReverseTransientMcpSnapshot({
    required this.servers,
    required this.catalogsByServerName,
  });

  static const empty = WebReverseTransientMcpSnapshot(
    servers: <McpServer>[],
    catalogsByServerName: <String, McpToolCatalog>{},
  );

  final List<McpServer> servers;
  final Map<String, McpToolCatalog> catalogsByServerName;
}

class WebReverseCdpMcpBridge {
  WebReverseCdpMcpBridge({
    McpToolDiscoveryService? discoveryService,
    this.catalogTimeout = defaultCatalogTimeout,
    this.catalogCacheTtl = defaultCatalogCacheTtl,
  }) : _discoveryService = discoveryService ?? DefaultMcpToolDiscoveryService();

  static const String templateId = 'web_reverse_expert';
  static const String cdpMcpPackage = 'chrome-devtools-mcp@latest';
  static const Duration defaultCatalogTimeout = Duration(seconds: 90);
  static const Duration defaultCatalogCacheTtl = Duration(minutes: 5);

  final McpToolDiscoveryService _discoveryService;
  final Duration catalogTimeout;
  final Duration catalogCacheTtl;
  final Map<String, String> _serverNamesBySessionId = <String, String>{};
  final Map<String, String> _serverSignaturesBySessionId = <String, String>{};
  final Map<String, _WebReverseCdpMcpCatalogCacheEntry> _catalogCache =
      <String, _WebReverseCdpMcpCatalogCacheEntry>{};

  Future<WebReverseTransientMcpSnapshot> buildSnapshot({
    required String? sessionId,
    required String? sessionTemplateId,
    required WebReverseSessionController? controller,
    required Iterable<McpServer> existingServers,
  }) async {
    final server = _serverFor(
      sessionId: sessionId,
      sessionTemplateId: sessionTemplateId,
      controller: controller,
      existingServers: existingServers,
      syncLifecycle: true,
    );
    if (server == null || sessionId == null) {
      return WebReverseTransientMcpSnapshot.empty;
    }
    final cacheKey = _catalogCacheKey(sessionId, server);
    final catalog = await _discoverCatalog(server: server, cacheKey: cacheKey);
    return WebReverseTransientMcpSnapshot(
      servers: <McpServer>[server],
      catalogsByServerName: <String, McpToolCatalog>{server.name: catalog},
    );
  }

  WebReverseTransientMcpSnapshot cachedSnapshot({
    required String? sessionId,
    required String? sessionTemplateId,
    required WebReverseSessionController? controller,
    required Iterable<McpServer> existingServers,
  }) {
    final server = _serverFor(
      sessionId: sessionId,
      sessionTemplateId: sessionTemplateId,
      controller: controller,
      existingServers: existingServers,
      syncLifecycle: false,
    );
    if (server == null || sessionId == null) {
      return WebReverseTransientMcpSnapshot.empty;
    }
    final cacheKey = _catalogCacheKey(sessionId, server);
    final catalog =
        _catalogCache[cacheKey]?.catalog ??
        McpToolCatalog(
          status: McpToolCatalogStatus.loading,
          warningMessage:
              'OpenHand is preparing the transient CDP MCP catalog for this Web Reverse session.',
          lastScannedAt: DateTime.now().toUtc(),
        );
    return WebReverseTransientMcpSnapshot(
      servers: <McpServer>[server],
      catalogsByServerName: <String, McpToolCatalog>{server.name: catalog},
    );
  }

  void stopSession(String sessionId) {
    final serverName = _serverNamesBySessionId.remove(sessionId);
    _serverSignaturesBySessionId.remove(sessionId);
    _catalogCache.removeWhere((key, _) => key.startsWith('$sessionId|'));
    if (serverName != null && serverName.isNotEmpty) {
      unawaited(McpStdioProcessManager.instance.stopServer(serverName));
    }
  }

  void dispose() {
    for (final sessionId in _serverNamesBySessionId.keys.toList()) {
      stopSession(sessionId);
    }
    _catalogCache.clear();
    _discoveryService.dispose();
  }

  McpServer? _serverFor({
    required String? sessionId,
    required String? sessionTemplateId,
    required WebReverseSessionController? controller,
    required Iterable<McpServer> existingServers,
    required bool syncLifecycle,
  }) {
    if (sessionId == null || sessionTemplateId != templateId) {
      return null;
    }
    if (controller == null || !controller.isBrowserAlive) {
      if (syncLifecycle) {
        stopSession(sessionId);
      }
      return null;
    }
    final port = controller.cdpPort;
    if (port == null || port <= 0) {
      return null;
    }
    final serverName = _serverName(
      sessionId,
      existingServers,
      persist: syncLifecycle,
    );
    final server = McpServer(
      name: serverName,
      type: McpServerType.stdio,
      enabled: true,
      probeEnabled: false,
      command: 'npx',
      args: <String>[
        '--yes',
        cdpMcpPackage,
        '--browser-url=http://127.0.0.1:$port',
      ],
    );
    if (syncLifecycle) {
      _syncServerSignature(sessionId, server);
    }
    return server;
  }

  String _serverName(
    String sessionId,
    Iterable<McpServer> existingServers, {
    required bool persist,
  }) {
    final existing = _serverNamesBySessionId[sessionId];
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final shortId = sessionId.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
    final shortToken = shortId.length <= 8 ? shortId : shortId.substring(0, 8);
    final base = 'web_reverse_cdp_$shortToken';
    final existingNames = existingServers.map((server) => server.name).toSet();
    var candidate = base;
    var suffix = 2;
    while (existingNames.contains(candidate)) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    if (persist) {
      _serverNamesBySessionId[sessionId] = candidate;
    }
    return candidate;
  }

  void _syncServerSignature(String sessionId, McpServer server) {
    final signature = server.summary;
    final previousSignature = _serverSignaturesBySessionId[sessionId];
    if (previousSignature != null && previousSignature != signature) {
      _catalogCache.removeWhere((key, _) => key.startsWith('$sessionId|'));
      unawaited(McpStdioProcessManager.instance.stopServer(server.name));
    }
    _serverSignaturesBySessionId[sessionId] = signature;
  }

  String _catalogCacheKey(String sessionId, McpServer server) =>
      '$sessionId|${server.name}|${server.summary}';

  Future<McpToolCatalog> _discoverCatalog({
    required McpServer server,
    required String cacheKey,
  }) {
    final now = DateTime.now().toUtc();
    _pruneCatalogCache(now);
    final cached = _catalogCache[cacheKey];
    if (cached != null && now.difference(cached.createdAt) < catalogCacheTtl) {
      return cached.future;
    }

    final entry = _WebReverseCdpMcpCatalogCacheEntry(createdAt: now);
    entry.future = _discoveryService
        .discoverTools(server)
        .timeout(
          catalogTimeout,
          onTimeout: () => McpToolCatalog(
            status: McpToolCatalogStatus.failed,
            errorMessage:
                'OpenHand auto CDP MCP discovery timed out after '
                '${catalogTimeout.inSeconds}s. Install or refresh '
                'chrome-devtools-mcp, then retry the Web Reverse turn.',
            lastScannedAt: DateTime.now().toUtc(),
          ),
        )
        .then(
          (catalog) {
            entry.catalog = catalog;
            return catalog;
          },
          onError: (Object error, StackTrace stack) {
            silentLog(
              'web_reverse_cdp_mcp_bridge',
              'discover transient cdp mcp ${server.name}',
              error,
              stack,
            );
            final failed = McpToolCatalog(
              status: McpToolCatalogStatus.failed,
              errorMessage: 'OpenHand auto CDP MCP discovery failed: $error',
              lastScannedAt: DateTime.now().toUtc(),
            );
            entry.catalog = failed;
            return failed;
          },
        );
    _catalogCache[cacheKey] = entry;
    return entry.future;
  }

  void _pruneCatalogCache(DateTime now) {
    _catalogCache.removeWhere(
      (_, entry) => now.difference(entry.createdAt) >= catalogCacheTtl,
    );
  }
}

class _WebReverseCdpMcpCatalogCacheEntry {
  _WebReverseCdpMcpCatalogCacheEntry({required this.createdAt});

  final DateTime createdAt;
  late final Future<McpToolCatalog> future;
  McpToolCatalog? catalog;
}
