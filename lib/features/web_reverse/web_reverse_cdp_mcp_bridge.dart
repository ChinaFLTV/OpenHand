import 'dart:async';

import '../../app/support/silent_log.dart';
import '../mcp/index.dart';
import 'web_reverse_session_controller.dart';

class WebReverseTransientMcpSnapshot {
  const WebReverseTransientMcpSnapshot({
    required this.servers,
    required this.catalogsByServerName,
    required this.diagnostic,
  });

  static const empty = WebReverseTransientMcpSnapshot(
    servers: <McpServer>[],
    catalogsByServerName: <String, McpToolCatalog>{},
    diagnostic: WebReverseCdpMcpBridgeDiagnostic.unavailable(),
  );

  final List<McpServer> servers;
  final Map<String, McpToolCatalog> catalogsByServerName;
  final WebReverseCdpMcpBridgeDiagnostic diagnostic;
}

enum WebReverseCdpMcpBridgeStatus { unavailable, preparing, ready, failed }

class WebReverseCdpMcpBridgeDiagnostic {
  const WebReverseCdpMcpBridgeDiagnostic({
    required this.status,
    required this.browserAlive,
    required this.toolCount,
    required this.message,
    this.serverName,
    this.cdpPort,
    this.browserUrl,
    this.errorMessage,
    this.warningMessage,
    this.lastScannedAt,
  });

  const WebReverseCdpMcpBridgeDiagnostic.unavailable()
    : status = WebReverseCdpMcpBridgeStatus.unavailable,
      browserAlive = false,
      toolCount = 0,
      message = 'Transient CDP MCP is unavailable for this session.',
      serverName = null,
      cdpPort = null,
      browserUrl = null,
      errorMessage = null,
      warningMessage = null,
      lastScannedAt = null;

  final WebReverseCdpMcpBridgeStatus status;
  final bool browserAlive;
  final int toolCount;
  final String message;
  final String? serverName;
  final int? cdpPort;
  final String? browserUrl;
  final String? errorMessage;
  final String? warningMessage;
  final DateTime? lastScannedAt;

  bool get liveActionsCallable =>
      status == WebReverseCdpMcpBridgeStatus.ready &&
      browserAlive &&
      toolCount > 0;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'browser_alive': browserAlive,
      'live_actions_callable': liveActionsCallable,
      'tool_count': toolCount,
      'message': message,
      if (serverName != null && serverName!.isNotEmpty)
        'server_name': serverName,
      if (cdpPort != null) 'cdp_port': cdpPort,
      if (browserUrl != null && browserUrl!.isNotEmpty)
        'browser_url': browserUrl,
      if (errorMessage != null && errorMessage!.isNotEmpty)
        'error_message': errorMessage,
      if (warningMessage != null && warningMessage!.isNotEmpty)
        'warning_message': warningMessage,
      if (lastScannedAt != null)
        'last_scanned_at': lastScannedAt!.toUtc().toIso8601String(),
    };
  }
}

class WebReverseCdpMcpBridge {
  WebReverseCdpMcpBridge({
    McpToolDiscoveryService? discoveryService,
    this.catalogTimeout = defaultCatalogTimeout,
    this.catalogCacheTtl = defaultCatalogCacheTtl,
    this.failedCatalogRetryTtl = defaultFailedCatalogRetryTtl,
  }) : _discoveryService = discoveryService ?? DefaultMcpToolDiscoveryService();

  static const String templateId = 'web_reverse_expert';
  static const String cdpMcpPackage = 'chrome-devtools-mcp@latest';
  // 底层 stdio MCP discovery 已给 npx 首次冷启动 6 分钟预算；外层略大，
  // 避免提前把 chrome-devtools-mcp 首次安装误判成失败。
  static const Duration defaultCatalogTimeout = Duration(minutes: 7);
  static const Duration defaultCatalogCacheTtl = Duration(minutes: 5);
  static const Duration defaultFailedCatalogRetryTtl = Duration(seconds: 30);

  final McpToolDiscoveryService _discoveryService;
  final Duration catalogTimeout;
  final Duration catalogCacheTtl;
  final Duration failedCatalogRetryTtl;
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
      return WebReverseTransientMcpSnapshot(
        servers: const <McpServer>[],
        catalogsByServerName: const <String, McpToolCatalog>{},
        diagnostic: _diagnosticForUnavailable(
          sessionId: sessionId,
          sessionTemplateId: sessionTemplateId,
          controller: controller,
        ),
      );
    }
    final cacheKey = _catalogCacheKey(sessionId, server);
    final catalog = await _discoverCatalog(server: server, cacheKey: cacheKey);
    return WebReverseTransientMcpSnapshot(
      servers: <McpServer>[server],
      catalogsByServerName: <String, McpToolCatalog>{server.name: catalog},
      diagnostic: _diagnosticFromCatalog(
        server: server,
        controller: controller!,
        catalog: catalog,
      ),
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
      return WebReverseTransientMcpSnapshot(
        servers: const <McpServer>[],
        catalogsByServerName: const <String, McpToolCatalog>{},
        diagnostic: _diagnosticForUnavailable(
          sessionId: sessionId,
          sessionTemplateId: sessionTemplateId,
          controller: controller,
        ),
      );
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
      diagnostic: _diagnosticFromCatalog(
        server: server,
        controller: controller!,
        catalog: catalog,
      ),
    );
  }

  WebReverseCdpMcpBridgeDiagnostic cachedDiagnostic({
    required String? sessionId,
    required String? sessionTemplateId,
    required WebReverseSessionController? controller,
    required Iterable<McpServer> existingServers,
  }) {
    return cachedSnapshot(
      sessionId: sessionId,
      sessionTemplateId: sessionTemplateId,
      controller: controller,
      existingServers: existingServers,
    ).diagnostic;
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
    if (cached != null) {
      final cachedCatalog = cached.catalog;
      if (cachedCatalog == null) {
        return cached.future;
      }
      final age = now.difference(cached.createdAt);
      if (age >= catalogCacheTtl) {
        _catalogCache.remove(cacheKey);
      } else {
        if (cachedCatalog.status == McpToolCatalogStatus.failed &&
            age >= failedCatalogRetryTtl) {
          _catalogCache.remove(cacheKey);
        } else {
          return cached.future;
        }
      }
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
      (_, entry) =>
          entry.catalog != null &&
          now.difference(entry.createdAt) >= catalogCacheTtl,
    );
  }

  WebReverseCdpMcpBridgeDiagnostic _diagnosticForUnavailable({
    required String? sessionId,
    required String? sessionTemplateId,
    required WebReverseSessionController? controller,
  }) {
    if (sessionId == null || sessionId.isEmpty) {
      return const WebReverseCdpMcpBridgeDiagnostic(
        status: WebReverseCdpMcpBridgeStatus.unavailable,
        browserAlive: false,
        toolCount: 0,
        message: 'No active session is available for transient CDP MCP.',
      );
    }
    if (sessionTemplateId != templateId) {
      return const WebReverseCdpMcpBridgeDiagnostic(
        status: WebReverseCdpMcpBridgeStatus.unavailable,
        browserAlive: false,
        toolCount: 0,
        message: 'Current session is not a Web Reverse Expert session.',
      );
    }
    if (controller == null) {
      return const WebReverseCdpMcpBridgeDiagnostic(
        status: WebReverseCdpMcpBridgeStatus.unavailable,
        browserAlive: false,
        toolCount: 0,
        message: 'No Web Reverse CDP controller is attached.',
      );
    }
    final port = controller.cdpPort;
    if (!controller.isBrowserAlive) {
      return WebReverseCdpMcpBridgeDiagnostic(
        status: WebReverseCdpMcpBridgeStatus.unavailable,
        browserAlive: false,
        toolCount: 0,
        cdpPort: port,
        browserUrl: port == null ? null : 'http://127.0.0.1:$port',
        message:
            'The Web Reverse browser is not alive; live CDP MCP actions are unavailable.',
      );
    }
    return WebReverseCdpMcpBridgeDiagnostic(
      status: WebReverseCdpMcpBridgeStatus.unavailable,
      browserAlive: true,
      toolCount: 0,
      cdpPort: port,
      browserUrl: port == null ? null : 'http://127.0.0.1:$port',
      message: 'The live Web Reverse CDP port is not available yet.',
    );
  }

  WebReverseCdpMcpBridgeDiagnostic _diagnosticFromCatalog({
    required McpServer server,
    required WebReverseSessionController controller,
    required McpToolCatalog catalog,
  }) {
    final port = controller.cdpPort;
    final browserUrl = port == null ? null : 'http://127.0.0.1:$port';
    final status = switch (catalog.status) {
      McpToolCatalogStatus.ready =>
        catalog.tools.isEmpty
            ? WebReverseCdpMcpBridgeStatus.failed
            : WebReverseCdpMcpBridgeStatus.ready,
      McpToolCatalogStatus.failed => WebReverseCdpMcpBridgeStatus.failed,
      McpToolCatalogStatus.loading ||
      McpToolCatalogStatus.idle => WebReverseCdpMcpBridgeStatus.preparing,
    };
    final message = switch (status) {
      WebReverseCdpMcpBridgeStatus.ready =>
        'Transient chrome-devtools-mcp is ready for live CDP actions.',
      WebReverseCdpMcpBridgeStatus.failed =>
        catalog.tools.isEmpty && catalog.status == McpToolCatalogStatus.ready
            ? 'Transient chrome-devtools-mcp returned no tools.'
            : 'Transient chrome-devtools-mcp discovery failed.',
      WebReverseCdpMcpBridgeStatus.preparing =>
        'Transient chrome-devtools-mcp catalog is being prepared.',
      WebReverseCdpMcpBridgeStatus.unavailable =>
        'Transient chrome-devtools-mcp is unavailable.',
    };
    return WebReverseCdpMcpBridgeDiagnostic(
      status: status,
      browserAlive: controller.isBrowserAlive,
      toolCount: catalog.tools.length,
      serverName: server.name,
      cdpPort: port,
      browserUrl: browserUrl,
      message: message,
      errorMessage: catalog.errorMessage?.trim(),
      warningMessage: catalog.warningMessage?.trim(),
      lastScannedAt: catalog.lastScannedAt,
    );
  }
}

class _WebReverseCdpMcpCatalogCacheEntry {
  _WebReverseCdpMcpCatalogCacheEntry({required this.createdAt});

  final DateTime createdAt;
  late final Future<McpToolCatalog> future;
  McpToolCatalog? catalog;
}
