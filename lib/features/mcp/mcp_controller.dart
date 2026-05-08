import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../app/support/silent_log.dart';
import 'data/mcp_store.dart';
import 'model/mcp_server.dart';
import 'model/mcp_server_health.dart';
import 'model/mcp_tool.dart';
import 'service/mcp_keyword_index.dart';
import 'service/mcp_tool_discovery_service.dart';

class McpController extends ChangeNotifier {
  McpController._({
    required McpStore store,
    required McpToolDiscoveryService toolDiscoveryService,
    required Duration healthCheckInterval,
    required int autoProbeConcurrency,
    bool isLoading = false,
  }) : _store = store,
       _toolDiscoveryService = toolDiscoveryService,
       _healthCheckInterval = healthCheckInterval,
       _autoProbeConcurrency = _normalizeAutoProbeConcurrency(
         autoProbeConcurrency,
       ),
       _isLoading = isLoading;

  /// Constructs an [McpController] synchronously without performing the
  /// initial server-list load. Reports `isLoading == true` until the caller
  /// invokes [refresh] (typically as `unawaited(controller.refresh())`).
  ///
  /// Used by `main.dart` to keep the MCP servers file load off the boot
  /// critical path — home reads `servers` only inside the workspace-selected
  /// branch and tool-catalog preview, both of which surface naturally once
  /// the background refresh fires `notifyListeners()`.
  factory McpController.uninitialized({
    required String initialFilePath,
    McpStore? store,
    McpToolDiscoveryService? toolDiscoveryService,
    Duration healthCheckInterval = const Duration(seconds: 30),
    int autoProbeConcurrency = defaultAutoProbeConcurrency,
  }) {
    return McpController._(
      store: store ?? McpStore(serversFilePath: initialFilePath),
      toolDiscoveryService:
          toolDiscoveryService ?? DefaultMcpToolDiscoveryService(),
      healthCheckInterval: healthCheckInterval,
      autoProbeConcurrency: autoProbeConcurrency,
      isLoading: true,
    );
  }

  static Future<McpController> create({
    required String initialFilePath,
    McpStore? store,
    McpToolDiscoveryService? toolDiscoveryService,
    Duration healthCheckInterval = const Duration(seconds: 30),
    int autoProbeConcurrency = defaultAutoProbeConcurrency,
  }) async {
    final controller = McpController._(
      store: store ?? McpStore(serversFilePath: initialFilePath),
      toolDiscoveryService:
          toolDiscoveryService ?? DefaultMcpToolDiscoveryService(),
      healthCheckInterval: healthCheckInterval,
      autoProbeConcurrency: autoProbeConcurrency,
    );
    await controller.refresh();
    return controller;
  }

  static const Duration _pageActivationWorkDelay = Duration(milliseconds: 450);
  static const Duration _autoProbeGap = Duration(milliseconds: 80);
  static const int defaultAutoProbeConcurrency = 5;
  static const int _minAutoProbeConcurrency = 1;
  static const int _maxAutoProbeConcurrency = 32;

  final McpStore _store;
  final McpToolDiscoveryService _toolDiscoveryService;
  final Duration _healthCheckInterval;
  int _autoProbeConcurrency;

  bool _isLoading;
  String? _errorMessage;
  List<McpServer> _servers = const <McpServer>[];
  List<McpServer> _serversView = const <McpServer>[];
  final Map<String, McpToolCatalog> _toolCatalogByServerName =
      <String, McpToolCatalog>{};
  final Map<String, int> _toolRefreshGenerationByServerName = <String, int>{};
  final Map<String, McpServerHealth> _healthByServerName =
      <String, McpServerHealth>{};
  final Map<String, int> _healthCheckGenerationByServerName = <String, int>{};
  final Queue<Completer<bool>> _autoProbeSlotWaiters = Queue<Completer<bool>>();
  McpPersistenceIssue? _persistenceIssue;
  bool _isDisposed = false;
  bool _isPageActive = false;
  bool _autoToolRefreshInProgress = false;
  bool _autoHealthCheckInProgress = false;
  int _activeAutoProbeSlots = 0;
  DateTime? _lastBatchProbeAt;
  static const int _maxRecentProbeRecords = 30;
  Future<void> _operationQueue = Future<void>.value();
  Timer? _pageActivationWorkTimer;
  Timer? _healthCheckTimer;
  final ValueNotifier<int> _saveSuccessSignal = ValueNotifier<int>(0);

  /// Increments after each successful `_store.save`. UI may listen via
  /// `HighlightPulse` to flash on commit.
  ValueListenable<int> get saveSuccessSignal => _saveSuccessSignal;

  // ----- Keyword inverted index (Phase 2) -------------------------------
  final McpKeywordIndexService _keywordIndexService = McpKeywordIndexService();
  McpKeywordIndex? _keywordIndex;
  bool _keywordIndexLoadedFromDisk = false;

  /// 当前最近一次构建（或落盘加载）的关键词倒排索引。从未构建则为 null。
  McpKeywordIndex? get keywordIndex => _keywordIndex;

  /// 是否正在构建（用于按钮 disable / 防抖）。
  bool get isBuildingKeywordIndex => _keywordIndexService.isBuilding;

  /// 启动期惰性加载落盘索引；幂等。
  Future<void> ensureKeywordIndexLoaded() async {
    if (_keywordIndexLoadedFromDisk) return;
    _keywordIndexLoadedFromDisk = true;
    final loaded = await _keywordIndexService.loadFromDisk();
    if (_isDisposed) return;
    if (loaded != null) {
      _keywordIndex = loaded;
      notifyListeners();
    }
  }

  /// 触发一次构建。`onProgress` 直接转发自服务层；构建完毕会更新
  /// [keywordIndex] 并 notifyListeners。返回构建结果（含跳过统计）。
  /// 调用方负责防抖 / disable 按钮 —— 服务层也做了单飞兜底。
  Future<McpKeywordIndexBuildResult> buildKeywordIndex({
    required void Function(McpKeywordIndexProgress) onProgress,
  }) async {
    final snapshot = List<McpServer>.unmodifiable(_servers);
    final result = await _keywordIndexService.build(
      servers: snapshot,
      resolveTools: (server) async {
        // 仅索引「当前可用」的服务 —— 即 catalog 已 ready 且工具列表非空。
        // 未探测的 stdio 服务首启可达 6 分钟，强行 fresh-discover 会让弹窗
        // 卡住数分钟，违反「按钮触发的轻量任务」体感。索引刷新依赖
        // 用户/自动 probe 自行先把 catalog 拉好，未拉到的服务计入 skipped。
        final cached = toolCatalogFor(server.name);
        if (cached.status == McpToolCatalogStatus.ready) {
          return cached.tools;
        }
        return const <McpTool>[];
      },
      onProgress: onProgress,
    );
    if (!_isDisposed) {
      _keywordIndex = result.index;
      notifyListeners();
    }
    return result;
  }

  /// 删除已构建的索引（设置项关闭等场景）。
  Future<void> clearKeywordIndex() async {
    await _keywordIndexService.deleteFromDisk();
    if (_isDisposed) return;
    _keywordIndex = null;
    notifyListeners();
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<McpServer> get servers => _serversView;
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

  int get autoProbeConcurrency => _autoProbeConcurrency;
  int get activeAutoProbeSlots => _activeAutoProbeSlots;
  int get queuedAutoProbeTasks => _autoProbeSlotWaiters.length;

  /// 最近一次自动批量探测（tools 拉取或健康检查）的发起时间（UTC）。
  DateTime? get lastBatchProbeAt => _lastBatchProbeAt;

  /// 健康检查的固定周期，用于 UI 推算「下次自动探测」时间。
  Duration get healthCheckInterval => _healthCheckInterval;

  /// 推算下次自动健康探测的 UTC 时间；当前没有可用信息时返回 null。
  DateTime? get nextScheduledProbeAt {
    if (_isDisposed || !_isPageActive) {
      return null;
    }
    if (!_servers.any((server) => server.enabled)) {
      return null;
    }
    final base = _lastBatchProbeAt;
    if (base == null) {
      return DateTime.now().toUtc().add(_healthCheckInterval);
    }
    return base.add(_healthCheckInterval);
  }

  bool get isAutoToolRefreshInProgress => _autoToolRefreshInProgress;
  bool get isAutoHealthCheckInProgress => _autoHealthCheckInProgress;

  void updateAutoProbeConcurrency(int value) {
    final normalized = _normalizeAutoProbeConcurrency(value);
    if (_autoProbeConcurrency == normalized) {
      return;
    }
    _autoProbeConcurrency = normalized;
    _notifyAutoProbeMetricsChanged();
    _drainAutoProbeSlotQueue();
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
    _pageActivationWorkTimer?.cancel();
    _healthCheckTimer?.cancel();
    _cancelQueuedAutoProbeSlots();
    try {
      _toolDiscoveryService.dispose();
    } catch (error, stack) {
      silentLog('mcp', 'dispose.discoveryService', error, stack);
    }
    _saveSuccessSignal.dispose();
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
      _schedulePageActivationWork();
    } else {
      _pageActivationWorkTimer?.cancel();
      _cancelQueuedAutoProbeSlots();
      _invalidateToolRefreshGenerations();
      _invalidateHealthCheckGenerations();
    }
    _reconcileHealthCheckTimer();
  }

  void _schedulePageActivationWork() {
    _pageActivationWorkTimer?.cancel();
    _pageActivationWorkTimer = Timer(_pageActivationWorkDelay, () {
      _pageActivationWorkTimer = null;
      if (_isDisposed || !_isPageActive) {
        return;
      }
      _autoRefreshEnabledServerTools();
      _autoCheckEnabledServerHealth(force: true);
    });
  }

  Future<void> refresh() async {
    await _enqueueOperation(() async {
      _isLoading = true;
      _errorMessage = null;
      _persistenceIssue = null;
      notifyListeners();

      try {
        final loadResult = await _store.load();
        _setServers(loadResult.servers);
        _syncToolCatalogsWithServers(_servers);
        _syncHealthStatusesWithServers(_servers);
        _persistenceIssue = loadResult.issue;
      } catch (error) {
        _setServers(const <McpServer>[]);
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
      return _commitSaveLocked(updatedServers, previousServerName: server.name);
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

  /// 用户主动「一键重连」：并行触发 Tool 重扫与健康复测，对外作为单次刷新动作。
  /// 不修改连续失败计数（健康复测内部会自然更新），只清空旧的探测历史，让卡片
  /// 立即显示最新一次探测结果而非沿用历史快照。
  Future<void> reconnectServer(String serverName) async {
    final normalizedServerName = _normalizeServerName(serverName);
    if (normalizedServerName.isEmpty) {
      return;
    }
    final previousHealth = healthStatusFor(normalizedServerName);
    _healthByServerName[normalizedServerName] = previousHealth.copyWith(
      recentProbes: const <McpHealthProbeRecord>[],
    );
    notifyListeners();
    await Future.wait<void>(<Future<void>>[
      refreshServerTools(normalizedServerName),
      checkServerHealth(normalizedServerName),
    ]);
  }

  /// 批量重连「需要处理」的服务（连续失败 ≥ 3 次或最近一次探测明确不健康）。
  /// 仅作用于已启用服务；返回参与本次重连的服务名列表，调用方据此显示进度/反馈。
  Future<List<String>> reconnectFailingServers() async {
    final candidates = <String>[
      for (final server in _servers)
        if (server.enabled)
          if (() {
            final health = healthStatusFor(server.name);
            return health.needsAttention ||
                health.status == McpServerHealthStatus.unhealthy;
          }())
            server.name,
    ];
    if (candidates.isEmpty) {
      return const <String>[];
    }
    await Future.wait<void>(<Future<void>>[
      for (final name in candidates) reconnectServer(name),
    ]);
    return candidates;
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

    final stopwatch = Stopwatch()..start();
    try {
      final resolvedHealth = await _toolDiscoveryService.checkHealth(server);
      stopwatch.stop();
      if (_isDisposed ||
          !_isPageActive ||
          _healthCheckGenerationByServerName[normalizedServerName] !=
              nextGeneration) {
        return;
      }
      final latencyMs = stopwatch.elapsedMilliseconds;
      final completedAt =
          resolvedHealth.lastCheckedAt ?? DateTime.now().toUtc();
      final isHealthy = resolvedHealth.status == McpServerHealthStatus.healthy;
      final consecutiveFailures = isHealthy
          ? 0
          : previousHealth.consecutiveFailures + 1;
      final probeRecord = McpHealthProbeRecord(
        status: resolvedHealth.status,
        timestamp: completedAt,
        latencyMs: isHealthy ? latencyMs : null,
        errorMessage: resolvedHealth.errorMessage,
      );
      final mergedRecent = _appendProbeRecord(
        previousHealth.recentProbes,
        probeRecord,
      );
      _healthByServerName[normalizedServerName] = resolvedHealth.copyWith(
        latencyMs: isHealthy ? latencyMs : null,
        clearLatency: !isHealthy,
        consecutiveFailures: consecutiveFailures,
        lastSuccessAt: isHealthy ? completedAt : previousHealth.lastSuccessAt,
        recentProbes: mergedRecent,
      );
      notifyListeners();
    } catch (error) {
      stopwatch.stop();
      if (_isDisposed ||
          !_isPageActive ||
          _healthCheckGenerationByServerName[normalizedServerName] !=
              nextGeneration) {
        return;
      }
      final completedAt = DateTime.now().toUtc();
      final probeRecord = McpHealthProbeRecord(
        status: McpServerHealthStatus.unhealthy,
        timestamp: completedAt,
        errorMessage: '$error',
      );
      final mergedRecent = _appendProbeRecord(
        previousHealth.recentProbes,
        probeRecord,
      );
      _healthByServerName[normalizedServerName] = McpServerHealth(
        status: McpServerHealthStatus.unhealthy,
        errorMessage: '$error',
        lastCheckedAt: completedAt,
        consecutiveFailures: previousHealth.consecutiveFailures + 1,
        lastSuccessAt: previousHealth.lastSuccessAt,
        recentProbes: mergedRecent,
      );
      notifyListeners();
    }
  }

  List<McpHealthProbeRecord> _appendProbeRecord(
    List<McpHealthProbeRecord> previous,
    McpHealthProbeRecord record,
  ) {
    final next = <McpHealthProbeRecord>[record, ...previous];
    if (next.length > _maxRecentProbeRecords) {
      next.removeRange(_maxRecentProbeRecords, next.length);
    }
    return List<McpHealthProbeRecord>.unmodifiable(next);
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
    _setServers(nextServers);
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
      _saveSuccessSignal.value = _saveSuccessSignal.value + 1;
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
      _setServers(previousServers);
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

  void _setServers(List<McpServer> servers) {
    _servers = servers;
    _serversView = List<McpServer>.unmodifiable(servers);
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    if (_isDisposed) {
      return Future<T>.error(StateError('McpController is disposed'));
    }
    final completer = Completer<T>();
    _operationQueue = _operationQueue.catchError((_) {}).then((_) async {
      // Check disposed state before executing to avoid race conditions.
      if (_isDisposed) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('McpController is disposed'));
        }
        return;
      }
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
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
    if (_autoToolRefreshInProgress) {
      return;
    }
    _autoToolRefreshInProgress = true;
    _notifyAutoProbeMetricsChanged();
    unawaited(_runAutoToolRefreshes(force: force));
  }

  Future<void> _runAutoToolRefreshes({required bool force}) async {
    try {
      final targets = <McpServer>[];
      for (final server in _servers) {
        if (_isDisposed || !_isPageActive) {
          return;
        }
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
        targets.add(server);
      }
      await _runAutoProbeWorkerPool(
        targets,
        (server) => refreshServerTools(server.name),
      );
    } finally {
      _autoToolRefreshInProgress = false;
      _notifyAutoProbeMetricsChanged();
    }
  }

  void _autoCheckEnabledServerHealth({bool force = false}) {
    if (_autoHealthCheckInProgress) {
      return;
    }
    _autoHealthCheckInProgress = true;
    _notifyAutoProbeMetricsChanged();
    unawaited(_runAutoHealthChecks(force: force));
  }

  Future<void> _runAutoHealthChecks({required bool force}) async {
    try {
      final now = DateTime.now().toUtc();
      final targets = <McpServer>[];
      for (final server in _servers) {
        if (_isDisposed || !_isPageActive) {
          return;
        }
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
        targets.add(server);
      }
      await _runAutoProbeWorkerPool(
        targets,
        (server) => checkServerHealth(server.name),
      );
    } finally {
      _autoHealthCheckInProgress = false;
      _notifyAutoProbeMetricsChanged();
    }
  }

  Future<void> _runAutoProbeWorkerPool(
    List<McpServer> targets,
    Future<void> Function(McpServer server) operation,
  ) async {
    if (targets.isEmpty || _isDisposed || !_isPageActive) {
      return;
    }
    var nextIndex = 0;
    final workerCount = math.min(_autoProbeConcurrency, targets.length);
    await Future.wait<void>(
      List<Future<void>>.generate(workerCount, (_) async {
        while (!_isDisposed && _isPageActive) {
          final index = nextIndex;
          nextIndex += 1;
          if (index >= targets.length) {
            return;
          }
          try {
            await _runWithAutoProbeSlot(() => operation(targets[index]));
          } catch (error, stack) {
            silentLog('mcp', '_runAutoProbeWorkerPool', error, stack);
          }
          if (_isDisposed || !_isPageActive) {
            return;
          }
          if (_autoProbeGap > Duration.zero && index < targets.length - 1) {
            await Future<void>.delayed(_autoProbeGap);
          }
        }
      }),
    );
  }

  Future<void> _runWithAutoProbeSlot(Future<void> Function() operation) async {
    final acquired = await _acquireAutoProbeSlot();
    if (!acquired) {
      return;
    }
    try {
      if (!_isDisposed && _isPageActive) {
        await operation();
      }
    } finally {
      _releaseAutoProbeSlot();
    }
  }

  Future<bool> _acquireAutoProbeSlot() {
    if (_isDisposed || !_isPageActive) {
      return Future<bool>.value(false);
    }
    if (_activeAutoProbeSlots < _autoProbeConcurrency) {
      _activeAutoProbeSlots += 1;
      _notifyAutoProbeMetricsChanged();
      return Future<bool>.value(true);
    }
    final waiter = Completer<bool>();
    _autoProbeSlotWaiters.add(waiter);
    _notifyAutoProbeMetricsChanged();
    return waiter.future;
  }

  void _releaseAutoProbeSlot() {
    if (_activeAutoProbeSlots > 0) {
      _activeAutoProbeSlots -= 1;
      _notifyAutoProbeMetricsChanged();
    }
    _drainAutoProbeSlotQueue();
  }

  void _drainAutoProbeSlotQueue() {
    var didChange = false;
    while (!_isDisposed &&
        _isPageActive &&
        _autoProbeSlotWaiters.isNotEmpty &&
        _activeAutoProbeSlots < _autoProbeConcurrency) {
      final waiter = _autoProbeSlotWaiters.removeFirst();
      if (waiter.isCompleted) {
        continue;
      }
      _activeAutoProbeSlots += 1;
      waiter.complete(true);
      didChange = true;
    }
    if (didChange) {
      _notifyAutoProbeMetricsChanged();
    }
  }

  void _cancelQueuedAutoProbeSlots() {
    var didCancel = false;
    while (_autoProbeSlotWaiters.isNotEmpty) {
      final waiter = _autoProbeSlotWaiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.complete(false);
        didCancel = true;
      }
    }
    if (didCancel) {
      _notifyAutoProbeMetricsChanged();
    }
  }

  void _notifyAutoProbeMetricsChanged() {
    notifyListeners();
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

  static int _normalizeAutoProbeConcurrency(int value) {
    if (value < _minAutoProbeConcurrency) {
      return defaultAutoProbeConcurrency;
    }
    return value.clamp(_minAutoProbeConcurrency, _maxAutoProbeConcurrency);
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
