import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../app/support/silent_log.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/date_time_format.dart';
import '../../shared/util/duration_bounds.dart';
import '../../shared/util/input_value_parsing.dart';
import '../../shared/util/serial_task_queue.dart';
import '../../shared/util/text_normalization.dart';
import '../../shared/util/timer_safety.dart';
import '../ai/index.dart'
    show
        AiAuthScheme,
        AiBuiltinToolConfig,
        AiBuiltinToolKind,
        AiModelConfig,
        AiProtocolType,
        AiResolvedTool,
        AiResolvedToolCatalog,
        AiToolCall,
        AiToolDefinition,
        AiToolExecutionKind,
        AiToolExecutionRegistry,
        AiToolRuntimeService,
        BashToolExecutionStatus,
        builtinToolCanonicalName;
import '../instructions/index.dart';
import '../knowledge_base/index.dart';
import '../memory/index.dart';
import '../skills/index.dart';
import 'data/mcp_server_ops_store.dart';
import 'data/mcp_store.dart';
import 'mcp_errors.dart';
import 'model/mcp_server.dart';
import 'model/mcp_server_health.dart';
import 'model/mcp_server_ops.dart';
import 'model/mcp_tool.dart';
import 'service/mcp_keyword_index.dart';
import 'service/mcp_keyword_tokenizer.dart';
import 'service/mcp_ops_endpoint.dart';
import 'service/mcp_server_ops_runtime.dart';
import 'service/mcp_stdio_process_manager.dart';
import 'service/mcp_tool_catalog_cache.dart';
import 'service/mcp_tool_discovery_service.dart';

const Set<String> _genericMcpRoutingTokens = <String>{
  '查询',
  '请求',
  '获取',
  '调用',
  '使用',
  '工具',
  '服务',
  '接口',
  '信息',
  '数据',
  'query',
  'request',
  'fetch',
  'call',
  'use',
  'service',
  'info',
  'information',
  'data',
};

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

  /// 首个可用模型，供依赖大模型的内建工具（Task/WebSearch/WebFetch）使用；
  /// 无可用模型时返回 null，调用方据此优雅报错。
  final AiModelConfig? Function()? opsModelProvider;
}

class McpController extends ChangeNotifier {
  McpController._({
    required this._store,
    required this._opsStore,
    required this._toolDiscoveryService,
    required this._keywordIndexService,
    required this._toolCatalogCacheService,
    required this._ownsToolDiscoveryService,
    required this._healthCheckInterval,
    required int autoProbeConcurrency,
    this._isLoading = false,
  }) : _autoProbeConcurrency = _normalizeAutoProbeConcurrency(
         autoProbeConcurrency,
       );

  /// 同步创建控制器但不加载服务器列表。调用 [refresh] 前保持加载状态，
  /// 用于避免 MCP 文件读取阻塞应用启动。
  factory McpController.uninitialized({
    required String initialFilePath,
    McpStore? store,
    McpToolDiscoveryService? toolDiscoveryService,
    McpKeywordIndexService? keywordIndexService,
    McpToolCatalogCacheService? toolCatalogCacheService,
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
      keywordIndexService:
          keywordIndexService ??
          McpKeywordIndexService(
            storageDir: Directory(effectiveStore.storageDirectoryPath),
          ),
      toolCatalogCacheService:
          toolCatalogCacheService ??
          McpToolCatalogCacheService(
            storageDir: Directory(effectiveStore.storageDirectoryPath),
          ),
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
    McpKeywordIndexService? keywordIndexService,
    McpToolCatalogCacheService? toolCatalogCacheService,
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
      keywordIndexService:
          keywordIndexService ??
          McpKeywordIndexService(
            storageDir: Directory(effectiveStore.storageDirectoryPath),
          ),
      toolCatalogCacheService:
          toolCatalogCacheService ??
          McpToolCatalogCacheService(
            storageDir: Directory(effectiveStore.storageDirectoryPath),
          ),
      ownsToolDiscoveryService: toolDiscoveryService == null,
      healthCheckInterval: healthCheckInterval,
      autoProbeConcurrency: autoProbeConcurrency,
    );
    await controller.ensureRuntimeReady();
    return controller;
  }

  static const Duration _pageActivationWorkDelay = Duration(milliseconds: 450);
  static const Duration _autoProbeGap = Duration(milliseconds: 80);
  static const Duration runtimeCleanupTimeout = Duration(seconds: 10);
  static const int defaultAutoProbeConcurrency = 5;
  static const int _minAutoProbeConcurrency = 1;
  static const int _maxAutoProbeConcurrency = 32;
  static const int _maxQueuedAutoProbeTasks = 128;

  final McpStore _store;
  final McpServerOpsStore _opsStore;
  final McpToolDiscoveryService _toolDiscoveryService;
  final McpKeywordIndexService _keywordIndexService;
  final McpToolCatalogCacheService _toolCatalogCacheService;
  final bool _ownsToolDiscoveryService;
  final Duration _healthCheckInterval;
  int _autoProbeConcurrency;

  bool _isLoading;
  String? _errorMessage;
  bool _hasTrustedSnapshot = false;
  List<McpServer> _servers = const <McpServer>[];
  List<McpServer> _serversView = const <McpServer>[];
  final Map<String, McpToolCatalog> _toolCatalogByServerName =
      <String, McpToolCatalog>{};
  final Map<String, int> _toolRefreshGenerationByServerName = <String, int>{};
  final Map<String, Future<void>> _activeToolRefreshes =
      <String, Future<void>>{};
  final Map<String, McpServerHealth> _healthByServerName =
      <String, McpServerHealth>{};
  final Map<String, int> _healthCheckGenerationByServerName = <String, int>{};
  final Map<String, Future<void>> _activeHealthChecks =
      <String, Future<void>>{};
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
  Future<void>? _shutdownFuture;
  bool _isPageActive = false;
  bool _autoToolRefreshInProgress = false;
  bool _autoHealthCheckInProgress = false;
  bool _listenerNotificationScheduled = false;
  bool _opsPersistenceLoaded = false;
  final OpenHandSingleFlight<void> _opsPersistenceLoadFlight =
      OpenHandSingleFlight<void>();
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

  final SerialTaskQueue _operationQueue = SerialTaskQueue();
  final OpenHandSingleFlight<void> _refreshFlight =
      OpenHandSingleFlight<void>();
  late final OpenHandRetryableAsyncCache<void> _runtimeReadyCache =
      OpenHandRetryableAsyncCache<void>(_loadRuntimeReady);
  final OpenHandSingleFlight<void> _runtimeCatalogWarmupFlight =
      OpenHandSingleFlight<void>();
  late final OpenHandDebouncer _pageActivationWorkDebouncer = OpenHandDebouncer(
    delay: _pageActivationWorkDelay,
  );
  late final OpenHandDebouncer _opsPersistenceDebouncer = OpenHandDebouncer(
    delay: const Duration(milliseconds: 650),
    onError: (error, stack) => silentLog('mcp', '保存运维运行时数据', error, stack),
  );
  Timer? _healthCheckTimer;
  Timer? _opsSnapshotNotifyTimer;
  final ValueNotifier<int> _saveSuccessSignal = ValueNotifier<int>(0);

  /// 每次成功保存后递增，供界面触发保存反馈动画。
  ValueListenable<int> get saveSuccessSignal => _saveSuccessSignal;

  McpKeywordIndex? _keywordIndex;
  late final OpenHandRetryableAsyncCache<void> _keywordIndexLoadCache =
      OpenHandRetryableAsyncCache<void>(_loadKeywordIndex);
  late final OpenHandRetryableAsyncCache<void> _toolCatalogCacheLoadCache =
      OpenHandRetryableAsyncCache<void>(_loadToolCatalogCache);
  Map<String, McpCachedToolCatalog> _cachedToolCatalogs =
      const <String, McpCachedToolCatalog>{};
  int _keywordIndexRevision = 0;

  /// 当前最近一次构建（或落盘加载）的关键词倒排索引。从未构建则为 null。
  McpKeywordIndex? get keywordIndex => _keywordIndex;

  /// 是否正在构建（用于按钮 disable / 防抖）。
  bool get isBuildingKeywordIndex => _keywordIndexService.isBuilding;

  /// 启动期惰性加载落盘索引；幂等。
  Future<void> ensureKeywordIndexLoaded() => _keywordIndexLoadCache.load();

  Future<void> _loadKeywordIndex() async {
    final revision = _keywordIndexRevision;
    final loaded = await _keywordIndexService.loadFromDisk();
    if (_isDisposed || revision != _keywordIndexRevision || loaded == null) {
      return;
    }
    _keywordIndex = loaded;
    notifyListeners();
  }

  /// 等待服务器配置、关键词索引和上次完整工具目录完成本地恢复。
  Future<void> ensureRuntimeReady() => _runtimeReadyCache.load();

  Future<void> _loadRuntimeReady() async {
    await Future.wait<void>(<Future<void>>[
      refresh(),
      ensureKeywordIndexLoaded(),
      _ensureToolCatalogCacheLoaded(),
    ]);
    if (!_isDisposed) _restoreCachedToolCatalogs();
  }

  /// 首次对话仅扫描本地缓存缺失的服务，并限制前台等待时间。
  Future<void> ensureRuntimeToolCatalogs({
    Duration maxWait = const Duration(seconds: 9),
    Iterable<String>? serverNames,
  }) async {
    await ensureRuntimeReady();
    if (_isDisposed || !_hasTrustedSnapshot) return;
    final targets = serverNames
        ?.map(_normalizeServerName)
        .where((name) => name.isNotEmpty)
        .toSet();
    final warmup = targets == null
        ? _runtimeCatalogWarmupFlight.run(_warmRuntimeToolCatalogs)
        : _warmRuntimeToolCatalogs(serverNames: targets);
    try {
      await warmup.timeout(maxWait);
    } on TimeoutException {
      // 扫描继续在后台执行，本轮使用已恢复完成的目录。
    }
  }

  Future<void> _warmRuntimeToolCatalogs({Set<String>? serverNames}) async {
    final targets = runtimeServers
        .where(
          (server) =>
              server.enabled &&
              (serverNames == null || serverNames.contains(server.name)) &&
              (toolCatalogFor(server.name).status !=
                      McpToolCatalogStatus.ready ||
                  !toolCatalogFor(server.name).isComplete),
        )
        .toList(growable: false);
    await forEachIndexWithConcurrencyLimit(
      itemCount: targets.length,
      maxConcurrency: _autoProbeConcurrency,
      shouldContinue: () => !_isDisposed && _hasTrustedSnapshot,
      task: (index) async {
        try {
          await refreshServerTools(
            targets[index].name,
            clearCachedTools: false,
          );
        } catch (error, stack) {
          silentLog('mcp', '预热工具目录', error, stack);
        }
      },
    );
  }

  Future<void> _ensureToolCatalogCacheLoaded() =>
      _toolCatalogCacheLoadCache.load();

  Future<void> _loadToolCatalogCache() async {
    final loaded = await _toolCatalogCacheService.load();
    if (_isDisposed) return;
    _cachedToolCatalogs = loaded;
    if (_restoreCachedToolCatalogs()) notifyListeners();
  }

  /// 触发一次构建。`onProgress` 直接转发自服务层；构建完毕会更新
  /// [keywordIndex] 并 notifyListeners。返回构建结果（含跳过统计）。
  /// 调用方负责防抖 / disable 按钮 —— 服务层也做了单飞兜底。
  Future<McpKeywordIndexBuildResult> buildKeywordIndex({
    void Function(McpKeywordIndexProgress)? onProgress,
  }) async {
    if (!_hasTrustedSnapshot) {
      throw StateError('MCP 配置不可用。');
    }
    final revision = _keywordIndexRevision;
    final snapshot = List<McpServer>.unmodifiable(runtimeServers);
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
      baseIndex: _keywordIndex,
    );
    if (!_isDisposed && revision == _keywordIndexRevision) {
      _keywordIndex = result.index;
      notifyListeners();
    } else if (!_isDisposed) {
      // 构建期间的单服务刷新可能已写入更新索引。读取串行持久化队列的
      // 最新快照，避免构建结果被修订守卫丢弃后内存索引仍为空。
      for (var attempt = 0; attempt < 2; attempt++) {
        final recoveryRevision = _keywordIndexRevision;
        final recovered = await _keywordIndexService.loadFromDisk();
        if (_isDisposed) break;
        if (recoveryRevision == _keywordIndexRevision && recovered != null) {
          _keywordIndex = recovered;
          notifyListeners();
          break;
        }
      }
    }
    return result;
  }

  void _replaceKeywordIndexServerTools(String serverName, List<McpTool> tools) {
    _keywordIndexRevision += 1;
    final current = _keywordIndex;
    if (current != null) {
      _keywordIndex = current.replaceServerTools(
        serverName: serverName,
        tools: tools,
      );
    }
    _runDetached(
      _keywordIndexService.replacePersistedServerTools(
        serverName: serverName,
        tools: tools,
      ),
      '更新 MCP 关键词索引',
    );
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<McpServer> get servers => _serversView;
  List<McpServer> get runtimeServers =>
      _hasTrustedSnapshot ? _serversView : const <McpServer>[];
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

  String serverSearchText(McpServer server) {
    final buffer = StringBuffer()
      ..write(server.name)
      ..write(' ')
      ..write(server.summary)
      ..write(' ')
      ..write(server.type.transportValue);
    for (final tool in toolCatalogFor(server.name).tools) {
      buffer
        ..write(' ')
        ..write(tool.id)
        ..write(' ')
        ..write(tool.name)
        ..write(' ')
        ..write(tool.description);
    }
    return buffer.toString();
  }

  /// 请求语义命中且工具较少时直接暴露该 MCP，避免简单能力被全量懒加载隐藏。
  List<String> matchedSmallRuntimeServerNames({
    required String query,
    required Iterable<String> serverNames,
    int maxTools = 8,
  }) {
    final queryTokens = <String>{...tokenizeForMcpKeywordIndex(query)}
      ..removeAll(_genericMcpRoutingTokens);
    if (queryTokens.isEmpty) return const <String>[];
    final allowedNames = serverNames
        .map(_normalizeServerName)
        .where((name) => name.isNotEmpty)
        .toSet();
    final matched = <String>[];
    for (final server in runtimeServers) {
      if (!server.enabled || !allowedNames.contains(server.name)) continue;
      final catalog = toolCatalogFor(server.name);
      if (catalog.status != McpToolCatalogStatus.ready ||
          !catalog.isComplete ||
          catalog.tools.isEmpty ||
          catalog.tools.length > maxTools) {
        continue;
      }
      final capabilityText = StringBuffer(server.name);
      for (final tool in catalog.tools) {
        capabilityText
          ..write(' ')
          ..write(tool.name)
          ..write(' ')
          ..write(tool.description);
      }
      final capabilityTokens = <String>{
        ...tokenizeForMcpKeywordIndex(capabilityText.toString()),
      }..removeAll(_genericMcpRoutingTokens);
      if (capabilityTokens.any(queryTokens.contains)) matched.add(server.name);
    }
    return matched;
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
    if (_isDisposed || !_hasTrustedSnapshot || !_isPageActive) {
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
      if (_listenerNotificationScheduled) return;
      _listenerNotificationScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _listenerNotificationScheduled = false;
        if (_isDisposed) return;
        super.notifyListeners();
      });
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    final pendingTasks = <Future<void>>[
      _operationQueue.idle,
      _refreshFlight.idle,
      _runtimeCatalogWarmupFlight.idle,
      _opsPersistenceLoadFlight.idle,
      ..._activeToolRefreshes.values,
      ..._activeHealthChecks.values,
    ];
    for (final completer in _opsApprovalCompleters.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    _opsApprovalCompleters.clear();
    _opsApprovalRequests.clear();
    final opsRuntime = _opsRuntime;
    _opsRuntime = null;
    _pageActivationWorkDebouncer.dispose();
    _opsPersistenceDebouncer.dispose();
    _healthCheckTimer?.cancel();
    _opsSnapshotNotifyTimer?.cancel();
    _activeToolRefreshes.clear();
    _activeHealthChecks.clear();
    _cancelQueuedAutoProbeSlots();
    if (_ownsToolDiscoveryService) {
      try {
        _toolDiscoveryService.dispose();
      } catch (error, stack) {
        silentLog('mcp', '释放工具发现服务', error, stack);
      }
    }
    _shutdownFuture = _shutdownRuntimeResources(
      opsRuntime,
      pendingTasks: pendingTasks,
    );
    _saveSuccessSignal.dispose();
    super.dispose();
  }

  Future<void> shutdown() {
    if (!_isDisposed) dispose();
    return _shutdownFuture ?? Future<void>.value();
  }

  Future<void> _shutdownRuntimeResources(
    McpServerOpsRuntime? opsRuntime, {
    required List<Future<void>> pendingTasks,
  }) async {
    await Future.wait<void>(<Future<void>>[
      if (opsRuntime != null)
        _runShutdownStep('停止 MCP 运维服务', opsRuntime.shutdown),
      _runShutdownStep(
        '停止 STDIO MCP 进程',
        () => McpStdioProcessManager.instance.stopAll(immediate: true),
      ),
    ]);
    await _runShutdownStep(
      '等待 MCP 控制器任务',
      () => Future.wait<void>(pendingTasks),
    );
    await _runShutdownStep('保存 MCP 运维数据', _persistOpsRuntimeData);
    await Future.wait<void>(<Future<void>>[
      _runShutdownStep('排空 MCP 运维存储', _opsStore.flush),
      _runShutdownStep('排空 MCP 关键词索引', _keywordIndexService.flush),
      _runShutdownStep('排空 MCP 工具目录缓存', _toolCatalogCacheService.flush),
    ]);
  }

  Future<void> _runShutdownStep(
    String action,
    FutureOr<void> Function() operation,
  ) async {
    await runAsyncCleanupBounded(
      operation,
      timeout: runtimeCleanupTimeout,
      onError: (error, stack) => silentLog('mcp', action, error, stack),
    );
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
      _autoRefreshEnabledServerTools(force: true);
      _autoCheckEnabledServerHealth(force: true);
    });
  }

  Future<void> refresh() {
    return _refreshFlight.run(_refresh);
  }

  Future<void> _refresh() async {
    await _enqueueOperation(_loadServersLocked);
    if (_hasTrustedSnapshot && _isPageActive) {
      _autoRefreshEnabledServerTools(force: true);
      _autoCheckEnabledServerHealth(force: true);
    }
    _reconcileHealthCheckTimer();
    if (_opsConfig.autoStart && !_isDisposed) {
      _runDetached(startMcpOpsServer(), '启动 MCP 运维服务');
    }
  }

  Future<bool> _loadServersLocked() async {
    _isLoading = true;
    _hasTrustedSnapshot = false;
    _errorMessage = null;
    _persistenceIssue = null;
    _invalidateToolRefreshGenerations();
    _invalidateHealthCheckGenerations();
    _reconcileHealthCheckTimer();
    notifyListeners();
    try {
      final loadResult = await _store.load();
      await _ensureOpsPersistenceLoaded(force: true);
      if (!loadResult.canPersist) {
        _persistenceIssue = loadResult.issue;
        _errorMessage = loadResult.issue?.detail ?? 'MCP 配置内容无效。';
        return false;
      }
      final previousServers = List<McpServer>.from(_servers);
      await _reconcileStdioProcesses(previousServers, loadResult.servers);
      _setServers(loadResult.servers);
      _syncToolCatalogsWithServers(_servers);
      _restoreCachedToolCatalogs();
      _syncHealthStatusesWithServers(_servers);
      _hasTrustedSnapshot = true;
      return true;
    } catch (error, stack) {
      silentLog('mcp', '加载 MCP 配置', error, stack);
      final message = mcpFailureMessage(error, fallback: 'MCP 配置加载失败，请稍后重试。');
      _hasTrustedSnapshot = false;
      _errorMessage = message;
      _persistenceIssue = McpPersistenceIssue(
        kind: McpPersistenceIssueKind.loadFailed,
        filePath: _store.serversFilePath,
        detail: message,
      );
      return false;
    } finally {
      _isLoading = false;
      _reconcileHealthCheckTimer();
      notifyListeners();
    }
  }

  void attachOpsRuntimeBindings(McpOpsRuntimeBindings bindings) {
    _opsBindings = bindings;
    _ensureOpsRuntime();
    if (_opsConfig.autoStart && !_isDisposed) {
      _runDetached(startMcpOpsServer(), '绑定后启动 MCP 运维服务');
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
      silentLog('mcp', '保存运维配置', error, stack);
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
      silentLog('mcp', '启动运维服务', error, stack);
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
      silentLog('mcp', '停止运维服务', error, stack);
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
      silentLog('mcp', '重启运维服务', error, stack);
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
      silentLog('mcp', '测试运维连通性', error, stack);
      return McpOpsConnectivityResult(
        ok: false,
        message: mcpFailureMessage(error, fallback: 'MCP 运维连通性测试失败，请稍后重试。'),
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
    return _opsPersistenceLoadFlight.run(_loadOpsPersistenceLocked);
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
      onError: (error, stack) => silentLog('mcp', '通知运维快照更新', error, stack),
    );
  }

  Future<bool> _handleOpsApprovalRequest(
    McpOpsApprovalRequest request,
    Future<void> cancelSignal,
  ) async {
    final completer = Completer<bool>();
    _opsApprovalCompleters[request.id] = completer;
    _opsApprovalRequests.insert(0, request);
    _opsApprovalRequestsView = List<McpOpsApprovalRequest>.unmodifiable(
      _opsApprovalRequests,
    );
    notifyListeners();
    final timeout = request.expiresAt.difference(DateTime.now().toUtc());
    try {
      return await awaitWithCancelSignal<bool>(
            completer.future.timeout(
              nonNegativeDuration(timeout),
              onTimeout: () => false,
            ),
            cancelSignal: cancelSignal,
          ) ??
          false;
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
              return !isDateTimeInUtcRange(
                sample.minute,
                startUtc: startUtc,
                endUtc: endUtc,
              );
            })
            .toList(growable: false),
      );
    }
    _opsAuditEntries.removeWhere(
      (entry) =>
          clearsAll ||
          isDateTimeInUtcRange(
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
      final canonicalName = builtinToolCanonicalName(config.kind);
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
    if (!_hasTrustedSnapshot || !_opsConfig.surfaceEnabled(surface)) {
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
    final effectiveArguments = _opsBuiltinArguments(
      kind,
      arguments,
      context.workspaceRoot,
    );
    try {
      final result = await runtime.execute(
        sessionId: _opsBuiltinSessionId,
        catalog: catalog,
        toolCall: AiToolCall(
          id: context.invocationId,
          name: base.name,
          arguments: jsonEncode(effectiveArguments),
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
      silentLog('mcp', '调用运维内置工具', error, stack);
      return McpOpsToolInvocationResult(
        text: mcpFailureMessage(error, fallback: '内置工具执行失败，请稍后重试。'),
        isError: true,
      );
    }
  }

  Map<String, Object?> _opsBuiltinArguments(
    AiBuiltinToolKind kind,
    Map<String, Object?> arguments,
    String workspaceRoot,
  ) {
    final root = workspaceRoot.trim();
    if (root.isEmpty) return arguments;
    final hasPath = stringFromValue(arguments['path']).trim().isNotEmpty;
    final hasWorkingDirectory = <String>[
      'working_directory',
      'cwd',
    ].any((key) => stringFromValue(arguments[key]).trim().isNotEmpty);

    switch (kind) {
      case AiBuiltinToolKind.glob ||
          AiBuiltinToolKind.grep ||
          AiBuiltinToolKind.ls:
        return hasPath
            ? arguments
            : <String, Object?>{...arguments, 'path': root};
      case AiBuiltinToolKind.codebaseSearch:
        final targetDirectories = stringListFromValueOrJsonText(
          arguments['target_directories'],
        );
        return hasPath || targetDirectories.isNotEmpty
            ? arguments
            : <String, Object?>{...arguments, 'path': root};
      case AiBuiltinToolKind.bash ||
          AiBuiltinToolKind.bashBackground ||
          AiBuiltinToolKind.git ||
          AiBuiltinToolKind.readLints ||
          AiBuiltinToolKind.machineTerminalControl:
        return hasWorkingDirectory
            ? arguments
            : <String, Object?>{...arguments, 'working_directory': root};
      default:
        return arguments;
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
    final effectiveCancelSignal = combineCancelSignals(<Future<void>?>[
      context.cancelSignal,
      registration?.cancelSignal,
    ])!;
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
    final normalized = collapseRepeatedUnderscores(
      value.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9_]+'), '_'),
    ).replaceAll(RegExp(r'^_|_$'), '');
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
    final normalizedServer = server.copyWith(
      name: normalizedName,
      visibleTemplateIds: server.visibleTemplateIds == null
          ? null
          : Set<String>.unmodifiable(server.visibleTemplateIds!),
    );
    // 拒绝把 OpenHand 自身的 MCP 运维入口添加回来，杜绝引用循环 / 工具膨胀。
    // 覆盖 UI 弹窗与模板/插件等编程调用方所有入口。
    if (isSelfReferencingServer(normalizedServer)) {
      return false;
    }
    return _enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return false;
      final updatedServers = List<McpServer>.from(_servers);
      final normalizedPreviousName = previousName?.trim();
      final previousServer = normalizedPreviousName == null
          ? null
          : updatedServers
                .where((item) => item.name == normalizedPreviousName)
                .firstOrNull;
      if (normalizedPreviousName != null && normalizedPreviousName.isNotEmpty) {
        updatedServers.removeWhere(
          (item) => item.name == normalizedPreviousName,
        );
      }
      final duplicateExists = updatedServers.any(
        (item) => item.name.toLowerCase() == normalizedName.toLowerCase(),
      );
      if (duplicateExists) {
        return false;
      }
      if (updatedServers.length >= kMcpMaxServerCount) return false;
      updatedServers.add(normalizedServer);
      updatedServers.sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
      final runtimeChanged =
          previousServer == null ||
          previousServer.name != normalizedName ||
          previousServer.enabled != normalizedServer.enabled ||
          previousServer.probeEnabled != normalizedServer.probeEnabled ||
          mcpServerConnectionSignature(previousServer) !=
              mcpServerConnectionSignature(normalizedServer);
      return _commitSaveLocked(
        updatedServers,
        previousServerName: normalizedPreviousName,
        changedServerName: normalizedName,
        shouldAutoRefreshTools: normalizedServer.enabled && runtimeChanged,
        shouldAutoCheckHealth: normalizedServer.enabled && runtimeChanged,
        resetChangedServerToolCatalog: runtimeChanged,
        resetChangedServerHealth: runtimeChanged,
        invalidateRuntimeTasks: runtimeChanged,
      );
    });
  }

  Future<bool> deleteServer(McpServer server) async {
    return _enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return false;
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
      if (!await _ensureTrustedSnapshotLocked()) return false;
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
        probeEnabled: enabled,
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
      if (!await _ensureTrustedSnapshotLocked()) return false;
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
    if (_serverByName(normalizedServerName) == null) return;
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

  /// 同一服务仅保留一个刷新任务，避免并发刷新互相覆盖为永久加载状态。
  Future<void> refreshServerTools(
    String serverName, {
    bool requirePageActive = false,
    bool clearCachedTools = true,
  }) {
    if (_isDisposed || requirePageActive && !_isPageActive) {
      return Future<void>.value();
    }
    final normalizedServerName = _normalizeServerName(serverName);
    if (normalizedServerName.isEmpty) {
      return Future<void>.value();
    }
    final activeRefresh = _activeToolRefreshes[normalizedServerName];
    if (activeRefresh != null) return activeRefresh;

    late final Future<void> refresh;
    refresh =
        Future<void>.microtask(
          () => _performServerToolRefresh(
            normalizedServerName,
            requirePageActive: requirePageActive,
            clearCachedTools: clearCachedTools,
          ),
        ).whenComplete(() {
          if (identical(_activeToolRefreshes[normalizedServerName], refresh)) {
            _activeToolRefreshes.remove(normalizedServerName);
          }
        });
    _activeToolRefreshes[normalizedServerName] = refresh;
    return refresh;
  }

  /// 刷新期间保留当前展示快照；自动刷新失败时继续复用完整目录。
  Future<void> _performServerToolRefresh(
    String normalizedServerName, {
    required bool requirePageActive,
    required bool clearCachedTools,
  }) async {
    if (_isDisposed || requirePageActive && !_isPageActive) return;
    final server = _serverByName(normalizedServerName);
    if (server == null) {
      return;
    }
    final connectionSignature = mcpServerConnectionSignature(server);

    final nextGeneration =
        (_toolRefreshGenerationByServerName[normalizedServerName] ?? 0) + 1;
    _toolRefreshGenerationByServerName[normalizedServerName] = nextGeneration;
    final currentCatalog = toolCatalogFor(normalizedServerName);
    final cachedCatalog = _cachedToolCatalogs[normalizedServerName];
    final previousCatalog = currentCatalog.isLoading
        ? cachedCatalog != null &&
                  cachedCatalog.connectionSignature == connectionSignature
              ? cachedCatalog.catalog
              : const McpToolCatalog()
        : currentCatalog;
    final preserveVisibleState =
        !clearCachedTools &&
        previousCatalog.status != McpToolCatalogStatus.idle;
    final preserveUsableCatalog =
        !clearCachedTools &&
        previousCatalog.status == McpToolCatalogStatus.ready &&
        previousCatalog.isComplete;
    if (!preserveVisibleState) {
      _toolCatalogByServerName[normalizedServerName] = previousCatalog.copyWith(
        status: McpToolCatalogStatus.loading,
        clearErrorMessage: true,
        clearWarningMessage: true,
      );
      notifyListeners();
    }

    try {
      // 对 stdio 类型服务，确保 process manager 中有运行中的进程。
      // discovery service 会通过 borrowSessionForDiscovery 复用该进程发送
      // tools/list，避免 Playwright 等单例 MCP 服务的多实例冲突。
      // 必须 await startServer 完成后再继续，否则 borrowSession 会因
      // _processes 中 entry 尚未创建而立即返回 null，回退到启动新进程。
      if (server.type == McpServerType.stdio) {
        final processInfo = McpStdioProcessManager.instance.infoFor(
          server.name,
        );
        if (processInfo.isStopped) {
          await McpStdioProcessManager.instance.startServer(server);
        }
        if (_isDisposed || requirePageActive && !_isPageActive) {
          return;
        }
        final current = _serverByName(normalizedServerName);
        if (current == null || !_sameServerConnection(server, current)) return;
      }
      final discoveredCatalog = await _toolDiscoveryService.discoverTools(
        server,
      );
      if (_isDisposed ||
          requirePageActive && !_isPageActive ||
          _toolRefreshGenerationByServerName[normalizedServerName] !=
              nextGeneration ||
          !_sameServerConnection(server, _serverByName(normalizedServerName))) {
        return;
      }
      if (_isLifecycleCancelledCatalog(discoveredCatalog)) {
        _toolCatalogByServerName[normalizedServerName] = previousCatalog;
        notifyListeners();
        return;
      }
      if (discoveredCatalog.status != McpToolCatalogStatus.ready) {
        _toolCatalogByServerName[normalizedServerName] = preserveUsableCatalog
            ? previousCatalog.copyWith(
                warningMessage:
                    discoveredCatalog.errorMessage ??
                    discoveredCatalog.warningMessage,
                lastScannedAt: discoveredCatalog.lastScannedAt,
              )
            : discoveredCatalog;
        notifyListeners();
        return;
      }
      if (!discoveredCatalog.isComplete &&
          previousCatalog.status == McpToolCatalogStatus.ready &&
          previousCatalog.isComplete) {
        _toolCatalogByServerName[normalizedServerName] = previousCatalog
            .copyWith(
              warningMessage: discoveredCatalog.warningMessage,
              lastScannedAt: discoveredCatalog.lastScannedAt,
            );
        notifyListeners();
        return;
      }
      _toolCatalogByServerName[normalizedServerName] = discoveredCatalog;
      if (discoveredCatalog.isComplete) {
        if (!_sameKeywordIndexToolData(
          previousCatalog.tools,
          discoveredCatalog.tools,
        )) {
          _replaceKeywordIndexServerTools(
            normalizedServerName,
            discoveredCatalog.tools,
          );
        }
      }
      notifyListeners();
      if (discoveredCatalog.isComplete) {
        try {
          final cachedCatalog = _cachedToolCatalogs[normalizedServerName];
          final catalogChanged =
              cachedCatalog == null ||
              cachedCatalog.connectionSignature != connectionSignature ||
              mcpToolCatalogContentSignature(cachedCatalog.catalog) !=
                  mcpToolCatalogContentSignature(discoveredCatalog);
          if (catalogChanged) {
            await _toolCatalogCacheService.replace(
              server: server,
              catalog: discoveredCatalog,
            );
          }
          if (_isDisposed ||
              _toolRefreshGenerationByServerName[normalizedServerName] !=
                  nextGeneration ||
              !_sameServerConnection(
                server,
                _serverByName(normalizedServerName),
              )) {
            return;
          }
          _cachedToolCatalogs = <String, McpCachedToolCatalog>{
            ..._cachedToolCatalogs,
            normalizedServerName: McpCachedToolCatalog(
              connectionSignature: connectionSignature,
              catalog: discoveredCatalog,
            ),
          };
        } catch (error, stack) {
          silentLog('mcp', '保存工具目录缓存', error, stack);
        }
      }
    } catch (error, stack) {
      if (_isDisposed ||
          requirePageActive && !_isPageActive ||
          _toolRefreshGenerationByServerName[normalizedServerName] !=
              nextGeneration ||
          !_sameServerConnection(server, _serverByName(normalizedServerName))) {
        return;
      }
      if (isExpectedMcpToolDiscoveryLifecycleError(error)) {
        _toolCatalogByServerName[normalizedServerName] = previousCatalog;
        notifyListeners();
        return;
      }
      silentLog('mcp', '刷新 MCP 工具目录', error, stack);
      final message = mcpFailureMessage(error, fallback: 'MCP 工具目录刷新失败，请稍后重试。');
      _toolCatalogByServerName[normalizedServerName] = McpToolCatalog(
        status: McpToolCatalogStatus.failed,
        errorMessage: message,
        lastScannedAt: DateTime.now().toUtc(),
      );
      if (preserveUsableCatalog) {
        _toolCatalogByServerName[normalizedServerName] = previousCatalog
            .copyWith(
              warningMessage: message,
              lastScannedAt: DateTime.now().toUtc(),
            );
      }
      notifyListeners();
    }
  }

  /// 同一服务只保留一次健康探测，避免手动操作与自动探测重复占用连接。
  Future<void> checkServerHealth(
    String serverName, {
    bool preserveCurrentStatus = false,
  }) {
    if (_isDisposed || !_isPageActive) {
      return Future<void>.value();
    }
    final normalizedServerName = _normalizeServerName(serverName);
    if (normalizedServerName.isEmpty) {
      return Future<void>.value();
    }
    final activeCheck = _activeHealthChecks[normalizedServerName];
    if (activeCheck != null) return activeCheck;

    late final Future<void> check;
    check =
        Future<void>.microtask(
          () => _performServerHealthCheck(
            normalizedServerName,
            preserveCurrentStatus: preserveCurrentStatus,
          ),
        ).whenComplete(() {
          if (identical(_activeHealthChecks[normalizedServerName], check)) {
            _activeHealthChecks.remove(normalizedServerName);
          }
        });
    _activeHealthChecks[normalizedServerName] = check;
    return check;
  }

  Future<void> _performServerHealthCheck(
    String normalizedServerName, {
    required bool preserveCurrentStatus,
  }) async {
    if (_isDisposed || !_isPageActive) return;
    final server = _serverByName(normalizedServerName);
    if (server == null) {
      return;
    }
    final nextGeneration =
        (_healthCheckGenerationByServerName[normalizedServerName] ?? 0) + 1;
    _healthCheckGenerationByServerName[normalizedServerName] = nextGeneration;
    final previousHealth = healthStatusFor(normalizedServerName);
    if (!preserveCurrentStatus) {
      _healthByServerName[normalizedServerName] = previousHealth.copyWith(
        status: McpServerHealthStatus.checking,
        clearErrorMessage: true,
      );
      notifyListeners();
    }

    final stopwatch = Stopwatch()..start();
    try {
      final resolvedHealth = await _toolDiscoveryService.checkHealth(server);
      stopwatch.stop();
      if (_isDisposed ||
          !_isPageActive ||
          _healthCheckGenerationByServerName[normalizedServerName] !=
              nextGeneration ||
          !_sameServerConnection(server, _serverByName(normalizedServerName))) {
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
    } catch (error, stack) {
      stopwatch.stop();
      if (_isDisposed ||
          !_isPageActive ||
          _healthCheckGenerationByServerName[normalizedServerName] !=
              nextGeneration ||
          !_sameServerConnection(server, _serverByName(normalizedServerName))) {
        return;
      }
      if (isExpectedMcpToolDiscoveryLifecycleError(error)) {
        _healthByServerName[normalizedServerName] = previousHealth;
        notifyListeners();
        return;
      }
      silentLog('mcp', '检查 MCP 服务健康状态', error, stack);
      final message = mcpFailureMessage(error, fallback: 'MCP 服务健康检查失败，请稍后重试。');
      final completedAt = DateTime.now().toUtc();
      final probeRecord = McpHealthProbeRecord(
        status: McpServerHealthStatus.unhealthy,
        timestamp: completedAt,
        errorMessage: message,
      );
      final mergedRecent = _appendProbeRecord(
        previousHealth.recentProbes,
        probeRecord,
      );
      _healthByServerName[normalizedServerName] = McpServerHealth(
        status: McpServerHealthStatus.unhealthy,
        errorMessage: message,
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
      throw StateError('MCP 控制器已释放。');
    }
    final normalizedServerName = serverName.trim();
    final normalizedToolName = toolName.trim();
    if (normalizedServerName.isEmpty) {
      throw StateError('缺少 MCP 服务名称。');
    }
    if (normalizedToolName.isEmpty) {
      throw StateError('缺少 MCP 工具名称。');
    }
    final server = _serverByName(normalizedServerName);
    if (server == null) {
      throw StateError('MCP 服务不存在：$normalizedServerName');
    }
    if (!server.enabled) {
      throw StateError('MCP 服务已禁用：$normalizedServerName');
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
    bool invalidateRuntimeTasks = true,
  }) async {
    if (!_hasTrustedSnapshot) return false;
    final previousServers = List<McpServer>.from(_servers);
    final nextServersByName = <String, McpServer>{
      for (final server in nextServers) server.name: server,
    };
    final staleCatalogServerNames = previousServers
        .where((previous) {
          final next = nextServersByName[previous.name];
          return next == null ||
              mcpServerConnectionSignature(previous) !=
                  mcpServerConnectionSignature(next);
        })
        .map((server) => server.name)
        .toSet();
    _hasTrustedSnapshot = false;
    _errorMessage = null;
    if (invalidateRuntimeTasks) {
      _invalidateToolRefreshGenerations();
      _invalidateHealthCheckGenerations();
    }
    _reconcileHealthCheckTimer();
    notifyListeners();
    try {
      await _store.save(nextServers);
      _setServers(nextServers);
      _syncToolCatalogsWithServers(nextServers);
      _syncHealthStatusesWithServers(nextServers);
      if (previousServerName != null &&
          previousServerName != changedServerName) {
        _toolCatalogByServerName.remove(previousServerName);
        _toolRefreshGenerationByServerName.remove(previousServerName);
        unawaited(_activeToolRefreshes.remove(previousServerName));
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
      if (staleCatalogServerNames.isNotEmpty) {
        _cachedToolCatalogs = <String, McpCachedToolCatalog>{
          for (final entry in _cachedToolCatalogs.entries)
            if (!staleCatalogServerNames.contains(entry.key))
              entry.key: entry.value,
        };
        for (final serverName in staleCatalogServerNames) {
          _replaceKeywordIndexServerTools(serverName, const <McpTool>[]);
        }
      }
      _hasTrustedSnapshot = true;
      _restoreCachedToolCatalogs();
      _persistenceIssue = null;
      if (!_isDisposed) {
        _saveSuccessSignal.value = _saveSuccessSignal.value + 1;
      }
      _reconcileHealthCheckTimer();
      notifyListeners();

      // 配置落盘后立即更新页面，运行时与磁盘缓存收尾不阻塞列表变化。
      try {
        await _reconcileStdioProcesses(previousServers, nextServers);
      } catch (error, stack) {
        silentLog('mcp', '同步 STDIO 运行状态', error, stack);
      }
      if (staleCatalogServerNames.isNotEmpty) {
        try {
          await _toolCatalogCacheService.remove(staleCatalogServerNames);
        } catch (error, stack) {
          silentLog('mcp', '移除失效工具目录缓存', error, stack);
        }
      }
      if (_isPageActive &&
          shouldAutoRefreshTools &&
          changedServerName != null) {
        _runDetached(
          refreshServerTools(changedServerName, requirePageActive: true),
          '刷新变更服务器工具',
        );
      }
      if (_isPageActive && shouldAutoCheckHealth && changedServerName != null) {
        _runDetached(checkServerHealth(changedServerName), '检查变更服务器健康状态');
      }
      return true;
    } catch (error, stack) {
      silentLog('mcp', '保存 MCP 配置', error, stack);
      final issue = McpPersistenceIssue(
        kind: McpPersistenceIssueKind.saveFailed,
        filePath: _store.serversFilePath,
        detail: mcpFailureMessage(error, fallback: 'MCP 配置保存失败，请稍后重试。'),
      );
      if (await _loadServersLocked()) {
        _persistenceIssue = issue;
        notifyListeners();
      }
      return false;
    }
  }

  Future<bool> _ensureTrustedSnapshotLocked() async {
    if (_hasTrustedSnapshot) return true;
    return _loadServersLocked();
  }

  Future<void> _reconcileStdioProcesses(
    List<McpServer> previousServers,
    List<McpServer> nextServers,
  ) async {
    final nextByName = <String, McpServer>{
      for (final server in nextServers) server.name: server,
    };
    for (final previous in previousServers) {
      final next = nextByName[previous.name];
      if (next == null || next.type != McpServerType.stdio) {
        await McpStdioProcessManager.instance.removeServer(previous.name);
        continue;
      }
      if (!next.enabled ||
          previous.type != McpServerType.stdio ||
          previous.command != next.command ||
          !listEquals(previous.args, next.args) ||
          !mapEquals(previous.environment, next.environment)) {
        await McpStdioProcessManager.instance.stopServer(previous.name);
      }
    }
  }

  void _setServers(List<McpServer> servers) {
    _servers = servers;
    _serversView = List<McpServer>.unmodifiable(servers);
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    if (_isDisposed) {
      return Future<T>.error(StateError('MCP 控制器已释放。'));
    }
    return _operationQueue.enqueue(() {
      if (_isDisposed) {
        throw StateError('MCP 控制器已释放。');
      }
      return operation();
    });
  }

  void _syncToolCatalogsWithServers(List<McpServer> servers) {
    final serverNames = servers.map((item) => item.name).toSet();
    _toolCatalogByServerName.removeWhere(
      (serverName, value) => !serverNames.contains(serverName),
    );
    _toolRefreshGenerationByServerName.removeWhere(
      (serverName, value) => !serverNames.contains(serverName),
    );
    _activeToolRefreshes.removeWhere(
      (serverName, value) => !serverNames.contains(serverName),
    );
    for (final server in servers) {
      _toolCatalogByServerName.putIfAbsent(server.name, McpToolCatalog.new);
    }
  }

  bool _restoreCachedToolCatalogs() {
    var restored = false;
    for (final server in _servers) {
      final cached = _cachedToolCatalogs[server.name];
      if (cached == null ||
          cached.connectionSignature != mcpServerConnectionSignature(server)) {
        continue;
      }
      final current = toolCatalogFor(server.name);
      if (current.status != McpToolCatalogStatus.idle) continue;
      _toolCatalogByServerName[server.name] = cached.catalog;
      restored = true;
    }
    return restored;
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
    if (!_hasTrustedSnapshot || _autoToolRefreshInProgress) {
      return;
    }
    _autoToolRefreshInProgress = true;
    _notifyAutoProbeMetricsChanged();
    _runDetached(_runAutoToolRefreshes(force: force), '自动刷新工具');
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
        if (catalog.isLoading) {
          continue;
        }
        if (!force &&
            catalog.status == McpToolCatalogStatus.ready &&
            catalog.lastScannedAt != null) {
          continue;
        }
        targets.add(server);
      }
      if (targets.isNotEmpty) {
        _lastBatchProbeAt = DateTime.now().toUtc();
      }
      await _runAutoProbeWorkerPool(
        targets,
        (server) => refreshServerTools(
          server.name,
          requirePageActive: true,
          clearCachedTools: false,
        ),
      );
    } finally {
      _autoToolRefreshInProgress = false;
      _notifyAutoProbeMetricsChanged();
    }
  }

  void _autoCheckEnabledServerHealth({bool force = false}) {
    if (!_hasTrustedSnapshot || _autoHealthCheckInProgress) {
      return;
    }
    _autoHealthCheckInProgress = true;
    _notifyAutoProbeMetricsChanged();
    _runDetached(_runAutoHealthChecks(force: force), '自动健康检查');
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
      if (targets.isNotEmpty) {
        _lastBatchProbeAt = DateTime.now().toUtc();
      }
      await _runAutoProbeWorkerPool(
        targets,
        (server) => checkServerHealth(server.name, preserveCurrentStatus: true),
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
      shouldContinue: () =>
          !_isDisposed && _hasTrustedSnapshot && _isPageActive,
      delayBetweenItems: _autoProbeGap,
      task: (index) async {
        try {
          await _runWithAutoProbeSlot(() => operation(targets[index]));
        } catch (error, stack) {
          silentLog('mcp', '执行自动探测任务', error, stack);
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
      if (!_isDisposed && _hasTrustedSnapshot && _isPageActive) {
        await operation();
      }
    } finally {
      _releaseAutoProbeSlot();
    }
  }

  Future<bool> _acquireAutoProbeSlot() {
    if (_isDisposed || !_hasTrustedSnapshot || !_isPageActive) {
      return Future<bool>.value(false);
    }
    if (_activeAutoProbeSlots < _autoProbeConcurrency) {
      _activeAutoProbeSlots += 1;
      _notifyAutoProbeMetricsChanged();
      return Future<bool>.value(true);
    }
    if (_autoProbeSlotWaiters.length >= _maxQueuedAutoProbeTasks) {
      return Future<bool>.value(false);
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
        _hasTrustedSnapshot &&
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
    _activeHealthChecks.clear();
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
    _activeToolRefreshes.clear();
  }

  void _reconcileHealthCheckTimer() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    if (_isDisposed ||
        !_hasTrustedSnapshot ||
        !_isPageActive ||
        !_servers.any((server) => server.enabled)) {
      return;
    }
    _healthCheckTimer = startSafePeriodicTimer(_healthCheckInterval, (_) {
      _autoRefreshEnabledServerTools(force: true);
      _autoCheckEnabledServerHealth();
    });
  }

  McpServer? _serverByName(String serverName) {
    if (!_hasTrustedSnapshot) return null;
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

  bool _sameServerConnection(McpServer expected, McpServer? current) {
    return current != null &&
        expected.name == current.name &&
        expected.type == current.type &&
        expected.enabled == current.enabled &&
        expected.probeEnabled == current.probeEnabled &&
        expected.url == current.url &&
        expected.command == current.command &&
        listEquals(expected.args, current.args) &&
        mapEquals(expected.headers, current.headers) &&
        mapEquals(expected.environment, current.environment);
  }

  String _normalizeServerName(String serverName) {
    return serverName.trim();
  }

  bool _sameKeywordIndexToolData(List<McpTool> left, List<McpTool> right) {
    if (left.length != right.length) return false;
    String signature(McpTool tool) {
      final searchHint =
          tool.annotations['searchHint'] ??
          tool.annotations['search_hint'] ??
          tool.rawMetadata['searchHint'] ??
          tool.rawMetadata['search_hint'];
      return '${tool.id}\u0000${tool.name}\u0000${tool.description}\u0000$searchHint';
    }

    final leftSignatures = left.map(signature).toList(growable: false)..sort();
    final rightSignatures = right.map(signature).toList(growable: false)
      ..sort();
    return listEquals(leftSignatures, rightSignatures);
  }

  void _invalidateToolRefreshGeneration(String serverName) {
    _toolRefreshGenerationByServerName[serverName] =
        (_toolRefreshGenerationByServerName[serverName] ?? 0) + 1;
    _activeToolRefreshes.remove(serverName);
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
