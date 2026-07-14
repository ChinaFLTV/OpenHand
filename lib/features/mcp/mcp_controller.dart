import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../app/support/silent_log.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/timer_safety.dart';
import '../ai/index.dart'
    show
        AiBuiltinToolConfig,
        AiBuiltinToolKind,
        AiModelConfig,
        AiAuthScheme,
        AiProtocolType,
        AiResolvedTool,
        AiResolvedToolCatalog,
        AiToolCall,
        AiToolDefinition,
        AiToolExecutionKind,
        AiToolExecutionRegistry,
        AiToolRuntimeService,
        BashToolExecutionStatus,
        agentBuiltinToolCanonicalName;
import '../instructions/index.dart';
import '../knowledge_base/index.dart';
import '../memory/index.dart';
import '../skills/index.dart';
import 'data/mcp_server_ops_store.dart';
import 'data/mcp_store.dart';
import 'model/mcp_server.dart';
import 'model/mcp_server_health.dart';
import 'model/mcp_server_ops.dart';
import 'model/mcp_tool.dart';
import 'service/mcp_keyword_index.dart';
import 'service/mcp_ops_endpoint.dart';
import 'service/mcp_server_ops_runtime.dart';
import 'service/mcp_stdio_process_manager.dart';
import 'service/mcp_tool_discovery_service.dart';

class McpOpsRuntimeBindings {
  const McpOpsRuntimeBindings({
    required this.builtinToolConfigsProvider,
    required this.skillsControllerProvider,
    required this.memoryControllerProvider,
    required this.instructionsControllerProvider,
    required this.knowledgeBaseControllerProvider,
    this.toolRuntimeServiceProvider,
    this.opsModelProvider,
  });

  final List<AiBuiltinToolConfig> Function() builtinToolConfigsProvider;
  final SkillsController? Function() skillsControllerProvider;
  final MemoryController? Function() memoryControllerProvider;
  final InstructionsController? Function() instructionsControllerProvider;
  final KnowledgeBaseController? Function() knowledgeBaseControllerProvider;

  /// 共享的 AI 工具运行时，供 MCP 运维服务器真正执行内建工具（而非仅返回配置）。
  final AiToolRuntimeService? Function()? toolRuntimeServiceProvider;

  /// 首个可用模型，供依赖大模型的内建工具（Task/WebSearch/WebFetch/Agent）使用；
  /// 无可用模型时返回 null，调用方据此优雅报错。
  final AiModelConfig? Function()? opsModelProvider;
}

class McpController extends ChangeNotifier {
  McpController._({
    required McpStore store,
    required McpServerOpsStore opsStore,
    required McpToolDiscoveryService toolDiscoveryService,
    required bool ownsToolDiscoveryService,
    required Duration healthCheckInterval,
    required int autoProbeConcurrency,
    bool isLoading = false,
  }) : _store = store,
       _opsStore = opsStore,
       _toolDiscoveryService = toolDiscoveryService,
       _ownsToolDiscoveryService = ownsToolDiscoveryService,
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
    final effectiveStore = store ?? McpStore(serversFilePath: initialFilePath);
    return McpController._(
      store: effectiveStore,
      opsStore: McpServerOpsStore(
        storageDirectoryPath: effectiveStore.storageDirectoryPath,
      ),
      toolDiscoveryService:
          toolDiscoveryService ?? DefaultMcpToolDiscoveryService(),
      ownsToolDiscoveryService: toolDiscoveryService == null,
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
    final effectiveStore = store ?? McpStore(serversFilePath: initialFilePath);
    final controller = McpController._(
      store: effectiveStore,
      opsStore: McpServerOpsStore(
        storageDirectoryPath: effectiveStore.storageDirectoryPath,
      ),
      toolDiscoveryService:
          toolDiscoveryService ?? DefaultMcpToolDiscoveryService(),
      ownsToolDiscoveryService: toolDiscoveryService == null,
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
  final McpServerOpsStore _opsStore;
  final McpToolDiscoveryService _toolDiscoveryService;
  final bool _ownsToolDiscoveryService;
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
  McpOpsConfig _opsConfig = const McpOpsConfig();
  McpOpsRuntimeSnapshot _opsSnapshot = const McpOpsRuntimeSnapshot();
  final List<McpOpsAuditEntry> _opsAuditEntries = <McpOpsAuditEntry>[];
  List<McpOpsAuditEntry> _opsAuditEntriesView = const <McpOpsAuditEntry>[];
  final Map<String, Completer<bool>> _opsApprovalCompleters =
      <String, Completer<bool>>{};
  final List<McpOpsApprovalRequest> _opsApprovalRequests =
      <McpOpsApprovalRequest>[];
  List<McpOpsApprovalRequest> _opsApprovalRequestsView =
      const <McpOpsApprovalRequest>[];
  McpServerOpsRuntime? _opsRuntime;
  McpOpsRuntimeBindings? _opsBindings;
  bool _isDisposed = false;
  bool _isPageActive = false;
  bool _autoToolRefreshInProgress = false;
  bool _autoHealthCheckInProgress = false;
  bool _opsPersistenceLoaded = false;
  Future<void>? _opsPersistenceLoadFuture;
  int _activeAutoProbeSlots = 0;
  DateTime? _lastBatchProbeAt;
  static const int _maxRecentProbeRecords = 30;

  /// 内建工具 MCP 端点标识：语义为"执行"（真实调用工具），非旧的"describe"。
  static const String _opsBuiltinEndpointId = 'invoke';

  /// 会话标识与占位工作目录，供 MCP 运维服务器无会话执行内建工具时使用。
  static const String _opsBuiltinSessionId = 'mcp-ops';

  /// 依赖大模型的内建工具：无可用模型时优雅报错，不进入执行。
  static const Set<AiBuiltinToolKind> _opsModelDependentBuiltinKinds =
      <AiBuiltinToolKind>{
        AiBuiltinToolKind.task,
        AiBuiltinToolKind.webSearch,
        AiBuiltinToolKind.webFetch,
      };

  /// 写语义内建工具：作为 MCP destructiveHint 与只读模式门控依据。
  static const Set<AiBuiltinToolKind> _opsWriteBuiltinKinds =
      <AiBuiltinToolKind>{
        AiBuiltinToolKind.bash,
        AiBuiltinToolKind.bashBackground,
        AiBuiltinToolKind.taskStop,
        AiBuiltinToolKind.edit,
        AiBuiltinToolKind.multiEdit,
        AiBuiltinToolKind.applyFileDiffs,
        AiBuiltinToolKind.write,
        AiBuiltinToolKind.notebookEdit,
        AiBuiltinToolKind.deleteFile,
        AiBuiltinToolKind.git,
        AiBuiltinToolKind.skillManager,
        AiBuiltinToolKind.memory,
        AiBuiltinToolKind.machineTerminalWrite,
        AiBuiltinToolKind.machineTerminalExec,
        AiBuiltinToolKind.machineTerminalControl,
      };

  /// 无会话执行时的占位模型：仅用于满足 execute() 的非空约束；
  /// 非模型类工具（Read/Grep/Bash/Edit…）不会读取 context.model。
  static const AiModelConfig _opsPlaceholderModel = AiModelConfig(
    id: 'mcp-ops-placeholder',
    baseUrl: '',
    authScheme: AiAuthScheme.none,
    token: '',
    modelId: '',
    protocolType: AiProtocolType.openai,
  );

  Future<void> _operationQueue = Future<void>.value();
  late final OpenHandDebouncer _pageActivationWorkDebouncer = OpenHandDebouncer(
    delay: _pageActivationWorkDelay,
  );
  late final OpenHandDebouncer _opsPersistenceDebouncer = OpenHandDebouncer(
    delay: const Duration(milliseconds: 650),
    onError: (error, stack) =>
        silentLog('mcp', 'persist ops runtime data', error, stack),
  );
  Timer? _healthCheckTimer;
  Timer? _opsSnapshotNotifyTimer;
  final ValueNotifier<int> _saveSuccessSignal = ValueNotifier<int>(0);

  /// Increments after each successful `_store.save`. UI may listen via
  /// `HighlightPulse` to flash on commit.
  ValueListenable<int> get saveSuccessSignal => _saveSuccessSignal;

  // ----- Keyword inverted index -----------------------------------------
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
    void Function(McpKeywordIndexProgress)? onProgress,
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
      onProgress: onProgress ?? (_) {},
    );
    if (!_isDisposed) {
      _keywordIndex = result.index;
      notifyListeners();
    }
    return result;
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<McpServer> get servers => _serversView;
  String get serversFilePath => _store.serversFilePath;
  String get storageDirectoryPath => _store.storageDirectoryPath;
  McpPersistenceIssue? get persistenceIssue => _persistenceIssue;
  McpOpsConfig get opsConfig => _opsConfig;
  McpOpsRuntimeSnapshot get opsSnapshot => _opsSnapshot;
  List<McpOpsAuditEntry> get opsAuditEntries => _opsAuditEntriesView;
  List<McpOpsApprovalRequest> get opsApprovalRequests =>
      _opsApprovalRequestsView;

  Future<void> ensureOpsPersistenceLoaded() {
    return _ensureOpsPersistenceLoaded();
  }

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
    // tree-lock 防护：当 setPageActive(false) 在
    // _McpViewState.dispose 期间被调用，会经由 _cancelQueuedAutoProbeSlots
    // → _notifyAutoProbeMetricsChanged → notifyListeners 触发
    // _InheritedProviderScope.markNeedsBuild，而此时 BuildOwner 处于
    // _InactiveElements._unmount 的 lockState 阶段，框架会断言
    // "setState() or markNeedsBuild() called when widget tree was locked"。
    // 用 schedulerPhase 判定，若处于持续帧回调 / 暂态回调 / 后置回调期间，
    // 推迟到下一帧再发通知；其它阶段（idle / midFrameMicrotasks）直接发。
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.postFrameCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (_isDisposed) return;
        super.notifyListeners();
      });
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final completer in _opsApprovalCompleters.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    _opsApprovalCompleters.clear();
    _opsApprovalRequests.clear();
    final opsRuntime = _opsRuntime;
    if (opsRuntime != null) {
      unawaited(opsRuntime.stop());
    }
    _pageActivationWorkDebouncer.dispose();
    unawaited(_persistOpsRuntimeData());
    _opsPersistenceDebouncer.dispose();
    _healthCheckTimer?.cancel();
    _opsSnapshotNotifyTimer?.cancel();
    _cancelQueuedAutoProbeSlots();
    if (_ownsToolDiscoveryService) {
      try {
        _toolDiscoveryService.dispose();
      } catch (error, stack) {
        silentLog('mcp', 'dispose.discoveryService', error, stack);
      }
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
      _pageActivationWorkDebouncer.cancel();
      _cancelQueuedAutoProbeSlots();
      _invalidateToolRefreshGenerations();
      _invalidateHealthCheckGenerations();
    }
    _reconcileHealthCheckTimer();
  }

  void _schedulePageActivationWork() {
    _pageActivationWorkDebouncer.schedule(() {
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
        await _ensureOpsPersistenceLoaded(force: true);
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
    if (_opsConfig.autoStart && !_isDisposed) {
      _runDetached(startMcpOpsServer(), 'start MCP ops server');
    }
  }

  void attachOpsRuntimeBindings(McpOpsRuntimeBindings bindings) {
    _opsBindings = bindings;
    _ensureOpsRuntime();
    if (_opsConfig.autoStart && !_isDisposed) {
      _runDetached(startMcpOpsServer(), 'start MCP ops server after bindings');
    }
  }

  Future<bool> saveOpsConfig(McpOpsConfig config) async {
    try {
      await _ensureOpsPersistenceLoaded();
      final normalized = config.copyWith();
      await _opsStore.saveConfig(normalized);
      _opsConfig = normalized;
      _opsRuntime?.updateConfig(normalized);
      notifyListeners();
      return true;
    } catch (error, stack) {
      silentLog('mcp', 'save ops config', error, stack);
      return false;
    }
  }

  Future<bool> startMcpOpsServer() async {
    if (_isDisposed) return false;
    try {
      await _ensureOpsPersistenceLoaded();
      await _ensureOpsRuntime().start(_opsConfig);
      notifyListeners();
      return true;
    } catch (error, stack) {
      silentLog('mcp', 'start ops server', error, stack);
      notifyListeners();
      return false;
    }
  }

  Future<bool> stopMcpOpsServer() async {
    try {
      await _ensureOpsPersistenceLoaded();
      await _ensureOpsRuntime().stop();
      notifyListeners();
      return true;
    } catch (error, stack) {
      silentLog('mcp', 'stop ops server', error, stack);
      return false;
    }
  }

  Future<bool> restartMcpOpsServer() async {
    try {
      await _ensureOpsPersistenceLoaded();
      await _ensureOpsRuntime().restart(_opsConfig);
      notifyListeners();
      return true;
    } catch (error, stack) {
      silentLog('mcp', 'restart ops server', error, stack);
      notifyListeners();
      return false;
    }
  }

  Future<McpOpsConnectivityResult> testMcpOpsConnectivity() async {
    try {
      await _ensureOpsPersistenceLoaded();
      final result = await _ensureOpsRuntime().testConnectivity();
      notifyListeners();
      return result;
    } catch (error, stack) {
      silentLog('mcp', 'test ops connectivity', error, stack);
      return McpOpsConnectivityResult(
        ok: false,
        message: '$error',
        checkedAt: DateTime.now().toUtc(),
      );
    }
  }

  void resolveOpsApproval(String id, {required bool approved}) {
    final completer = _opsApprovalCompleters.remove(id);
    _opsApprovalRequests.removeWhere((item) => item.id == id);
    _opsApprovalRequestsView = List<McpOpsApprovalRequest>.unmodifiable(
      _opsApprovalRequests,
    );
    if (completer != null && !completer.isCompleted) {
      completer.complete(approved);
    }
    notifyListeners();
  }

  McpServerOpsRuntime _ensureOpsRuntime() {
    final existing = _opsRuntime;
    if (existing != null) {
      return existing;
    }
    final runtime = McpServerOpsRuntime(
      toolListProvider: _opsToolDefinitions,
      toolInvoker: _invokeOpsTool,
      approvalGate: _handleOpsApprovalRequest,
      auditSink: _recordOpsAudit,
      snapshotSink: (snapshot) {
        _opsSnapshot = snapshot;
        _scheduleOpsPersistence();
        _scheduleOpsSnapshotNotify();
      },
    );
    _opsRuntime = runtime;
    runtime.hydrateMetrics(_opsSnapshot);
    return runtime;
  }

  Future<void> _ensureOpsPersistenceLoaded({bool force = false}) {
    if (!force && _opsPersistenceLoaded) {
      return Future<void>.value();
    }
    final pending = _opsPersistenceLoadFuture;
    if (pending != null) {
      return pending;
    }
    final future = _loadOpsPersistenceLocked();
    _opsPersistenceLoadFuture = future.whenComplete(() {
      if (identical(_opsPersistenceLoadFuture, future)) {
        _opsPersistenceLoadFuture = null;
      }
    });
    return _opsPersistenceLoadFuture!;
  }

  Future<void> _loadOpsPersistenceLocked() async {
    final config = await _opsStore.loadConfig();
    final persistedOps = await _opsStore.loadRuntimeData();
    _opsConfig = config;
    _opsRuntime?.updateConfig(config);
    if (_opsRuntime?.isRunning != true) {
      _hydratePersistedOpsRuntimeData(persistedOps);
    }
    _opsPersistenceLoaded = true;
  }

  void _scheduleOpsSnapshotNotify() {
    if (_isDisposed || (_opsSnapshotNotifyTimer?.isActive ?? false)) {
      return;
    }
    _opsSnapshotNotifyTimer = startSafeTimer(
      const Duration(milliseconds: 80),
      () {
        _opsSnapshotNotifyTimer = null;
        notifyListeners();
      },
      onError: (error, stack) =>
          silentLog('mcp', 'ops snapshot notify', error, stack),
    );
  }

  Future<bool> _handleOpsApprovalRequest(McpOpsApprovalRequest request) async {
    final completer = Completer<bool>();
    _opsApprovalCompleters[request.id] = completer;
    _opsApprovalRequests.insert(0, request);
    _opsApprovalRequestsView = List<McpOpsApprovalRequest>.unmodifiable(
      _opsApprovalRequests,
    );
    notifyListeners();
    final timeout = request.expiresAt.difference(DateTime.now().toUtc());
    try {
      return await completer.future.timeout(
        timeout.isNegative ? Duration.zero : timeout,
        onTimeout: () => false,
      );
    } finally {
      _opsApprovalCompleters.remove(request.id);
      _opsApprovalRequests.removeWhere((item) => item.id == request.id);
      _opsApprovalRequestsView = List<McpOpsApprovalRequest>.unmodifiable(
        _opsApprovalRequests,
      );
      notifyListeners();
    }
  }

  void _recordOpsAudit(McpOpsAuditEntry entry) {
    _opsAuditEntries.insert(0, entry);
    if (_opsAuditEntries.length > mcpOpsMaxAuditEntries) {
      _opsAuditEntries.removeRange(
        mcpOpsMaxAuditEntries,
        _opsAuditEntries.length,
      );
    }
    _opsAuditEntriesView = List<McpOpsAuditEntry>.unmodifiable(
      _opsAuditEntries,
    );
    _scheduleOpsPersistence();
    _scheduleOpsSnapshotNotify();
  }

  Future<McpOpsPersistenceReport> measureOpsRuntimeData() async {
    await _ensureOpsPersistenceLoaded();
    return _opsStore.measureRuntimeData();
  }

  Future<McpOpsPersistenceReport> clearOpsRuntimeData({
    DateTime? startUtc,
    DateTime? endUtc,
  }) async {
    await _ensureOpsPersistenceLoaded();
    final before = await _opsStore.measureRuntimeData();
    final clearsAll = startUtc == null && endUtc == null;
    _opsRuntime?.clearMetrics(startUtc: startUtc, endUtc: endUtc);
    if (clearsAll && _opsRuntime?.isRunning != true) {
      _opsSnapshot = const McpOpsRuntimeSnapshot();
    } else if (!clearsAll && _opsRuntime?.isRunning != true) {
      _opsSnapshot = _opsSnapshot.copyWith(
        trafficSeries: _opsSnapshot.trafficSeries
            .where((sample) {
              return !_mcpOpsTimestampInRange(
                sample.minute,
                startUtc: startUtc,
                endUtc: endUtc,
              );
            })
            .toList(growable: false),
      );
    }
    _opsAuditEntries.removeWhere(
      (entry) => clearsAll
          ? true
          : _mcpOpsTimestampInRange(
              entry.timestamp,
              startUtc: startUtc,
              endUtc: endUtc,
            ),
    );
    _opsAuditEntriesView = List<McpOpsAuditEntry>.unmodifiable(
      _opsAuditEntries,
    );
    _opsPersistenceDebouncer.cancel();
    await _persistOpsRuntimeData();
    notifyListeners();
    return before;
  }

  void _hydratePersistedOpsRuntimeData(McpOpsPersistedRuntimeData data) {
    final snapshot = data.snapshot?.asOfflinePersistedSnapshot();
    if (snapshot != null) {
      _opsSnapshot = snapshot;
      _opsRuntime?.hydrateMetrics(snapshot);
    }
    final entries = List<McpOpsAuditEntry>.from(data.auditEntries)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _opsAuditEntries
      ..clear()
      ..addAll(entries.take(mcpOpsMaxAuditEntries));
    _opsAuditEntriesView = List<McpOpsAuditEntry>.unmodifiable(
      _opsAuditEntries,
    );
  }

  void _scheduleOpsPersistence() {
    if (_isDisposed) return;
    _opsPersistenceDebouncer.schedule(_persistOpsRuntimeData);
  }

  Future<void> _persistOpsRuntimeData() async {
    await _ensureOpsPersistenceLoaded();
    final entries = _opsAuditEntries.take(mcpOpsMaxPersistedAuditEntries);
    await _opsStore.saveRuntimeData(
      McpOpsPersistedRuntimeData(
        snapshot: _mcpOpsRuntimeSnapshotHasData(_opsSnapshot)
            ? _opsSnapshot
            : null,
        auditEntries: entries.toList(growable: false),
      ),
    );
  }

  List<McpOpsToolDefinition> _opsToolDefinitions() {
    final tools = <McpOpsToolDefinition>[];
    tools.addAll(_opsBuiltinToolDefinitions());
    tools.addAll(_opsMemoryToolDefinitions());
    tools.addAll(_opsSkillToolDefinitions());
    tools.addAll(_opsInstructionToolDefinitions());
    tools.addAll(_opsKnowledgeToolDefinitions());
    tools.addAll(_opsMcpBridgeToolDefinitions());
    return List<McpOpsToolDefinition>.unmodifiable(tools);
  }

  List<McpOpsToolDefinition> _opsBuiltinToolDefinitions() {
    if (!_opsConfig.surfaceEnabled(McpOpsExposureSurface.builtinTools)) {
      return const <McpOpsToolDefinition>[];
    }
    final bindings = _opsBindings;
    final configs =
        bindings?.builtinToolConfigsProvider() ?? const <AiBuiltinToolConfig>[];
    final tools = <McpOpsToolDefinition>[];
    for (final config in configs) {
      if (!config.enabled) continue;
      final base = AiToolRuntimeService.builtinToolDefault(config.kind);
      if (base == null) continue;
      final itemId = config.kind.name;
      if (!_opsVisible(
        McpOpsExposureSurface.builtinTools,
        itemId,
        _opsBuiltinEndpointId,
      )) {
        continue;
      }
      final canonicalName = agentBuiltinToolCanonicalName(config.kind);
      final schemaOverride = config.schemaOverride;
      tools.add(
        McpOpsToolDefinition(
          name: _opsToolName('builtin', canonicalName, _opsBuiltinEndpointId),
          title: config.displayName?.trim().isNotEmpty == true
              ? config.displayName!.trim()
              : canonicalName,
          // 优先用户覆盖，否则回落到工具的真实 Claude Code 风格描述与 JSON schema。
          description: _opsBuiltinDescription(
            config,
            base.definition.description,
          ),
          surface: McpOpsExposureSurface.builtinTools,
          itemId: itemId,
          endpointId: _opsBuiltinEndpointId,
          inputSchema: schemaOverride != null && schemaOverride.isNotEmpty
              ? schemaOverride
              : base.definition.parameters,
          isWrite: _builtinKindMayWrite(config.kind),
        ),
      );
    }
    return tools;
  }

  /// 内建工具描述：用户 summary/promptOverride 优先，否则用工具默认描述。
  String _opsBuiltinDescription(
    AiBuiltinToolConfig config,
    String fallbackDescription,
  ) {
    final summary = config.summary?.trim();
    if (summary != null && summary.isNotEmpty) return summary;
    final prompt = config.promptOverride?.trim();
    if (prompt != null && prompt.isNotEmpty) return prompt;
    return fallbackDescription.trim();
  }

  List<McpOpsToolDefinition> _opsMemoryToolDefinitions() {
    const surface = McpOpsExposureSurface.memory;
    if (!_opsConfig.surfaceEnabled(surface)) {
      return const <McpOpsToolDefinition>[];
    }
    final entries =
        _opsBindings?.memoryControllerProvider()?.entries ??
        const <UserMemoryEntry>[];
    return [
      for (final entry in entries)
        if (_opsVisible(surface, entry.id, 'read'))
          McpOpsToolDefinition(
            name: _opsToolName('memory', entry.id, 'read'),
            title: entry.displayTitle,
            description: 'Read an approved OpenHand memory entry.',
            surface: surface,
            itemId: entry.id,
            endpointId: 'read',
            inputSchema: _opsObjectSchema(),
          ),
    ];
  }

  List<McpOpsToolDefinition> _opsSkillToolDefinitions() {
    const surface = McpOpsExposureSurface.skills;
    if (!_opsConfig.surfaceEnabled(surface)) {
      return const <McpOpsToolDefinition>[];
    }
    final skills =
        _opsBindings?.skillsControllerProvider()?.skills ??
        const <LocalSkill>[];
    return [
      for (final skill in skills)
        if (_opsVisible(surface, skill.name, 'manifest'))
          McpOpsToolDefinition(
            name: _opsToolName('skill', skill.name, 'manifest'),
            title: skill.name,
            description: skill.description.trim().isEmpty
                ? 'Read an approved OpenHand skill manifest summary.'
                : skill.description.trim(),
            surface: surface,
            itemId: skill.name,
            endpointId: 'manifest',
            inputSchema: _opsObjectSchema(),
          ),
    ];
  }

  List<McpOpsToolDefinition> _opsInstructionToolDefinitions() {
    const surface = McpOpsExposureSurface.instructions;
    if (!_opsConfig.surfaceEnabled(surface)) {
      return const <McpOpsToolDefinition>[];
    }
    final entries =
        _opsBindings?.instructionsControllerProvider()?.entries ??
        const <UserInstructionEntry>[];
    return [
      for (final entry in entries)
        if (entry.enabled && _opsVisible(surface, entry.id, 'read'))
          McpOpsToolDefinition(
            name: _opsToolName('instruction', entry.id, 'read'),
            title: entry.name,
            description: entry.description.trim().isEmpty
                ? 'Read an approved OpenHand user instruction.'
                : entry.description.trim(),
            surface: surface,
            itemId: entry.id,
            endpointId: 'read',
            inputSchema: _opsObjectSchema(),
          ),
    ];
  }

  List<McpOpsToolDefinition> _opsKnowledgeToolDefinitions() {
    const surface = McpOpsExposureSurface.knowledgeBase;
    if (!_opsConfig.surfaceEnabled(surface)) {
      return const <McpOpsToolDefinition>[];
    }
    final sources =
        _opsBindings?.knowledgeBaseControllerProvider()?.sources ??
        const <KnowledgeSource>[];
    return [
      for (final source in sources)
        if (_opsVisible(surface, source.id, 'metadata'))
          McpOpsToolDefinition(
            name: _opsToolName('knowledge', source.id, 'metadata'),
            title: source.title,
            description: 'Read approved knowledge source metadata.',
            surface: surface,
            itemId: source.id,
            endpointId: 'metadata',
            inputSchema: _opsObjectSchema(),
          ),
    ];
  }

  List<McpOpsToolDefinition> _opsMcpBridgeToolDefinitions() {
    const surface = McpOpsExposureSurface.mcpServers;
    if (!_opsConfig.surfaceEnabled(surface)) {
      return const <McpOpsToolDefinition>[];
    }
    final tools = <McpOpsToolDefinition>[];
    for (final server in _servers) {
      if (!server.enabled || !_opsConfig.itemVisible(surface, server.name)) {
        continue;
      }
      // 兜底：即便某个 server 因后期改端口/host 变成指向本机运维入口，也绝不
      // 把它反向桥接出去，避免引用循环与工具无限膨胀。
      if (isSelfReferencingServer(server)) {
        continue;
      }
      final catalog = toolCatalogFor(server.name);
      for (final tool in catalog.tools) {
        final endpointId = tool.id;
        if (!_opsVisible(surface, server.name, endpointId)) {
          continue;
        }
        tools.add(
          McpOpsToolDefinition(
            name: _opsToolName('mcp', server.name, tool.id),
            title: '${server.name} / ${tool.name}',
            description: tool.description.trim().isEmpty
                ? 'Call an approved tool from the MCP server ${server.name}.'
                : tool.description.trim(),
            surface: surface,
            itemId: server.name,
            endpointId: endpointId,
            inputSchema: tool.inputSchema,
            isWrite: _mcpToolMayWrite(tool),
          ),
        );
      }
    }
    return tools;
  }

  Future<McpOpsToolInvocationResult> _invokeOpsTool(
    McpOpsToolDefinition tool,
    Map<String, Object?> arguments,
    McpOpsToolInvocationContext context,
  ) async {
    return switch (tool.surface) {
      McpOpsExposureSurface.builtinTools => _invokeOpsBuiltinTool(
        tool,
        arguments,
        context,
      ),
      McpOpsExposureSurface.memory => _invokeOpsMemoryTool(tool),
      McpOpsExposureSurface.skills => _invokeOpsSkillTool(tool),
      McpOpsExposureSurface.instructions => _invokeOpsInstructionTool(tool),
      McpOpsExposureSurface.knowledgeBase => _invokeOpsKnowledgeTool(tool),
      McpOpsExposureSurface.mcpServers => _invokeOpsMcpBridgeTool(
        tool,
        arguments,
        context,
      ),
    };
  }

  Future<McpOpsToolInvocationResult> _invokeOpsBuiltinTool(
    McpOpsToolDefinition tool,
    Map<String, Object?> arguments,
    McpOpsToolInvocationContext context,
  ) async {
    final runtime = _opsBindings?.toolRuntimeServiceProvider?.call();
    if (runtime == null) {
      return const McpOpsToolInvocationResult(
        text: 'AI tool runtime is not available; builtin tools cannot run.',
        isError: true,
      );
    }
    final kind = _builtinKindFromItemId(tool.itemId);
    final base = kind == null
        ? null
        : AiToolRuntimeService.builtinToolDefault(kind);
    if (kind == null || base == null) {
      return const McpOpsToolInvocationResult(
        text: 'Builtin tool is not available.',
        isError: true,
      );
    }
    // 依赖大模型的工具在无可用模型时优雅报错，不进入执行。
    final resolvedModel = _opsBindings?.opsModelProvider?.call();
    if (_opsModelDependentBuiltinKinds.contains(kind) &&
        resolvedModel == null) {
      return McpOpsToolInvocationResult(
        text:
            'Tool "${base.name}" requires a configured AI model. '
            'Add a model in OpenHand settings before calling it.',
        isError: true,
      );
    }
    final catalog = AiResolvedToolCatalog(
      definitions: <AiToolDefinition>[base.definition],
      toolsByName: <String, AiResolvedTool>{base.name: base},
    );
    try {
      final result = await runtime.execute(
        sessionId: _opsBuiltinSessionId,
        catalog: catalog,
        toolCall: AiToolCall(
          id: context.invocationId,
          name: base.name,
          arguments: jsonEncode(arguments),
        ),
        model: resolvedModel ?? _opsPlaceholderModel,
        previouslyReadFiles: const <String>{},
        denyCommandRules: const [],
        requireWriteCommandConfirmation: false,
        confirmWriteCommand: null,
        cancelSignal: context.cancelSignal,
      );
      final succeeded = result.status == BashToolExecutionStatus.success;
      return McpOpsToolInvocationResult(
        text: result.toToolOutput(),
        isError: !succeeded,
        metadata: <String, Object?>{
          'kind': kind.name,
          'status': result.status.storageValue,
        },
      );
    } catch (error, stack) {
      silentLog('mcp', 'invoke ops builtin tool', error, stack);
      return McpOpsToolInvocationResult(
        text: 'Builtin tool execution failed: $error',
        isError: true,
      );
    }
  }

  Future<McpOpsToolInvocationResult> _invokeOpsMemoryTool(
    McpOpsToolDefinition tool,
  ) async {
    final entries =
        _opsBindings?.memoryControllerProvider()?.entries ??
        const <UserMemoryEntry>[];
    for (final entry in entries) {
      if (entry.id == tool.itemId) {
        return McpOpsToolInvocationResult(
          text: prettyPrintJson(entry.toJson()),
          metadata: <String, Object?>{'memory_id': entry.id},
        );
      }
    }
    return const McpOpsToolInvocationResult(
      text: 'Memory entry is not available.',
      isError: true,
    );
  }

  Future<McpOpsToolInvocationResult> _invokeOpsSkillTool(
    McpOpsToolDefinition tool,
  ) async {
    final skills =
        _opsBindings?.skillsControllerProvider()?.skills ??
        const <LocalSkill>[];
    for (final skill in skills) {
      if (skill.name == tool.itemId) {
        return McpOpsToolInvocationResult(
          text: prettyPrintJson(<String, Object?>{
            'name': skill.name,
            'description': skill.description,
            'directory': skill.displayDirectoryPath,
            'relative_directory': skill.relativeDirectoryPath,
            'default_prompt': skill.defaultPrompt,
            'manifest_path': skill.manifestPath,
          }),
          metadata: <String, Object?>{'skill': skill.name},
        );
      }
    }
    return const McpOpsToolInvocationResult(
      text: 'Skill is not available.',
      isError: true,
    );
  }

  Future<McpOpsToolInvocationResult> _invokeOpsInstructionTool(
    McpOpsToolDefinition tool,
  ) async {
    final entries =
        _opsBindings?.instructionsControllerProvider()?.entries ??
        const <UserInstructionEntry>[];
    for (final entry in entries) {
      if (entry.id == tool.itemId && entry.enabled) {
        return McpOpsToolInvocationResult(
          text: prettyPrintJson(entry.toJson()),
          metadata: <String, Object?>{'instruction_id': entry.id},
        );
      }
    }
    return const McpOpsToolInvocationResult(
      text: 'Instruction is not available.',
      isError: true,
    );
  }

  Future<McpOpsToolInvocationResult> _invokeOpsKnowledgeTool(
    McpOpsToolDefinition tool,
  ) async {
    final sources =
        _opsBindings?.knowledgeBaseControllerProvider()?.sources ??
        const <KnowledgeSource>[];
    for (final source in sources) {
      if (source.id == tool.itemId) {
        return McpOpsToolInvocationResult(
          text: prettyPrintJson(source.toRow()),
          metadata: <String, Object?>{'knowledge_source_id': source.id},
        );
      }
    }
    return const McpOpsToolInvocationResult(
      text: 'Knowledge source is not available.',
      isError: true,
    );
  }

  Future<McpOpsToolInvocationResult> _invokeOpsMcpBridgeTool(
    McpOpsToolDefinition tool,
    Map<String, Object?> arguments,
    McpOpsToolInvocationContext context,
  ) async {
    final registry = AiToolExecutionRegistry.instance;
    final registration = registry.register(
      toolCallId: context.invocationId,
      sessionId: _opsBuiltinSessionId,
      kind: AiToolExecutionKind.mcp,
      displayName: tool.name,
    );
    unawaited(
      context.cancelSignal.then<void>(
        (_) => registry.cancelRegistration(registration),
        onError: (Object _, StackTrace _) =>
            registry.cancelRegistration(registration),
      ),
    );
    final effectiveCancelSignal = registration == null
        ? context.cancelSignal
        : Future.any<void>(<Future<void>>[
            context.cancelSignal,
            registration.cancelSignal,
          ]);
    try {
      final result = await registry.runRegistered(
        registration,
        () => callTool(
          serverName: tool.itemId,
          toolName: tool.endpointId,
          arguments: arguments,
          toolCallId: context.invocationId,
          cancelSignal: effectiveCancelSignal,
        ),
      );
      return McpOpsToolInvocationResult(
        text: result.outputText,
        isError: result.isError,
        metadata: <String, Object?>{
          'server': tool.itemId,
          'tool': tool.endpointId,
        },
      );
    } finally {
      if (registration != null) registry.unregister(registration);
    }
  }

  bool _opsVisible(
    McpOpsExposureSurface surface,
    String itemId,
    String endpointId,
  ) {
    return _opsConfig.itemVisible(surface, itemId) &&
        _opsConfig.endpointVisible(surface, '$itemId:$endpointId');
  }

  bool _mcpToolMayWrite(McpTool tool) {
    final annotations = tool.annotations;
    if (boolFromValue(annotations['destructiveHint'])) return true;
    if (boolFromValue(annotations['readOnlyHint'])) return false;
    final name = tool.id.toLowerCase();
    return name.contains('write') ||
        name.contains('edit') ||
        name.contains('delete') ||
        name.contains('remove') ||
        name.contains('create') ||
        name.contains('update') ||
        name.contains('apply') ||
        name.contains('exec') ||
        name.contains('run');
  }

  bool _builtinKindMayWrite(AiBuiltinToolKind kind) {
    return _opsWriteBuiltinKinds.contains(kind);
  }

  /// itemId 为 [AiBuiltinToolKind.name]（见 _opsBuiltinToolDefinitions），
  /// 反解回枚举；未知返回 null。
  AiBuiltinToolKind? _builtinKindFromItemId(String itemId) {
    for (final kind in AiBuiltinToolKind.values) {
      if (kind.name == itemId) return kind;
    }
    return null;
  }

  String _opsToolName(String surface, String item, String endpoint) {
    return 'openhand.$surface.${_opsNameToken(item)}.${_opsNameToken(endpoint)}';
  }

  String _opsNameToken(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (normalized.isEmpty) return 'item';
    return normalized.length <= 80 ? normalized : normalized.substring(0, 80);
  }

  Map<String, Object?> _opsObjectSchema({
    Map<String, Object?> properties = const <String, Object?>{},
    List<String> required = const <String>[],
  }) {
    return <String, Object?>{
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
      'additionalProperties': false,
    };
  }

  /// 待保存的 server 是否指向 OpenHand 自身的 MCP 运维入口。命中即为自引用，
  /// 保存会被拒绝——把内置运维入口添加回 MCP 列表会造成引用循环与工具无限膨胀。
  bool isSelfReferencingServer(McpServer server) {
    return mcpOpsServerTargetsSelfEndpoint(
      server: server,
      snapshot: _opsSnapshot,
      config: _opsConfig,
    );
  }

  Future<bool> saveServer(McpServer server, {String? previousName}) async {
    final normalizedName = server.name.trim();
    if (normalizedName.isEmpty) {
      return false;
    }
    // 拒绝把 OpenHand 自身的 MCP 运维入口添加回来，杜绝引用循环 / 工具膨胀。
    // 覆盖 UI 弹窗与模板/插件等编程调用方所有入口。
    if (isSelfReferencingServer(server)) {
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
      // 禁用服务时同步禁用探测；启用服务时同步启用探测
      updatedServers[index] = updatedServers[index].copyWith(
        enabled: enabled,
        probeEnabled: enabled ? true : false,
      );
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

  /// 切换服务的探测启用状态（不影响服务本身的 enabled）。
  Future<bool> updateServerProbeEnabled(String name, bool probeEnabled) async {
    return _enqueueOperation(() async {
      final normalizedName = _normalizeServerName(name);
      final index = _servers.indexWhere((item) => item.name == normalizedName);
      if (index == -1) {
        return false;
      }
      if (_servers[index].probeEnabled == probeEnabled) {
        return true;
      }

      final updatedServers = List<McpServer>.from(_servers);
      updatedServers[index] = updatedServers[index].copyWith(
        probeEnabled: probeEnabled,
      );
      return _commitSaveLocked(
        updatedServers,
        changedServerName: updatedServers[index].name,
        shouldAutoRefreshTools: probeEnabled,
        shouldAutoCheckHealth: probeEnabled,
        resetChangedServerToolCatalog: !probeEnabled,
        resetChangedServerHealth: !probeEnabled,
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

  Future<void> refreshServerTools(
    String serverName, {
    bool requirePageActive = false,
  }) async {
    if (_isDisposed || requirePageActive && !_isPageActive) {
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

    // 对 stdio 类型服务，确保 process manager 中有运行中的进程。
    // discovery service 会通过 borrowSessionForDiscovery 复用该进程发送
    // tools/list，避免 Playwright 等单例 MCP 服务的多实例冲突。
    // 必须 await startServer 完成后再继续，否则 borrowSession 会因
    // _processes 中 entry 尚未创建而立即返回 null，回退到启动新进程。
    if (server.type == McpServerType.stdio) {
      final processInfo = McpStdioProcessManager.instance.infoFor(server.name);
      if (processInfo.isStopped) {
        await McpStdioProcessManager.instance.startServer(server);
      }
      if (_isDisposed || requirePageActive && !_isPageActive) {
        return;
      }
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
          requirePageActive && !_isPageActive ||
          _toolRefreshGenerationByServerName[normalizedServerName] !=
              nextGeneration) {
        return;
      }
      if (_isLifecycleCancelledCatalog(discoveredCatalog)) {
        _toolCatalogByServerName[normalizedServerName] = previousCatalog;
        notifyListeners();
        return;
      }
      _toolCatalogByServerName[normalizedServerName] = _resolvedRefreshCatalog(
        previousCatalog: previousCatalog,
        discoveredCatalog: discoveredCatalog,
      );
      notifyListeners();
    } catch (error) {
      if (_isDisposed ||
          requirePageActive && !_isPageActive ||
          _toolRefreshGenerationByServerName[normalizedServerName] !=
              nextGeneration) {
        return;
      }
      if (isExpectedMcpToolDiscoveryLifecycleError(error)) {
        _toolCatalogByServerName[normalizedServerName] = previousCatalog;
        notifyListeners();
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
      if (_isLifecycleCancelledHealth(resolvedHealth)) {
        _healthByServerName[normalizedServerName] = previousHealth;
        notifyListeners();
        return;
      }
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
      if (isExpectedMcpToolDiscoveryLifecycleError(error)) {
        _healthByServerName[normalizedServerName] = previousHealth;
        notifyListeners();
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
    Map<String, String>? customHeaders,
    String? toolCallId,
    Future<void>? cancelSignal,
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
      customHeaders: customHeaders,
      toolCallId: toolCallId,
      cancelSignal: cancelSignal,
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
        _runDetached(
          refreshServerTools(changedServerName, requirePageActive: true),
          'refresh changed server tools',
        );
      }
      if (_isPageActive && shouldAutoCheckHealth && changedServerName != null) {
        _runDetached(
          checkServerHealth(changedServerName),
          'check changed server health',
        );
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
    _runDetached(_runAutoToolRefreshes(force: force), 'auto refresh tools');
  }

  Future<void> _runAutoToolRefreshes({required bool force}) async {
    try {
      final targets = <McpServer>[];
      for (final server in _servers) {
        if (_isDisposed || !_isPageActive) {
          return;
        }
        if (!server.probeEnabled) {
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
        (server) => refreshServerTools(server.name, requirePageActive: true),
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
    _runDetached(_runAutoHealthChecks(force: force), 'auto health checks');
  }

  void _runDetached(Future<void> future, String where) {
    unawaited(
      future.catchError((Object error, StackTrace stack) {
        silentLog('mcp', where, error, stack);
      }),
    );
  }

  Future<void> _runAutoHealthChecks({required bool force}) async {
    try {
      final now = DateTime.now().toUtc();
      final targets = <McpServer>[];
      for (final server in _servers) {
        if (_isDisposed || !_isPageActive) {
          return;
        }
        if (!server.probeEnabled) {
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
    await forEachIndexWithConcurrencyLimit(
      itemCount: targets.length,
      maxConcurrency: _autoProbeConcurrency,
      shouldContinue: () => !_isDisposed && _isPageActive,
      delayBetweenItems: _autoProbeGap,
      task: (index) async {
        try {
          await _runWithAutoProbeSlot(() => operation(targets[index]));
        } catch (error, stack) {
          silentLog('mcp', '_runAutoProbeWorkerPool', error, stack);
        }
      },
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
    _healthCheckTimer = startSafePeriodicTimer(_healthCheckInterval, (_) {
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
    if (_isLifecycleCancelledCatalog(discoveredCatalog)) {
      return previousCatalog;
    }
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

  bool _isLifecycleCancelledCatalog(McpToolCatalog catalog) {
    return catalog.status == McpToolCatalogStatus.idle &&
        catalog.tools.isEmpty &&
        catalog.errorMessage == null &&
        catalog.warningMessage == null &&
        catalog.serverInstructions.isEmpty &&
        catalog.lastScannedAt == null;
  }

  bool _isLifecycleCancelledHealth(McpServerHealth health) {
    return health.status == McpServerHealthStatus.idle &&
        health.errorMessage == null &&
        health.lastCheckedAt == null &&
        health.latencyMs == null &&
        health.consecutiveFailures == 0 &&
        health.lastSuccessAt == null &&
        health.recentProbes.isEmpty;
  }
}

bool _mcpOpsTimestampInRange(
  DateTime value, {
  required DateTime? startUtc,
  required DateTime? endUtc,
}) {
  final utc = value.toUtc();
  final start = startUtc?.toUtc();
  final end = endUtc?.toUtc();
  if (start != null && utc.isBefore(start)) return false;
  if (end != null && utc.isAfter(end)) return false;
  return true;
}

bool _mcpOpsRuntimeSnapshotHasData(McpOpsRuntimeSnapshot snapshot) {
  return snapshot.lifecycle != McpOpsLifecycleState.stopped ||
      snapshot.boundHost != null ||
      snapshot.boundPort != null ||
      snapshot.startedAt != null ||
      snapshot.lastConnectivityAt != null ||
      snapshot.lastConnectivityMessage.trim().isNotEmpty ||
      snapshot.currentConnections > 0 ||
      snapshot.activeRequests > 0 ||
      snapshot.activeStreams > 0 ||
      snapshot.sessionCount > 0 ||
      snapshot.requestTotal > 0 ||
      snapshot.blockedTotal > 0 ||
      snapshot.failedTotal > 0 ||
      snapshot.inboundBytes > 0 ||
      snapshot.outboundBytes > 0 ||
      snapshot.avgLatencyMs > 0 ||
      snapshot.p95LatencyMs > 0 ||
      snapshot.fileMutationCount > 0 ||
      snapshot.memoryRssBytes > 0 ||
      (snapshot.errorMessage?.trim().isNotEmpty ?? false) ||
      snapshot.ipDistribution.isNotEmpty ||
      snapshot.clientDistribution.isNotEmpty ||
      snapshot.requestDistribution.isNotEmpty ||
      snapshot.protocolDistribution.isNotEmpty ||
      snapshot.trafficSeries.any(
        (sample) =>
            sample.total > 0 ||
            sample.avgLatencyMs > 0 ||
            sample.p95LatencyMs > 0,
      );
}
