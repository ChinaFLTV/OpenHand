import 'dart:async';

import '../../app/support/silent_log.dart';
import '../../shared/net/tcp_port_utils.dart';
import '../mcp/index.dart';
import 'web_reverse_cdp_http.dart';
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
    diagnostic: WebReverseCdpMcpBridgeDiagnostic.disabled(),
  );

  final List<McpServer> servers;
  final Map<String, McpToolCatalog> catalogsByServerName;
  final WebReverseCdpMcpBridgeDiagnostic diagnostic;
}

enum WebReverseCdpMcpBridgeStatus {
  disabled,
  unavailable,
  preparing,
  ready,
  failed,
}

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

  const WebReverseCdpMcpBridgeDiagnostic.disabled()
    : status = WebReverseCdpMcpBridgeStatus.disabled,
      browserAlive = false,
      toolCount = 0,
      message = '当前 Web 逆向会话未启用 AI 侧 CDP MCP，可在设置对话框或调试器中启用。',
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
  }) : _discoveryService = discoveryService ?? DefaultMcpToolDiscoveryService(),
       _ownsDiscoveryService = discoveryService == null;

  static const String templateId = 'web_reverse_expert';
  static const String cdpMcpPackage = 'chrome-devtools-mcp@latest';
  // 底层 stdio MCP discovery 已给 npx 首次冷启动 6 分钟预算；外层略大，
  // 避免提前把 chrome-devtools-mcp 首次安装误判成失败。
  static const Duration defaultCatalogTimeout = Duration(minutes: 7);
  static const Duration defaultCatalogCacheTtl = Duration(minutes: 5);
  static const Duration defaultFailedCatalogRetryTtl = Duration(seconds: 30);
  static const int _maxCatalogCacheEntries = 32;
  static const int _maxConcurrentCatalogDiscoveries = 4;
  static const String _preparingCatalogWarning =
      'OpenHand 正在为当前 Web 逆向会话准备临时 CDP MCP 工具目录。';

  final McpToolDiscoveryService _discoveryService;
  final bool _ownsDiscoveryService;
  final Duration catalogTimeout;
  final Duration catalogCacheTtl;
  final Duration failedCatalogRetryTtl;
  final Map<String, String> _serverNamesBySessionId = <String, String>{};
  final Map<String, String> _serverSignaturesBySessionId = <String, String>{};
  final Map<String, _WebReverseCdpMcpCatalogCacheEntry> _catalogCache =
      <String, _WebReverseCdpMcpCatalogCacheEntry>{};
  final Map<String, Future<void>> _serverStopsByName = <String, Future<void>>{};

  Future<WebReverseTransientMcpSnapshot> buildSnapshot({
    required bool enabled,
    required String? sessionId,
    required String? sessionTemplateId,
    required WebReverseSessionController? controller,
    required Iterable<McpServer> existingServers,
  }) async {
    if (!enabled) {
      if (sessionId != null && sessionId.isNotEmpty) {
        stopSession(sessionId);
      }
      return WebReverseTransientMcpSnapshot.empty;
    }
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
    await _syncServerSignature(sessionId, server);
    final cacheKey = _catalogCacheKey(sessionId, server);
    final catalog = await _discoverCatalog(server: server, cacheKey: cacheKey);
    return _snapshotWithCatalog(server, controller!, catalog);
  }

  WebReverseTransientMcpSnapshot cachedSnapshot({
    required bool enabled,
    required String? sessionId,
    required String? sessionTemplateId,
    required WebReverseSessionController? controller,
    required Iterable<McpServer> existingServers,
  }) {
    if (!enabled) {
      return WebReverseTransientMcpSnapshot.empty;
    }
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
        const McpToolCatalog(
          status: McpToolCatalogStatus.loading,
          warningMessage: _preparingCatalogWarning,
        );
    return _snapshotWithCatalog(server, controller!, catalog);
  }

  WebReverseTransientMcpSnapshot _snapshotWithCatalog(
    McpServer server,
    WebReverseSessionController controller,
    McpToolCatalog catalog,
  ) {
    return WebReverseTransientMcpSnapshot(
      servers: <McpServer>[server],
      catalogsByServerName: <String, McpToolCatalog>{server.name: catalog},
      diagnostic: _diagnosticFromCatalog(
        server: server,
        controller: controller,
        catalog: catalog,
      ),
    );
  }

  WebReverseCdpMcpBridgeDiagnostic cachedDiagnostic({
    required bool enabled,
    required String? sessionId,
    required String? sessionTemplateId,
    required WebReverseSessionController? controller,
    required Iterable<McpServer> existingServers,
  }) {
    return cachedSnapshot(
      enabled: enabled,
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
      unawaited(_stopServer(serverName, '停止 Web 逆向 CDP MCP 服务'));
    }
  }

  void dispose() {
    for (final sessionId in _serverNamesBySessionId.keys.toList()) {
      stopSession(sessionId);
    }
    _catalogCache.clear();
    if (_ownsDiscoveryService) {
      _discoveryService.dispose();
    }
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
    final port = validTcpPort(controller.cdpPort);
    if (port == null) {
      if (syncLifecycle) {
        stopSession(sessionId);
      }
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
        '--browser-url=${webReverseCdpHttpOrigin(port)}',
      ],
      visibleTemplateIds: const <String>{templateId},
    );
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

  Future<void> _syncServerSignature(String sessionId, McpServer server) async {
    final activeStop = _serverStopsByName[server.name];
    if (activeStop != null) await activeStop;
    final signature = server.summary;
    final previousSignature = _serverSignaturesBySessionId[sessionId];
    _serverSignaturesBySessionId[sessionId] = signature;
    if (previousSignature != null && previousSignature != signature) {
      _catalogCache.removeWhere((key, _) => key.startsWith('$sessionId|'));
      await _stopServer(server.name, '重启配置已变更的 Web 逆向 CDP MCP 服务');
    }
  }

  Future<void> _stopServer(String serverName, String action) {
    final active = _serverStopsByName[serverName];
    if (active != null) return active;
    late final Future<void> tracked;
    tracked = McpStdioProcessManager.instance
        .stopServer(serverName)
        .catchError((Object error, StackTrace stack) {
          silentLog('web_reverse_cdp_mcp_bridge', action, error, stack);
        })
        .whenComplete(() {
          if (identical(_serverStopsByName[serverName], tracked)) {
            _serverStopsByName.remove(serverName);
          }
        });
    _serverStopsByName[serverName] = tracked;
    return tracked;
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

    final pendingCount = _catalogCache.values
        .where((entry) => entry.catalog == null)
        .length;
    if (pendingCount >= _maxConcurrentCatalogDiscoveries ||
        _catalogCache.length >= _maxCatalogCacheEntries) {
      return Future<McpToolCatalog>.value(
        McpToolCatalog(
          status: McpToolCatalogStatus.failed,
          errorMessage: pendingCount >= _maxConcurrentCatalogDiscoveries
              ? 'CDP MCP 工具发现任务已达到并发上限 $_maxConcurrentCatalogDiscoveries。'
              : 'CDP MCP 工具目录缓存已达到容量上限 $_maxCatalogCacheEntries。',
          lastScannedAt: now,
        ),
      );
    }

    final entry = _WebReverseCdpMcpCatalogCacheEntry(createdAt: now);
    entry.future = _discoveryService
        .discoverTools(server)
        .timeout(
          catalogTimeout,
          onTimeout: () => McpToolCatalog(
            status: McpToolCatalogStatus.failed,
            errorMessage:
                'OpenHand CDP MCP 工具发现超过 ${catalogTimeout.inSeconds} 秒。'
                '请检查 MCP stdio 缓存及网络或 npm 访问后重试。',
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
              '发现临时 CDP MCP 服务：${server.name}',
              error,
              stack,
            );
            final failed = McpToolCatalog(
              status: McpToolCatalogStatus.failed,
              errorMessage: 'OpenHand CDP MCP 工具发现失败：$error',
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
    while (_catalogCache.length >= _maxCatalogCacheEntries) {
      String? oldestKey;
      DateTime? oldestCreatedAt;
      for (final item in _catalogCache.entries) {
        if (item.value.catalog == null) continue;
        if (oldestCreatedAt == null ||
            item.value.createdAt.isBefore(oldestCreatedAt)) {
          oldestKey = item.key;
          oldestCreatedAt = item.value.createdAt;
        }
      }
      if (oldestKey == null) break;
      _catalogCache.remove(oldestKey);
    }
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
        message: '当前没有可用于临时 CDP MCP 的活动会话。',
      );
    }
    if (sessionTemplateId != templateId) {
      return const WebReverseCdpMcpBridgeDiagnostic(
        status: WebReverseCdpMcpBridgeStatus.unavailable,
        browserAlive: false,
        toolCount: 0,
        message: '当前会话不是 Web 逆向专家会话。',
      );
    }
    if (controller == null) {
      return const WebReverseCdpMcpBridgeDiagnostic(
        status: WebReverseCdpMcpBridgeStatus.unavailable,
        browserAlive: false,
        toolCount: 0,
        message: '当前未关联 Web 逆向 CDP 控制器。',
      );
    }
    final port = controller.cdpPort;
    if (!controller.isBrowserAlive) {
      return WebReverseCdpMcpBridgeDiagnostic(
        status: WebReverseCdpMcpBridgeStatus.unavailable,
        browserAlive: false,
        toolCount: 0,
        cdpPort: port,
        browserUrl: port == null ? null : webReverseCdpHttpOrigin(port),
        message: 'Web 逆向浏览器未运行，实时 CDP MCP 操作不可用。',
      );
    }
    return WebReverseCdpMcpBridgeDiagnostic(
      status: WebReverseCdpMcpBridgeStatus.unavailable,
      browserAlive: true,
      toolCount: 0,
      cdpPort: port,
      browserUrl: port == null ? null : webReverseCdpHttpOrigin(port),
      message: 'Web 逆向实时 CDP 端口尚不可用。',
    );
  }

  WebReverseCdpMcpBridgeDiagnostic _diagnosticFromCatalog({
    required McpServer server,
    required WebReverseSessionController controller,
    required McpToolCatalog catalog,
  }) {
    final port = controller.cdpPort;
    final browserUrl = port == null ? null : webReverseCdpHttpOrigin(port);
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
        '临时 chrome-devtools-mcp 已可执行实时 CDP 操作。',
      WebReverseCdpMcpBridgeStatus.failed =>
        catalog.tools.isEmpty && catalog.status == McpToolCatalogStatus.ready
            ? '临时 chrome-devtools-mcp 未返回工具。'
            : '临时 chrome-devtools-mcp 工具发现失败。',
      WebReverseCdpMcpBridgeStatus.preparing =>
        '正在通过 npx 准备临时 chrome-devtools-mcp 工具目录。',
      WebReverseCdpMcpBridgeStatus.disabled => '当前 Web 逆向会话未启用 AI 侧 CDP MCP。',
      WebReverseCdpMcpBridgeStatus.unavailable => '临时 chrome-devtools-mcp 不可用。',
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
