import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data/mcp_store.dart';
import 'model/mcp_server.dart';
import 'model/mcp_server_health.dart';
import 'model/mcp_tool.dart';
import 'service/mcp_tool_discovery_service.dart';

class McpController extends ChangeNotifier {
  McpController._({
    required McpStore store,
    required McpToolDiscoveryService toolDiscoveryService,
    required Duration healthCheckInterval,
  }) : _store = store,
       _toolDiscoveryService = toolDiscoveryService,
       _healthCheckInterval = healthCheckInterval;

  static Future<McpController> create({
    required String initialFilePath,
    McpStore? store,
    McpToolDiscoveryService? toolDiscoveryService,
    Duration healthCheckInterval = const Duration(seconds: 30),
  }) async {
    final controller = McpController._(
      store: store ?? McpStore(serversFilePath: initialFilePath),
      toolDiscoveryService:
          toolDiscoveryService ?? DefaultMcpToolDiscoveryService(),
      healthCheckInterval: healthCheckInterval,
    );
    await controller.refresh();
    return controller;
  }

  final McpStore _store;
  final McpToolDiscoveryService _toolDiscoveryService;
  final Duration _healthCheckInterval;

  bool _isLoading = false;
  String? _errorMessage;
  List<McpServer> _servers = const <McpServer>[];
  final Map<String, McpToolCatalog> _toolCatalogByServerName =
      <String, McpToolCatalog>{};
  final Map<String, int> _toolRefreshGenerationByServerName = <String, int>{};
  final Map<String, McpServerHealth> _healthByServerName =
      <String, McpServerHealth>{};
  final Map<String, int> _healthCheckGenerationByServerName = <String, int>{};
  McpPersistenceIssue? _persistenceIssue;
  bool _isDisposed = false;
  bool _isPageActive = false;
  Future<void> _operationQueue = Future<void>.value();
  Timer? _healthCheckTimer;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<McpServer> get servers => List<McpServer>.unmodifiable(_servers);
  String get serversFilePath => _store.serversFilePath;
  String get storageDirectoryPath => _store.storageDirectoryPath;
  McpPersistenceIssue? get persistenceIssue => _persistenceIssue;
  McpToolCatalog toolCatalogFor(String serverName) {
    return _toolCatalogByServerName[_normalizeServerName(serverName)] ??
        const McpToolCatalog();
  }

  McpServerHealth healthStatusFor(String serverName) {
    return _healthByServerName[_normalizeServerName(serverName)] ??
        const McpServerHealth();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) {
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _healthCheckTimer?.cancel();
    _toolDiscoveryService.dispose();
    super.dispose();
  }

  void clearPersistenceIssue() {
    if (_persistenceIssue == null) {
      return;
    }
    _persistenceIssue = null;
    notifyListeners();
  }

  void setPageActive(bool isActive) {
    if (_isDisposed || _isPageActive == isActive) {
      return;
    }
    _isPageActive = isActive;
    if (_isPageActive) {
      _autoRefreshEnabledServerTools();
      _forceCheckEnabledServerHealth();
    } else {
      _invalidateToolRefreshGenerations();
      _invalidateHealthCheckGenerations();
    }
    _reconcileHealthCheckTimer();
  }

  Future<void> refresh() async {
    await _enqueueOperation(() async {
      _isLoading = true;
      _errorMessage = null;
      _persistenceIssue = null;
      notifyListeners();

      try {
        final loadResult = await _store.load();
        _servers = loadResult.servers;
        _syncToolCatalogsWithServers(_servers);
        _syncHealthStatusesWithServers(_servers);
        _persistenceIssue = loadResult.issue;
      } catch (error) {
        _servers = const <McpServer>[];
        _toolCatalogByServerName.clear();
        _toolRefreshGenerationByServerName.clear();
        _healthByServerName.clear();
        _healthCheckGenerationByServerName.clear();
        _errorMessage = '$error';
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    });
    if (_isPageActive) {
      _autoRefreshEnabledServerTools(force: true);
      _autoCheckEnabledServerHealth(force: true);
    }
    _reconcileHealthCheckTimer();
  }

  Future<bool> saveServer(McpServer server, {String? previousName}) async {
    final normalizedName = server.name.trim();
    if (normalizedName.isEmpty) {
      return false;
    }
    return _enqueueOperation(() async {
      final updatedServers = List<McpServer>.from(_servers);
      final normalizedPreviousName = previousName?.trim();
      if (normalizedPreviousName != null && normalizedPreviousName.isNotEmpty) {
        updatedServers.removeWhere(
          (item) => item.name == normalizedPreviousName,
        );
      }
      final duplicateExists = updatedServers.any(
        (item) => item.name == normalizedName,
      );
      if (duplicateExists) {
        return false;
      }
      updatedServers.add(server.copyWith(name: normalizedName));
      updatedServers.sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
      return _commitSaveLocked(
        updatedServers,
        previousServerName: normalizedPreviousName,
        changedServerName: normalizedName,
        shouldAutoRefreshTools: server.enabled,
        shouldAutoCheckHealth: server.enabled,
        resetChangedServerToolCatalog: true,
        resetChangedServerHealth: true,
      );
    });
  }

  Future<bool> deleteServer(McpServer server) async {
    return _enqueueOperation(() async {
      final updatedServers = _servers
          .where((item) => item.name != server.name)
          .toList(growable: false);
      if (updatedServers.length == _servers.length) {
        return true;
      }
      return _commitSaveLocked(
        updatedServers,
        previousServerName: server.name,
      );
    });
  }

  Future<bool> updateServerEnabled(String name, bool enabled) async {
    return _enqueueOperation(() async {
      final normalizedName = _normalizeServerName(name);
      final index = _servers.indexWhere((item) => item.name == normalizedName);
      if (index == -1) {
        return false;
      }
      if (_servers[index].enabled == enabled) {
        return true;
      }

      final updatedServers = List<McpServer>.from(_servers);
      updatedServers[index] = updatedServers[index].copyWith(enabled: enabled);
      return _commitSaveLocked(
        updatedServers,
        changedServerName: updatedServers[index].name,
        shouldAutoRefreshTools: enabled,
        shouldAutoCheckHealth: enabled,
        resetChangedServerToolCatalog: !enabled,
        resetChangedServerHealth: !enabled,
      );
    });
  }

  Future<void> openStorageDirectory() {
    return _store.openStorageDirectory();
  }

  Future<void> refreshServerTools(String serverName) async {
    final normalizedServerName = _normalizeServerName(serverName);
    if (normalizedServerName.isEmpty) {
      return;
    }
    final server = _serverByName(normalizedServerName);
    if (server == null) {
      return;
    }
    final nextGeneration =
        (_toolRefreshGenerationByServerName[normalizedServerName] ?? 0) + 1;
    _toolRefreshGenerationByServerName[normalizedServerName] = nextGeneration;
    final previousCatalog = toolCatalogFor(normalizedServerName);
    _toolCatalogByServerName[normalizedServerName] = previousCatalog.copyWith(
      status: McpToolCatalogStatus.loading,
      clearErrorMessage: true,
    );
    notifyListeners();

    try {
      final discoveredCatalog = await _toolDiscoveryService.discoverTools(
        server,
      );
      if (_isDisposed ||
          _toolRefreshGenerationByServerName[normalizedServerName] !=
              nextGeneration) {
        return;
      }
      _toolCatalogByServerName[normalizedServerName] = _resolvedRefreshCatalog(
        previousCatalog: previousCatalog,
        discoveredCatalog: discoveredCatalog,
      );
      notifyListeners();
    } catch (error) {
      if (_isDisposed ||
          _toolRefreshGenerationByServerName[normalizedServerName] !=
              nextGeneration) {
        return;
      }
      _toolCatalogByServerName[normalizedServerName] = _resolvedRefreshCatalog(
        previousCatalog: previousCatalog,
        discoveredCatalog: McpToolCatalog(
          status: McpToolCatalogStatus.failed,
          errorMessage: '$error',
          lastScannedAt: DateTime.now().toUtc(),
        ),
      );
      notifyListeners();
    }
  }

  Future<void> checkServerHealth(String serverName) async {
    if (_isDisposed || !_isPageActive) {
      return;
    }
    final normalizedServerName = _normalizeServerName(serverName);
    if (normalizedServerName.isEmpty) {
      return;
    }
    final server = _serverByName(normalizedServerName);
    if (server == null) {
      return;
    }
    final nextGeneration =
        (_healthCheckGenerationByServerName[normalizedServerName] ?? 0) + 1;
    _healthCheckGenerationByServerName[normalizedServerName] = nextGeneration;
    final previousHealth = healthStatusFor(normalizedServerName);
    _healthByServerName[normalizedServerName] = previousHealth.copyWith(
      status: McpServerHealthStatus.checking,
      clearErrorMessage: true,
    );
    notifyListeners();

    try {
      final resolvedHealth = await _toolDiscoveryService.checkHealth(server);
      if (_isDisposed ||
          !_isPageActive ||
          _healthCheckGenerationByServerName[normalizedServerName] !=
              nextGeneration) {
        return;
      }
      _healthByServerName[normalizedServerName] = resolvedHealth;
      notifyListeners();
    } catch (error) {
      if (_isDisposed ||
          !_isPageActive ||
          _healthCheckGenerationByServerName[normalizedServerName] !=
              nextGeneration) {
        return;
      }
      _healthByServerName[normalizedServerName] = McpServerHealth(
        status: McpServerHealthStatus.unhealthy,
        errorMessage: '$error',
        lastCheckedAt: DateTime.now().toUtc(),
      );
      notifyListeners();
    }
  }

  Future<McpToolCallResult> callTool({
    required String serverName,
    required String toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) async {
    if (_isDisposed) {
      throw StateError('MCP controller has been disposed.');
    }
    final normalizedServerName = serverName.trim();
    final normalizedToolName = toolName.trim();
    if (normalizedServerName.isEmpty) {
      throw StateError('Missing MCP server name.');
    }
    if (normalizedToolName.isEmpty) {
      throw StateError('Missing MCP tool name.');
    }
    final server = _serverByName(normalizedServerName);
    if (server == null) {
      throw StateError('Missing MCP server: $normalizedServerName');
    }
    if (!server.enabled) {
      throw StateError('MCP server is disabled: $normalizedServerName');
    }
    return _toolDiscoveryService.callTool(
      server: server,
      toolName: normalizedToolName,
      arguments: arguments,
    );
  }

  Future<bool> _commitSaveLocked(
    List<McpServer> nextServers, {
    String? previousServerName,
    String? changedServerName,
    bool shouldAutoRefreshTools = false,
    bool shouldAutoCheckHealth = false,
    bool resetChangedServerToolCatalog = false,
    bool resetChangedServerHealth = false,
  }) async {
    final previousServers = List<McpServer>.from(_servers);
    final previousToolCatalogByServerName = Map<String, McpToolCatalog>.from(
      _toolCatalogByServerName,
    );
    final previousToolRefreshGenerationByServerName = Map<String, int>.from(
      _toolRefreshGenerationByServerName,
    );
    final previousHealthByServerName = Map<String, McpServerHealth>.from(
      _healthByServerName,
    );
    final previousHealthCheckGenerationByServerName = Map<String, int>.from(
      _healthCheckGenerationByServerName,
    );
    _servers = nextServers;
    _syncToolCatalogsWithServers(nextServers);
    _syncHealthStatusesWithServers(nextServers);
    if (previousServerName != null && previousServerName != changedServerName) {
      _toolCatalogByServerName.remove(previousServerName);
      _toolRefreshGenerationByServerName.remove(previousServerName);
      _healthByServerName.remove(previousServerName);
      _healthCheckGenerationByServerName.remove(previousServerName);
    }
    if (resetChangedServerToolCatalog && changedServerName != null) {
      _toolCatalogByServerName[changedServerName] = const McpToolCatalog();
      _invalidateToolRefreshGeneration(changedServerName);
    }
    if (resetChangedServerHealth && changedServerName != null) {
      _healthByServerName[changedServerName] = const McpServerHealth();
      _invalidateHealthCheckGeneration(changedServerName);
    }
    _errorMessage = null;
    notifyListeners();
    try {
      await _store.save(nextServers);
      if (_persistenceIssue != null) {
        _persistenceIssue = null;
        notifyListeners();
      }
      _reconcileHealthCheckTimer();
      if (_isPageActive &&
          shouldAutoRefreshTools &&
          changedServerName != null) {
        unawaited(refreshServerTools(changedServerName));
      }
      if (_isPageActive && shouldAutoCheckHealth && changedServerName != null) {
        unawaited(checkServerHealth(changedServerName));
      }
      return true;
    } catch (error) {
      _servers = previousServers;
      _toolCatalogByServerName
        ..clear()
        ..addAll(previousToolCatalogByServerName);
      _toolRefreshGenerationByServerName
        ..clear()
        ..addAll(previousToolRefreshGenerationByServerName);
      _healthByServerName
        ..clear()
        ..addAll(previousHealthByServerName);
      _healthCheckGenerationByServerName
        ..clear()
        ..addAll(previousHealthCheckGenerationByServerName);
      _persistenceIssue = McpPersistenceIssue(
        kind: McpPersistenceIssueKind.saveFailed,
        filePath: _store.serversFilePath,
        detail: '$error',
      );
      notifyListeners();
      return false;
    }
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _syncToolCatalogsWithServers(List<McpServer> servers) {
    final serverNames = servers.map((item) => item.name).toSet();
    _toolCatalogByServerName.removeWhere(
      (serverName, value) => !serverNames.contains(serverName),
    );
    _toolRefreshGenerationByServerName.removeWhere(
      (serverName, value) => !serverNames.contains(serverName),
    );
    for (final server in servers) {
      _toolCatalogByServerName.putIfAbsent(server.name, McpToolCatalog.new);
    }
  }

  void _syncHealthStatusesWithServers(List<McpServer> servers) {
    final serverNames = servers.map((item) => item.name).toSet();
    _healthByServerName.removeWhere(
      (serverName, value) => !serverNames.contains(serverName),
    );
    _healthCheckGenerationByServerName.removeWhere(
      (serverName, value) => !serverNames.contains(serverName),
    );
    for (final server in servers) {
      _healthByServerName.putIfAbsent(server.name, McpServerHealth.new);
    }
  }

  void _autoRefreshEnabledServerTools({bool force = false}) {
    for (final server in _servers) {
      if (!server.enabled) {
        continue;
      }
      final catalog = toolCatalogFor(server.name);
      if (!force &&
          (catalog.isLoading ||
              catalog.status == McpToolCatalogStatus.ready &&
                  catalog.lastScannedAt != null)) {
        continue;
      }
      unawaited(refreshServerTools(server.name));
    }
  }

  void _autoCheckEnabledServerHealth({bool force = false}) {
    final now = DateTime.now().toUtc();
    for (final server in _servers) {
      if (!server.enabled) {
        continue;
      }
      final healthStatus = healthStatusFor(server.name);
      if (healthStatus.isChecking) {
        continue;
      }
      if (!force && healthStatus.lastCheckedAt != null) {
        final age = now.difference(healthStatus.lastCheckedAt!);
        if (age < _healthCheckInterval) {
          continue;
        }
      }
      unawaited(checkServerHealth(server.name));
    }
  }

  void _forceCheckEnabledServerHealth() {
    for (final server in _servers) {
      if (!server.enabled) {
        continue;
      }
      unawaited(checkServerHealth(server.name));
    }
  }

  void _invalidateHealthCheckGenerations() {
    for (final serverName in _healthByServerName.keys) {
      _invalidateHealthCheckGeneration(serverName);
    }
  }

  void _invalidateToolRefreshGenerations() {
    for (final entry in _toolCatalogByServerName.entries) {
      final serverName = entry.key;
      _invalidateToolRefreshGeneration(serverName);
      final catalog = entry.value;
      if (!catalog.isLoading) {
        continue;
      }
      _toolCatalogByServerName[serverName] = catalog.copyWith(
        status: McpToolCatalogStatus.idle,
        clearErrorMessage: true,
      );
    }
  }

  void _reconcileHealthCheckTimer() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    if (_isDisposed ||
        !_isPageActive ||
        !_servers.any((server) => server.enabled)) {
      return;
    }
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) {
      _autoCheckEnabledServerHealth();
    });
  }

  McpServer? _serverByName(String serverName) {
    final normalizedServerName = _normalizeServerName(serverName);
    if (normalizedServerName.isEmpty) {
      return null;
    }
    for (final server in _servers) {
      if (server.name == normalizedServerName) {
        return server;
      }
    }
    return null;
  }

  String _normalizeServerName(String serverName) {
    return serverName.trim();
  }

  void _invalidateToolRefreshGeneration(String serverName) {
    _toolRefreshGenerationByServerName[serverName] =
        (_toolRefreshGenerationByServerName[serverName] ?? 0) + 1;
  }

  void _invalidateHealthCheckGeneration(String serverName) {
    _healthCheckGenerationByServerName[serverName] =
        (_healthCheckGenerationByServerName[serverName] ?? 0) + 1;
  }

  McpToolCatalog _resolvedRefreshCatalog({
    required McpToolCatalog previousCatalog,
    required McpToolCatalog discoveredCatalog,
  }) {
    if (discoveredCatalog.status != McpToolCatalogStatus.failed ||
        previousCatalog.tools.isEmpty) {
      return discoveredCatalog;
    }
    return previousCatalog.copyWith(
      status: discoveredCatalog.status,
      errorMessage: discoveredCatalog.errorMessage,
      clearErrorMessage: discoveredCatalog.errorMessage == null,
      warningMessage: discoveredCatalog.warningMessage,
      clearWarningMessage: discoveredCatalog.warningMessage == null,
      lastScannedAt: discoveredCatalog.lastScannedAt,
    );
  }
}
