import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/support/silent_log.dart';
import '../../app/support/system_proxy.dart';
import '../../shared/util/async_concurrency.dart';
import '../../shared/util/serial_task_queue.dart';
import '../../shared/util/timer_safety.dart';
import '../ai/index.dart';
import '../plugin_service/index.dart';
import 'data/ai_exposure_preferences_store.dart';
import 'model/ai_exposure_models.dart';
import 'model/dependency_telemetry.dart';
import 'service/ai_exposure_proxy_probe.dart';
import 'service/ai_jungler_client.dart';
import 'service/ai_jungler_runtime.dart';
import 'services_errors.dart';

const int _kAiExposureMaxLogs = 5000;
const int _kAiExposureMaxCachedHistoryJobs = 20;
const int _kAiExposureMaxCachedLogsPerJob = 2000;
const int _kAiExposureLogFetchBatchSize = 500;
const int _kProxyInspectionCheckpointSize = 512;
const int _kEventStreamReconnectLimit = 3;
const Duration _kProxyInspectionFirstRunDelay = Duration(seconds: 10);
const Duration _kProxyStatisticsSyncInterval = Duration(seconds: 5);
const Duration _kEventStreamReconnectBaseDelay = Duration(seconds: 1);
const Duration _kRuntimeOperationDrainTimeout = Duration(seconds: 3);
// 停止扫描后有界回读任务状态，兜底 SSE 缺失/延迟，避免工作台卡在"运行中"。
// 上限覆盖在飞 HTTP 探测（10s 超时）的排空窗口，且严格有界不会无限轮询。
const int _kScanTerminationSyncMaxAttempts = 40;
const Duration _kScanTerminationSyncInterval = Duration(milliseconds: 300);
// SSE 重连耗尽后转入低频轮询兜底，直至任务进入终态。
const int _kEventStreamPollFallbackMaxAttempts = 60;
const Duration _kEventStreamPollFallbackInterval = Duration(seconds: 2);
const List<String> _kScanReaderFailureMarkers = <String>[
  'Jina Reader',
  '页面读取失败',
];

const String _kServiceStoppingMessage = '扫描服务正在停止。';

typedef AiExposureProxyInspectionResultCallback =
    void Function(
      String url,
      AiExposureProxyProbeSample sample,
      int completed,
      int total,
    );

String _reportServicesFailure(
  String action,
  Object error,
  StackTrace stack, {
  String? fallback,
}) {
  return reportServicesFailure(
    'services_controller',
    action,
    error,
    stack,
    fallback: fallback,
  );
}

class ServicesController extends ChangeNotifier {
  ServicesController({
    AiJunglerRuntime? runtime,
    AiExposurePreferencesStore? preferencesStore,
    AiExposurePreferences? initialPreferences,
    AiExposureProxyProbe? proxyProbe,
    Duration proxyInspectionFirstRunDelay = _kProxyInspectionFirstRunDelay,
  }) : _runtime = runtime ?? AiJunglerRuntime(),
       _preferencesStore = preferencesStore ?? AiExposurePreferencesStore(),
       _proxyProbe = proxyProbe ?? const AiExposureProxyProbe(),
       _proxyInspectionFirstRunDelay = proxyInspectionFirstRunDelay {
    final preferences = initialPreferences ?? AiExposurePreferences.defaults();
    _enabledSources = Set<AiExposureSource>.of(preferences.enabledSources);
    _defaultConcurrency = preferences.defaultConcurrency;
    _defaultValidationMode = preferences.defaultValidationMode;
    _forumFetchMode = preferences.forumFetchMode;
    _defaultGptAssisted = preferences.defaultGptAssisted;
    _useBundledEngine = preferences.useBundledEngine;
    _externalAddress = preferences.externalAddress;
    _postgresqlEnabled = preferences.postgresqlEnabled;
    _redisEnabled = preferences.redisEnabled;
    _proxyConfiguration = preferences.proxyConfiguration;
    _runtimeLogSubscription = _runtime.logs.listen(_appendRuntimeLog);
    _runtimeExitSubscription = _runtime.exits.listen(_handleRuntimeExit);
    SystemProxyResolver.instance.revision.addListener(
      _handleSystemProxyRevision,
    );
    _scheduleProxyInspection(firstDelay: _proxyInspectionFirstRunDelay);
  }

  final AiJunglerRuntime _runtime;
  final AiExposurePreferencesStore _preferencesStore;
  final AiExposureProxyProbe _proxyProbe;
  final Duration _proxyInspectionFirstRunDelay;
  AiModelConfig? Function()? _selectedAiModelProvider;
  PluginServiceController? _pluginServiceController;
  VoidCallback? _pluginStateListener;
  String _managedDependencySignature = '';
  StreamSubscription<String>? _runtimeLogSubscription;
  StreamSubscription<int>? _runtimeExitSubscription;
  StreamSubscription<Map<String, Object?>>? _eventSubscription;
  int _eventSubscriptionGeneration = 0;
  int _eventStreamReconnectAttempts = 0;
  String? _eventStreamErrorMessage;
  AiExposureServiceLifecycle _lifecycle = AiExposureServiceLifecycle.stopped;
  AiExposureHealth? _health;
  AiExposureProgress? _progress;
  List<AiExposureHistoryEntry> _history = const <AiExposureHistoryEntry>[];
  List<AiExposureResult> _results = const <AiExposureResult>[];
  List<AiExposureScanRule> _rules = const <AiExposureScanRule>[];
  List<AiExposureQuota> _quotas = const <AiExposureQuota>[];
  AiExposureAiExtractorStatus? _aiExtractorStatus;
  AiExposureDependencyStatus? _dependencyStatus;
  Map<String, Object?> _dependencyDataOverview = const <String, Object?>{};
  final DependencyTelemetryHistory _dependencyTelemetryHistory =
      DependencyTelemetryHistory();
  String? _dependencyDataOverviewError;
  AiExposureProxyStatus? _proxyStatus;
  Map<String, bool> _sourceStatus = const <String, bool>{};
  final Map<String, List<AiExposureLogEntry>> _historyLogs =
      <String, List<AiExposureLogEntry>>{};
  late Set<AiExposureSource> _enabledSources;
  late int _defaultConcurrency;
  late AiExposureValidationMode _defaultValidationMode;
  late AiExposureForumFetchMode _forumFetchMode;
  late bool _defaultGptAssisted;
  late bool _useBundledEngine;
  late String _externalAddress;
  late bool _postgresqlEnabled;
  late bool _redisEnabled;
  AiExposureProxyConfiguration _proxyConfiguration =
      AiExposureProxyConfiguration.defaults();
  Timer? _proxyInspectionTimer;
  Timer? _proxyStatisticsTimer;
  AiExposureProxyProbeCancellation? _proxyInspectionCancellation;
  bool _proxyInspectionRunning = false;
  bool _proxyInspectionCancelRequested = false;
  int _proxyInspectionGeneration = 0;
  int _proxyInspectionScheduleGeneration = 0;

  /// 各节点已成功持久化的请求样本 record_id，按节点保存最近一个窗口
  /// （≤ [kAiExposureProxyRuntimeRequestSampleLimit] 条），容量有界。
  /// 统计同步据此只写入新样本；保存失败或应用重启后回退为整窗重发，
  /// 由历史表 record_id 唯一约束去重兜底，不会丢样本。
  final Map<String, Set<String>> _persistedRequestRecordIds =
      <String, Set<String>>{};
  final OpenHandSingleFlight<void> _proxyStatisticsSync =
      OpenHandSingleFlight<void>();
  final OpenHandSingleFlight<void> _serviceStatusRefresh =
      OpenHandSingleFlight<void>();
  final OpenHandAsyncOnce _shutdownOnce = OpenHandAsyncOnce();
  final SerialTaskQueue _proxyRuntimeUpdateQueue = SerialTaskQueue(
    maxPendingTasks: 8,
  );
  final SerialTaskQueue _managedDependencyUpdateQueue = SerialTaskQueue(
    maxPendingTasks: 8,
  );
  final LatestTaskQueue _managedDependencyListenerSyncQueue = LatestTaskQueue();
  final List<AiExposureLogEntry> _logs = <AiExposureLogEntry>[];
  String? _errorMessage;
  String? _proxyRuntimeSyncError;
  bool _busy = false;
  bool _scanBusy = false;
  bool _logRefreshBusy = false;
  bool _disposed = false;
  bool _notifierDisposed = false;
  bool _systemProxySyncRunning = false;
  bool _systemProxySyncPending = false;

  AiExposureServiceLifecycle get lifecycle => _lifecycle;
  AiExposureHealth? get health => _health;
  AiExposureProgress? get progress => _progress;
  List<AiExposureHistoryEntry> get history => _history;
  List<AiExposureResult> get results => _results;
  List<AiExposureScanRule> get rules => _rules;
  List<AiExposureQuota> get quotas => _quotas;
  AiExposureAiExtractorStatus? get aiExtractorStatus => _aiExtractorStatus;
  AiExposureDependencyStatus? get dependencyStatus => _dependencyStatus;
  Map<String, Object?> get dependencyDataOverview => _dependencyDataOverview;
  List<DependencyTelemetrySample> get dependencyTelemetryHistory =>
      _dependencyTelemetryHistory.samples;
  String? get dependencyDataOverviewError => _dependencyDataOverviewError;
  AiExposureProxyStatus? get proxyStatus => _proxyStatus;
  AiExposureProxyConfiguration get proxyConfiguration => _proxyConfiguration;
  Map<String, bool> get sourceStatus => _sourceStatus;
  int get discoverySourceCount => _sourceStatus.isNotEmpty
      ? _sourceStatus.length
      : AiExposureSource.values
            .where(
              (source) =>
                  source != AiExposureSource.manual &&
                  source != AiExposureSource.githubArtifact,
            )
            .length;
  Set<AiExposureSource> get enabledSources => Set.unmodifiable(_enabledSources);
  int get defaultConcurrency => _defaultConcurrency;
  AiExposureValidationMode get defaultValidationMode => _defaultValidationMode;
  AiExposureForumFetchMode get forumFetchMode => _forumFetchMode;
  bool get defaultGptAssisted => _defaultGptAssisted;
  bool get useBundledEngine => _useBundledEngine;
  String get externalAddress => _externalAddress;
  bool get postgresqlEnabled => _postgresqlEnabled;
  bool get redisEnabled => _redisEnabled;
  String? get selectedAiExtractorModelLabel {
    final model = _selectedAiModelProvider?.call();
    if (model == null || model.apiDialect != AiApiDialect.openAiCompat) {
      return null;
    }
    return model.modelId.trim().isEmpty ? null : model.modelId.trim();
  }

  List<AiExposureLogEntry> get logs => List.unmodifiable(_logs);
  String? get errorMessage => _errorMessage;
  String? get proxyRuntimeSyncError => _proxyRuntimeSyncError;
  bool get busy => _busy;
  bool get isRunning => _lifecycle == AiExposureServiceLifecycle.running;
  bool get hasActiveScan => _progress?.isRunning ?? false;
  bool get proxyInspectionBusy => _proxyInspectionRunning;
  bool get proxyInspectionCancelling =>
      _proxyInspectionRunning && _proxyInspectionCancelRequested;
  bool get ownsProcess => _runtime.ownsProcess;
  AiJunglerClient? get _client => _runtime.client;

  Map<String, Object?> get _systemProxyRuntimeJson =>
      SystemProxyResolver.instance.resolveRuntimeRoute().toJson();

  bool get usesProxyPool =>
      _proxyConfiguration.enabled &&
      _proxyConfiguration.activeEndpoints.isNotEmpty;

  bool get usesSystemProxyFallback => !usesProxyPool && systemProxyAvailable;

  bool get systemProxyAvailable {
    final status = _proxyStatus;
    if (_client != null && status != null) return status.systemProxyEnabled;
    return SystemProxyResolver.instance.resolveRuntimeRoute().hasProxy;
  }

  Future<int> proxyRequestHistoryCount() =>
      _preferencesStore.countProxyRequestHistory();

  Future<Map<String, String>> loadSourceCredentials() =>
      _preferencesStore.loadSourceCredentials();

  Future<List<AiExposureProxyRequestRecord>> loadProxyRequestHistory({
    required int offset,
    required int limit,
  }) => _preferencesStore.loadProxyRequestHistory(offset: offset, limit: limit);

  Future<List<AiExposureProxyRequestTrendBucket>> loadProxyRequestTrend({
    required DateTime startAt,
    required Duration interval,
  }) => _preferencesStore.loadProxyRequestTrend(
    startAt: startAt,
    interval: interval,
  );

  AiExposureProxyRoute get proxyRoute => usesProxyPool
      ? AiExposureProxyRoute.pool
      : usesSystemProxyFallback
      ? AiExposureProxyRoute.system
      : AiExposureProxyRoute.direct;

  void _handleSystemProxyRevision() {
    if (_disposed) return;
    _notify();
    if (_client == null || _lifecycle == AiExposureServiceLifecycle.stopping) {
      return;
    }
    _systemProxySyncPending = true;
    if (_systemProxySyncRunning) return;
    _systemProxySyncRunning = true;
    unawaited(_syncSystemProxyRuntime());
  }

  Future<void> _syncSystemProxyRuntime() async {
    try {
      while (_systemProxySyncPending && !_disposed) {
        _systemProxySyncPending = false;
        if (_lifecycle == AiExposureServiceLifecycle.stopping) return;
        final client = _client;
        if (client == null) return;
        try {
          final status = await _updateProxyRuntime(client);
          if (!_isCurrentClient(client)) return;
          await _mergeProxyStatistics(status);
          if (!_isCurrentClient(client)) return;
          _proxyStatus = status;
          _proxyRuntimeSyncError = null;
          _notify();
        } catch (error, stack) {
          silentLog('services_controller', '同步系统代理到扫描服务', error, stack);
        }
      }
    } finally {
      _systemProxySyncRunning = false;
      if (_systemProxySyncPending && !_disposed) {
        _handleSystemProxyRevision();
      }
    }
  }

  Future<AiExposureProxyStatus> _updateProxyRuntime(
    AiJunglerClient client, {
    AiExposureProxyConfiguration? configuration,
  }) => _proxyRuntimeUpdateQueue.enqueue(() async {
    // 确保系统代理探测完成后再同步，避免服务启动竞态导致空快照。
    await SystemProxyResolver.instance.initialize();
    final effectiveConfiguration = configuration ?? _proxyConfiguration;
    await client.updateProxy(
      effectiveConfiguration,
      systemProxy: _systemProxyRuntimeJson,
    );
    return client.proxyStatus();
  });

  void _setHistory(List<AiExposureHistoryEntry> history) {
    _history = List<AiExposureHistoryEntry>.unmodifiable(history);
    final activeIds = _history.map((entry) => entry.id).toSet();
    _historyLogs.removeWhere((id, _) => !activeIds.contains(id));
  }

  List<AiExposureLogEntry>? _cachedHistoryLogs(String jobId) {
    final cached = _historyLogs.remove(jobId);
    if (cached == null) return null;
    _historyLogs[jobId] = cached;
    return cached;
  }

  List<AiExposureLogEntry> _cacheHistoryLogs(
    String jobId,
    Iterable<AiExposureLogEntry> logs,
  ) {
    final loaded = logs.toList(growable: false);
    final bounded = loaded.length <= _kAiExposureMaxCachedLogsPerJob
        ? loaded
        : loaded.sublist(0, _kAiExposureMaxCachedLogsPerJob);
    _historyLogs.remove(jobId);
    _historyLogs[jobId] = List<AiExposureLogEntry>.unmodifiable(bounded);
    while (_historyLogs.length > _kAiExposureMaxCachedHistoryJobs) {
      _historyLogs.remove(_historyLogs.keys.first);
    }
    return _historyLogs[jobId]!;
  }

  void attachSelectedAiModelProvider(AiModelConfig? Function() provider) {
    if (_disposed || _notifierDisposed) return;
    _selectedAiModelProvider = provider;
  }

  /// 让服务依赖与插件中心共用同一个状态源和生命周期结果。
  void attachPluginServiceController(PluginServiceController controller) {
    if (_disposed || _notifierDisposed) return;
    if (identical(_pluginServiceController, controller)) return;
    final previous = _pluginServiceController;
    final listener = _pluginStateListener;
    if (previous != null && listener != null) {
      previous.removeListener(listener);
    }
    _pluginServiceController = controller;
    _pluginStateListener = _handlePluginStateChange;
    _managedDependencySignature = '';
    controller.addListener(_pluginStateListener!);
    _handlePluginStateChange();
  }

  void _handlePluginStateChange() {
    final plugins = _pluginServiceController;
    if (_disposed || plugins == null) return;
    final signature = <String>[
      for (final id in const <String>[
        PluginCatalogIds.postgresql,
        PluginCatalogIds.redis,
        PluginCatalogIds.nodejs,
        PluginCatalogIds.playwright,
      ])
        if (plugins.pluginById(id) case final plugin?)
          '$id:${plugin.isInstalled}:${plugin.enabled}:${plugin.installPath ?? ''}:${plugin.metadata['installation_target'] ?? ''}:${plugin.metadata['data_directory'] ?? ''}',
    ].join('|');
    if (signature == _managedDependencySignature) return;
    _managedDependencySignature = signature;
    if (_client == null || _lifecycle == AiExposureServiceLifecycle.stopping) {
      return;
    }
    unawaited(
      _managedDependencyListenerSyncQueue.enqueue(
        _syncManagedDependenciesFromPluginState,
      ),
    );
  }

  Future<void> _syncManagedDependenciesFromPluginState() async {
    if (_disposed || _lifecycle == AiExposureServiceLifecycle.stopping) {
      return;
    }
    try {
      await _syncManagedDependencies();
    } catch (error, stack) {
      silentLog('services_controller', '处理插件状态触发的托管依赖同步', error, stack);
    }
  }

  Future<void> startService() async {
    if (_busy || isRunning) return;
    if (!_useBundledEngine) {
      final savedToken = await _preferencesStore.loadExternalAccessToken();
      if (savedToken != null && _externalAddress.isNotEmpty) {
        await connectExternal(
          address: _externalAddress,
          accessToken: savedToken,
        );
        return;
      }
      _errorMessage = '外部服务模式需要在服务设置中填写访问令牌后连接。';
      _notify();
      return;
    }
    _busy = true;
    _lifecycle = AiExposureServiceLifecycle.starting;
    _errorMessage = null;
    _notify();
    _appendLog(
      AiExposureLogEntry(
        level: 'info',
        message: '正在启动 AI 基础设施扫描服务。',
        at: DateTime.now(),
      ),
    );
    try {
      final client = await _runtime.startBundled();
      _health = await client.health();
      _proxyStatus = await _updateProxyRuntime(client);
      _proxyRuntimeSyncError = null;
      await _syncManagedDependencies();
      _lifecycle = AiExposureServiceLifecycle.running;
      _appendLog(
        AiExposureLogEntry(
          level: 'info',
          message: 'AI 基础设施扫描服务已启动。',
          at: DateTime.now(),
        ),
      );
      await _restoreSourceCredentials(client);
      await refreshData();
      _scheduleProxyStatisticsSync();
    } catch (error, stack) {
      _errorMessage = _reportServicesFailure(
        '启动扫描服务',
        error,
        stack,
        fallback: '启动扫描服务失败，请检查运行环境后重试。',
      );
      if (_runtime.client == null) {
        _lifecycle = AiExposureServiceLifecycle.error;
      } else {
        _lifecycle = AiExposureServiceLifecycle.running;
        _completeRunningActivation();
      }
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// 引擎已就绪但启动/连接期间部分初始化失败时，仍进入运行态并补齐数据加载与
  /// 代理统计轮询，避免"运行中却空白、统计定时器缺失"的半初始化状态。
  void _completeRunningActivation() {
    _scheduleProxyStatisticsSync();
    unawaited(refreshData());
  }

  Future<bool> connectExternal({
    required String address,
    required String accessToken,
  }) async {
    if (_busy) return false;
    _busy = true;
    _lifecycle = AiExposureServiceLifecycle.starting;
    _errorMessage = null;
    _notify();
    try {
      final uri = Uri.tryParse(address.trim());
      if (uri == null) throw const FormatException('服务地址格式无效。');
      final client = await _runtime.connectExternal(
        address: uri,
        accessToken: accessToken,
      );
      _health = await client.health();
      _proxyStatus = await _updateProxyRuntime(client);
      _proxyRuntimeSyncError = null;
      await _syncManagedDependencies();
      _lifecycle = AiExposureServiceLifecycle.running;
      await _preferencesStore.saveExternalAccessToken(accessToken);
      await _restoreSourceCredentials(client);
      await refreshData();
      _scheduleProxyStatisticsSync();
      return true;
    } catch (error, stack) {
      _errorMessage = _reportServicesFailure(
        '连接外部扫描服务',
        error,
        stack,
        fallback: '连接外部扫描服务失败，请检查地址、令牌和网络后重试。',
      );
      if (_runtime.client == null) {
        _lifecycle = AiExposureServiceLifecycle.error;
      } else {
        _lifecycle = AiExposureServiceLifecycle.running;
        _completeRunningActivation();
      }
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> stopService() async {
    if (_busy ||
        _lifecycle == AiExposureServiceLifecycle.stopped ||
        _lifecycle == AiExposureServiceLifecycle.stopping) {
      return;
    }
    _busy = true;
    _lifecycle = AiExposureServiceLifecycle.stopping;
    _managedDependencyListenerSyncQueue.discardPending();
    _systemProxySyncPending = false;
    _notify();
    try {
      await _drainRuntimeOperations();
      await _runtime.stop();
      _lifecycle = AiExposureServiceLifecycle.stopped;
      _health = null;
      _progress = null;
      _aiExtractorStatus = null;
      _dependencyStatus = null;
      _dependencyDataOverview = const <String, Object?>{};
      _dependencyTelemetryHistory.clear();
      _dependencyDataOverviewError = null;
      _proxyStatus = null;
      _errorMessage = null;
      _appendLog(
        AiExposureLogEntry(
          level: 'info',
          message: 'AI 基础设施扫描服务已停止。',
          at: DateTime.now(),
        ),
      );
    } catch (error, stack) {
      _lifecycle = AiExposureServiceLifecycle.error;
      _errorMessage = _reportServicesFailure('停止扫描服务', error, stack);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> refreshData({bool forcePluginRescan = false}) async {
    AiJunglerClient? requestClient;
    try {
      if (forcePluginRescan) {
        await _rescanPluginState();
        await _syncManagedDependencies();
      }
      final client = _requireClient();
      requestClient = client;
      final values = await Future.wait<Object>(<Future<Object>>[
        client.health(),
        client.quotas(),
        client.history(),
        client.results(),
        client.rules(),
        client.sourceStatus(),
        client.aiExtractorStatus(),
        client.dependencyStatus(),
        client.proxyStatus(),
      ]);
      if (!_isCurrentClient(client)) return;
      final proxyStatus = values[8] as AiExposureProxyStatus;
      await _mergeProxyStatistics(proxyStatus);
      if (!_isCurrentClient(client)) return;
      _health = values[0] as AiExposureHealth;
      _quotas = List<AiExposureQuota>.unmodifiable(
        values[1] as List<AiExposureQuota>,
      );
      _setHistory(values[2] as List<AiExposureHistoryEntry>);
      _results = List<AiExposureResult>.unmodifiable(
        values[3] as List<AiExposureResult>,
      );
      _rules = List<AiExposureScanRule>.unmodifiable(
        values[4] as List<AiExposureScanRule>,
      );
      _sourceStatus = Map<String, bool>.unmodifiable(
        values[5] as Map<String, bool>,
      );
      _aiExtractorStatus = values[6] as AiExposureAiExtractorStatus;
      _dependencyStatus = values[7] as AiExposureDependencyStatus;
      _proxyStatus = proxyStatus;
      _errorMessage = null;
    } catch (error, stack) {
      if (requestClient != null && !_isCurrentClient(requestClient)) return;
      _errorMessage = _reportServicesFailure('刷新扫描服务数据', error, stack);
    }
    _notify();
  }

  Future<void> _rescanPluginState() async {
    final plugins = _pluginServiceController;
    if (plugins == null) return;
    try {
      await plugins.rescan();
    } catch (error, stack) {
      // 插件扫描失败时保留上次状态，继续刷新扫描服务其余数据。
      silentLog('services_controller', '强制刷新插件状态', error, stack);
    }
  }

  Future<void> refreshServiceStatus() {
    return _serviceStatusRefresh.run(() async {
      AiJunglerClient? requestClient;
      try {
        final client = _requireClient();
        requestClient = client;
        final values = await Future.wait<Object>(<Future<Object>>[
          client.health(),
          client.quotas(),
          client.sourceStatus(),
          client.dependencyStatus(),
          client.proxyStatus(),
        ]);
        if (!_isCurrentClient(client)) return;
        final proxyStatus = values[4] as AiExposureProxyStatus;
        await _mergeProxyStatistics(proxyStatus);
        if (!_isCurrentClient(client)) return;
        _health = values[0] as AiExposureHealth;
        _quotas = List<AiExposureQuota>.unmodifiable(
          values[1] as List<AiExposureQuota>,
        );
        _sourceStatus = Map<String, bool>.unmodifiable(
          values[2] as Map<String, bool>,
        );
        _dependencyStatus = values[3] as AiExposureDependencyStatus;
        _proxyStatus = proxyStatus;
        _errorMessage = null;
      } catch (error, stack) {
        if (requestClient != null && !_isCurrentClient(requestClient)) return;
        _errorMessage = _reportServicesFailure('刷新扫描服务状态', error, stack);
      }
      _notify();
    });
  }

  Future<void> refreshManagedDependencyStatus({
    bool forcePluginRescan = false,
  }) async {
    if (forcePluginRescan) await _rescanPluginState();
    await _syncManagedDependencies();
    await refreshServiceStatus();
  }

  Future<bool> refreshDependencyDataOverview() async {
    AiJunglerClient? requestClient;
    try {
      final client = _requireClient();
      requestClient = client;
      final overview = await client.dependencyDataOverview();
      if (!_isCurrentClient(client)) return false;
      _dependencyDataOverview = Map<String, Object?>.unmodifiable(overview);
      _dependencyTelemetryHistory.add(overview);
      _dependencyDataOverviewError = null;
      _notify();
      return true;
    } catch (error, stack) {
      if (requestClient != null && !_isCurrentClient(requestClient)) {
        return false;
      }
      _dependencyDataOverviewError = _reportServicesFailure(
        '刷新依赖数据遥测',
        error,
        stack,
      );
      _notify();
      return false;
    }
  }

  Future<Map<String, Object?>> loadPostgresqlRows(
    String table, {
    int limit = 50,
    int offset = 0,
  }) => _runDependencyDataOperation(
    '读取 PostgreSQL 数据',
    (client) => client.postgresqlRows(table, limit: limit, offset: offset),
  );

  Future<void> insertPostgresqlRow(
    String table,
    Map<String, Object?> values,
  ) async {
    await _runDependencyDataOperation(
      '新增 PostgreSQL 记录',
      (client) => client.insertPostgresqlRow(table, values),
    );
    await refreshDependencyDataOverview();
  }

  Future<void> updatePostgresqlRow(
    String table, {
    required Map<String, Object?> keys,
    required Map<String, Object?> values,
  }) async {
    await _runDependencyDataOperation(
      '更新 PostgreSQL 记录',
      (client) => client.updatePostgresqlRow(table, keys: keys, values: values),
    );
    await refreshDependencyDataOverview();
  }

  Future<void> deletePostgresqlRow(
    String table,
    Map<String, Object?> keys,
  ) async {
    await _runDependencyDataOperation(
      '删除 PostgreSQL 记录',
      (client) => client.deletePostgresqlRow(table, keys),
    );
    await refreshDependencyDataOverview();
  }

  Future<Map<String, Object?>> queryPostgresql(String statement) =>
      _runDependencyDataOperation(
        '执行 PostgreSQL 只读查询',
        (client) => client.queryPostgresql(statement),
      );

  Future<Map<String, Object?>> loadRedisRecords({
    int cursor = 0,
    String search = '',
  }) => _runDependencyDataOperation(
    '读取 Redis 数据',
    (client) => client.redisRecords(cursor: cursor, search: search),
  );

  Future<void> putRedisRecord({
    required String key,
    required String type,
    required Object? value,
    required int? ttlSeconds,
  }) async {
    await _runDependencyDataOperation(
      '保存 Redis 数据',
      (client) => client.putRedisRecord(
        key: key,
        type: type,
        value: value,
        ttlSeconds: ttlSeconds,
      ),
    );
    await refreshDependencyDataOverview();
  }

  Future<void> deleteRedisRecord(String key) async {
    await _runDependencyDataOperation(
      '删除 Redis 数据',
      (client) => client.deleteRedisRecord(key),
    );
    await refreshDependencyDataOverview();
  }

  Future<T> _runDependencyDataOperation<T>(
    String action,
    Future<T> Function(AiJunglerClient client) operation,
  ) async {
    try {
      final result = await operation(_requireClient());
      _errorMessage = null;
      _notify();
      return result;
    } catch (error, stack) {
      final message = _reportServicesFailure(action, error, stack);
      _errorMessage = message;
      _notify();
      throw AiJunglerApiException(message);
    }
  }

  Future<bool> startScan(AiExposureScanRequest request) async {
    if (_scanBusy) {
      _errorMessage = '正在创建扫描任务，请稍候。';
      _notify();
      return false;
    }
    if (hasActiveScan) {
      _errorMessage = '已有扫描任务正在运行。';
      _notify();
      return false;
    }
    if (_busy || _lifecycle != AiExposureServiceLifecycle.running) {
      _errorMessage = '扫描服务尚未就绪，请等待服务启动完成。';
      _notify();
      return false;
    }
    _scanBusy = true;
    _errorMessage = null;
    _notify();
    try {
      final client = _requireClient();
      await _configureAiExtractor(request.gptAssisted);
      final jobId = await client.createJob(request);
      _progress = await client.progress(jobId);
      _logs.clear();
      await _watchJob(jobId);
      unawaited(_refreshHistoryAndResultsSafely());
      return true;
    } catch (error, stack) {
      _errorMessage = _reportServicesFailure('创建扫描任务', error, stack);
      return false;
    } finally {
      _scanBusy = false;
      _notify();
    }
  }

  Future<void> stopScan() async {
    final jobId = _progress?.jobId;
    if (jobId == null || jobId.isEmpty || !hasActiveScan) return;
    _eventStreamReconnectAttempts = 0;
    if (_errorMessage == _eventStreamErrorMessage) _errorMessage = null;
    _eventStreamErrorMessage = null;
    await _cancelEventSubscription();
    _notify();
    try {
      await _requireClient().stopJob(jobId);
    } catch (error, stack) {
      // 任务恰好已结束时后端返回 409，也需继续回读终态收敛 UI。
      _errorMessage = _reportServicesFailure('停止扫描任务', error, stack);
    }
    await _awaitScanTermination(jobId);
    _notify();
  }

  /// 取消实时订阅后，有界轮询任务状态直至进入终态。
  /// 这是停止/重连兜底的唯一 `_progress` 刷新路径，避免工作台卡在"运行中"。
  Future<void> _awaitScanTermination(
    String jobId, {
    int maxAttempts = _kScanTerminationSyncMaxAttempts,
    Duration interval = _kScanTerminationSyncInterval,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final client = _client;
      if (client == null || _disposed) return;
      final AiExposureProgress progress;
      try {
        progress = await client.progress(jobId);
      } catch (error, stack) {
        silentLog('services_controller', '回读扫描任务终态', error, stack);
        return;
      }
      if (!_isCurrentClient(client)) return;
      _progress = progress;
      if (!progress.isRunning) {
        _eventStreamReconnectAttempts = 0;
        if (_errorMessage == _eventStreamErrorMessage) _errorMessage = null;
        _eventStreamErrorMessage = null;
        await _refreshHistoryAndResultsSafely();
        return;
      }
      _notify();
      await Future<void>.delayed(interval);
    }
  }

  Future<bool> resumeHistory(String jobId) async {
    if (_scanBusy) {
      _errorMessage = '正在处理扫描任务，请稍候。';
      _notify();
      return false;
    }
    if (hasActiveScan) {
      _errorMessage = '已有扫描任务正在运行。';
      _notify();
      return false;
    }
    if (_busy || _lifecycle != AiExposureServiceLifecycle.running) {
      _errorMessage = '扫描服务尚未就绪，请等待服务启动完成。';
      _notify();
      return false;
    }
    _scanBusy = true;
    _errorMessage = null;
    _notify();
    try {
      final client = _requireClient();
      // 若被恢复的任务原先启用 GPT 辅助提取，需在恢复前重新下发模型配置，
      // 否则服务重启后引擎的 AiExtractor 为空会直接拒绝该任务。
      var resumedGptAssisted = false;
      for (final entry in _history) {
        if (entry.id == jobId) {
          resumedGptAssisted = entry.gptAssisted ?? false;
          break;
        }
      }
      await _configureAiExtractor(resumedGptAssisted);
      final resumedId = await client.resumeJob(jobId);
      _progress = await client.progress(resumedId);
      _logs.clear();
      await _watchJob(resumedId);
      unawaited(_refreshHistoryAndResultsSafely());
      return true;
    } catch (error, stack) {
      _errorMessage = _reportServicesFailure('恢复扫描任务', error, stack);
      return false;
    } finally {
      _scanBusy = false;
      _notify();
    }
  }

  bool isConnectedToExternalAddress(String address) =>
      _runtime.isConnectedToExternalAddress(address);

  Future<void> deleteHistory(String jobId) async {
    try {
      await _requireClient().deleteHistory(jobId);
      await _refreshHistoryAndResults();
      _historyLogs.remove(jobId);
    } catch (error, stack) {
      _errorMessage = _reportServicesFailure('删除扫描历史', error, stack);
    }
    _notify();
  }

  Future<bool> saveRules(List<AiExposureScanRule> rules) async {
    try {
      await _requireClient().saveRules(rules);
      _rules = List<AiExposureScanRule>.unmodifiable(
        await _requireClient().rules(),
      );
      _errorMessage = null;
      return true;
    } catch (error, stack) {
      _errorMessage = _reportServicesFailure('保存扫描规则', error, stack);
      return false;
    } finally {
      _notify();
    }
  }

  Future<bool> updateSourceCredentials({
    String? githubToken,
    String? giteeToken,
    String? gitcodeToken,
    String? fofaEmail,
    String? fofaKey,
    String? shodanKey,
  }) async {
    try {
      final client = _requireClient();
      await client.updateSourceCredentials(
        githubToken: githubToken,
        giteeToken: giteeToken,
        gitcodeToken: gitcodeToken,
        fofaEmail: fofaEmail,
        fofaKey: fofaKey,
        shodanKey: shodanKey,
      );
      _sourceStatus = Map<String, bool>.unmodifiable(
        await client.sourceStatus(),
      );
      _errorMessage = null;
      await _preferencesStore.saveSourceCredentials(<String, String>{
        if (githubToken != null && githubToken.trim().isNotEmpty)
          'githubToken': githubToken.trim(),
        if (giteeToken != null && giteeToken.trim().isNotEmpty)
          'giteeToken': giteeToken.trim(),
        if (gitcodeToken != null && gitcodeToken.trim().isNotEmpty)
          'gitcodeToken': gitcodeToken.trim(),
        if (fofaEmail != null && fofaEmail.trim().isNotEmpty)
          'fofaEmail': fofaEmail.trim(),
        if (fofaKey != null && fofaKey.trim().isNotEmpty)
          'fofaKey': fofaKey.trim(),
        if (shodanKey != null && shodanKey.trim().isNotEmpty)
          'shodanKey': shodanKey.trim(),
      });
      return true;
    } catch (error, stack) {
      _errorMessage = _reportServicesFailure('更新扫描数据源凭证', error, stack);
      return false;
    } finally {
      _notify();
    }
  }

  Future<bool> updateProxyConfiguration(
    AiExposureProxyConfiguration configuration,
  ) => _applyProxyConfiguration(
    configuration,
    logMessage: configuration.enabled
        ? configuration.activeEndpoints.isEmpty
              ? '代理池已启用但暂无可用节点，网络请求将使用 ${systemProxyAvailable ? '系统代理' : 'DIRECT'}。'
              : '代理池已启用，共 ${configuration.activeEndpoints.length} 个可用节点。'
        : '代理池已停用，网络请求将使用 ${systemProxyAvailable ? '系统代理' : 'DIRECT'}。',
  );

  Future<bool> updateProxyEndpoints(List<AiExposureProxyEndpoint> endpoints) {
    final activeCount = endpoints.where((endpoint) => endpoint.enabled).length;
    final current = _proxyConfiguration;
    return _applyProxyConfiguration(
      current.copyWith(
        enabled: current.enabled,
        inspectionEnabled: current.inspectionEnabled && activeCount > 0,
        endpoints: endpoints,
      ),
      logMessage: '代理节点配置已更新，共 ${endpoints.length} 个节点，$activeCount 个启用。',
    );
  }

  Future<bool> _applyProxyConfiguration(
    AiExposureProxyConfiguration configuration, {
    required String logMessage,
  }) async {
    _proxyInspectionGeneration++;
    _proxyInspectionCancelRequested = true;
    _proxyInspectionCancellation?.cancel();
    _proxyInspectionScheduleGeneration++;
    _proxyInspectionTimer?.cancel();
    _proxyInspectionTimer = null;
    final previousConfiguration = _proxyConfiguration;
    final previousStatus = _proxyStatus;
    try {
      if (configuration.endpoints.length > kAiExposureMaxProxyEndpoints) {
        throw const FormatException(
          '代理池最多支持 $kAiExposureMaxProxyEndpoints 个代理。',
        );
      }
      if (configuration.inspectionEnabled &&
          configuration.activeEndpoints.isEmpty) {
        throw const FormatException('启用巡检前至少启用一个代理节点。');
      }
      _proxyConfiguration = configuration;
      if (!await _persistPreferences()) {
        _proxyConfiguration = previousConfiguration;
        _proxyStatus = previousStatus;
        _scheduleProxyInspection();
        _scheduleProxyStatisticsSync();
        _notify();
        return false;
      }
    } catch (error, stack) {
      _proxyConfiguration = previousConfiguration;
      _proxyStatus = previousStatus;
      _scheduleProxyInspection();
      _scheduleProxyStatisticsSync();
      _errorMessage = _reportServicesFailure(
        '保存扫描网络代理',
        error,
        stack,
        fallback: '保存扫描网络代理失败，请检查配置后重试。',
      );
      _notify();
      return false;
    }

    _scheduleProxyInspection(firstDelay: _proxyInspectionFirstRunDelay);
    _scheduleProxyStatisticsSync();
    _errorMessage = null;
    _proxyRuntimeSyncError = null;
    _appendLog(
      AiExposureLogEntry(
        level: 'info',
        message: logMessage,
        at: DateTime.now(),
      ),
    );
    final client = _client;
    if (client != null) {
      try {
        final status = await _updateProxyRuntime(
          client,
          configuration: configuration,
        );
        if (_isCurrentClient(client)) {
          _proxyStatus = status;
          try {
            await _mergeProxyStatistics(status);
          } catch (error, stack) {
            silentLog('services_controller', '保存代理运行统计', error, stack);
          }
        }
      } catch (error, stack) {
        if (_isCurrentClient(client)) {
          _proxyStatus = previousStatus;
          final syncError = _reportServicesFailure(
            '同步代理配置到扫描服务',
            error,
            stack,
            fallback: '扫描服务暂时无法接收代理配置。',
          );
          _proxyRuntimeSyncError = syncError;
          _appendLog(
            AiExposureLogEntry(
              level: 'warning',
              message: '代理配置已保存，但未能同步到扫描服务：$syncError',
              at: DateTime.now(),
            ),
          );
        }
      }
    }
    _notify();
    return true;
  }

  Future<void> saveProxyProbeSamples(
    Map<String, AiExposureProxyProbeSample> samples,
  ) async {
    if (samples.isEmpty || _disposed) return;
    final endpoints = List<AiExposureProxyEndpoint>.of(
      _proxyConfiguration.endpoints,
    );
    final indexes = <String, int>{
      for (var index = 0; index < endpoints.length; index++)
        endpoints[index].url: index,
    };
    var changed = false;
    final changedEndpoints = <AiExposureProxyEndpoint>[];
    for (final entry in samples.entries) {
      final index = indexes[entry.key];
      if (index == null) continue;
      endpoints[index] = endpoints[index].withSample(entry.value);
      changedEndpoints.add(endpoints[index]);
      changed = true;
    }
    if (!changed) return;
    _proxyConfiguration = _proxyConfiguration.copyWith(endpoints: endpoints);
    await _persistProxySamples(changedEndpoints);
    _notify();
  }

  Future<bool> inspectAllProxies({
    required int concurrency,
    AiExposureProxyInspectionResultCallback? onResult,
    DateTime? scheduledAt,
  }) async {
    if (_proxyInspectionRunning || _disposed) return false;
    final configuration = _proxyConfiguration;
    final targets = <(int, AiExposureProxyEndpoint)>[];
    for (var index = 0; index < configuration.endpoints.length; index++) {
      final endpoint = configuration.endpoints[index];
      if (endpoint.enabled) targets.add((index, endpoint));
    }
    if (targets.isEmpty) return false;
    final generation = ++_proxyInspectionGeneration;
    final runStartedAt = DateTime.now();
    final inspectionRunId =
        'inspection-${runStartedAt.microsecondsSinceEpoch}-$generation';
    _proxyInspectionCancelRequested = false;
    _proxyInspectionRunning = true;
    final cancellation = AiExposureProxyProbeCancellation();
    _proxyInspectionCancellation = cancellation;
    _notify();
    var pending = <(int, String, AiExposureProxyProbeSample)>[];
    Future<bool>? persistence;
    var persistenceFailed = false;
    var cursor = 0;
    var completed = 0;
    var healthy = 0;
    final workerCount = concurrency.clamp(
      1,
      kAiExposureMaxProxyInspectionConcurrency,
    );

    Future<bool> persistCheckpoint({required bool force}) async {
      if (persistenceFailed) return false;
      while (persistence != null) {
        if (_disposed ||
            generation != _proxyInspectionGeneration ||
            _proxyInspectionCancelRequested) {
          return false;
        }
        if (!await persistence!) return false;
      }
      if (persistenceFailed) return false;
      if ((!force && pending.length < _kProxyInspectionCheckpointSize) ||
          pending.isEmpty) {
        return !persistenceFailed;
      }
      if (_disposed || generation != _proxyInspectionGeneration) return false;
      final batch = pending;
      pending = <(int, String, AiExposureProxyProbeSample)>[];
      final current = _proxyConfiguration;
      final updatedEndpoints = List<AiExposureProxyEndpoint>.of(
        current.endpoints,
      );
      final changedEndpoints = <AiExposureProxyEndpoint>[];
      for (final (index, url, sample) in batch) {
        if (index >= updatedEndpoints.length ||
            updatedEndpoints[index].url != url) {
          continue;
        }
        updatedEndpoints[index] = updatedEndpoints[index].withSample(sample);
        changedEndpoints.add(updatedEndpoints[index]);
      }
      _proxyConfiguration = current.copyWith(endpoints: updatedEndpoints);
      final saving = _persistProxySamples(changedEndpoints);
      persistence = saving;
      try {
        final saved = await saving;
        if (!saved) persistenceFailed = true;
        if (!_disposed && generation == _proxyInspectionGeneration) _notify();
        return saved;
      } finally {
        if (identical(persistence, saving)) persistence = null;
      }
    }

    Future<void> worker() async {
      while (!_disposed &&
          generation == _proxyInspectionGeneration &&
          !_proxyInspectionCancelRequested &&
          !persistenceFailed) {
        final index = cursor++;
        if (index >= targets.length) return;
        final (endpointIndex, endpoint) = targets[index];
        late final AiExposureProxyProbeSample sample;
        try {
          sample = await _proxyProbe.inspect(
            endpoint,
            inspectionRunId: inspectionRunId,
            scheduledAt: scheduledAt,
            cancellation: cancellation,
          );
        } on AiExposureProxyProbeCancelledException {
          return;
        }
        if (_disposed || generation != _proxyInspectionGeneration) return;
        pending.add((endpointIndex, endpoint.url, sample));
        completed++;
        if (sample.reachable) healthy++;
        onResult?.call(endpoint.url, sample, completed, targets.length);
        if (pending.length >= _kProxyInspectionCheckpointSize &&
            !await persistCheckpoint(force: false)) {
          return;
        }
      }
    }

    try {
      await Future.wait<void>(
        List<Future<void>>.generate(
          targets.length.clamp(1, workerCount),
          (_) => worker(),
        ),
      );
      if (_disposed || generation != _proxyInspectionGeneration) return false;
      if (!await persistCheckpoint(force: true)) {
        return false;
      }
      final cancelled = _proxyInspectionCancelRequested;
      _appendLog(
        AiExposureLogEntry(
          level: !cancelled && healthy == completed ? 'info' : 'warning',
          message: cancelled
              ? '代理巡检已停止：已完成 $completed 个节点，$healthy 个可连通。'
              : '代理巡检完成：$completed 个节点，$healthy 个可连通。',
          at: DateTime.now(),
        ),
      );
      return true;
    } catch (error, stack) {
      _errorMessage = _reportServicesFailure('巡检代理节点', error, stack);
      return false;
    } finally {
      _proxyInspectionRunning = false;
      if (identical(_proxyInspectionCancellation, cancellation)) {
        _proxyInspectionCancellation = null;
      }
      if (!_disposed) {
        _notify();
      }
    }
  }

  void cancelProxyInspection() {
    if (!_proxyInspectionRunning) return;
    _proxyInspectionCancelRequested = true;
    _proxyInspectionCancellation?.cancel();
    _notify();
  }

  void _scheduleProxyInspection({Duration? firstDelay}) {
    final generation = ++_proxyInspectionScheduleGeneration;
    _proxyInspectionTimer?.cancel();
    _proxyInspectionTimer = null;
    final configuration = _proxyConfiguration;
    if (!configuration.inspectionEnabled ||
        !configuration.endpoints.any((endpoint) => endpoint.enabled)) {
      return;
    }
    _armProxyInspectionTimer(
      generation,
      firstDelay ??
          Duration(
            minutes: configuration.inspectionIntervalMinutes.clamp(
              1,
              kAiExposureMaxProxyInspectionIntervalMinutes,
            ),
          ),
    );
  }

  void _armProxyInspectionTimer(int generation, Duration delay) {
    _proxyInspectionTimer = startSafeTimer(
      delay,
      () async {
        _proxyInspectionTimer = null;
        if (_disposed || generation != _proxyInspectionScheduleGeneration) {
          return;
        }
        await inspectAllProxies(
          concurrency: _proxyConfiguration.inspectionConcurrency,
          scheduledAt: DateTime.now(),
        );
        if (_disposed || generation != _proxyInspectionScheduleGeneration) {
          return;
        }
        _armProxyInspectionTimer(
          generation,
          Duration(
            minutes: _proxyConfiguration.inspectionIntervalMinutes.clamp(
              1,
              kAiExposureMaxProxyInspectionIntervalMinutes,
            ),
          ),
        );
      },
      onError: (error, stack) =>
          silentLog('services_controller', '执行定时代理巡检', error, stack),
    );
  }

  void _scheduleProxyStatisticsSync() {
    _proxyStatisticsTimer?.cancel();
    _proxyStatisticsTimer = null;
    if (_client == null || !_proxyConfiguration.enabled) return;
    _proxyStatisticsTimer = startNonOverlappingPeriodicTimer(
      _kProxyStatisticsSyncInterval,
      (_) => _syncProxyStatistics(notify: true),
      onError: (error, stack) =>
          silentLog('services_controller', '执行定时代理统计同步', error, stack),
    );
  }

  Future<void> _syncProxyStatistics({bool notify = false}) async {
    final client = _client;
    if (client == null || _disposed) return;
    await _proxyStatisticsSync.run(() async {
      try {
        final status = await client.proxyStatus();
        if (!_isCurrentClient(client)) return;
        final changed = await _mergeProxyStatistics(status);
        if (!_isCurrentClient(client)) return;
        _proxyStatus = status;
        if (notify && changed) _notify();
      } catch (error, stack) {
        silentLog('services_controller', '同步代理使用统计', error, stack);
      }
    });
  }

  Future<bool> _mergeProxyStatistics(AiExposureProxyStatus status) async {
    final byId = <String, AiExposureProxyEndpointStatus>{
      for (final item in status.endpoints) item.id: item,
    };
    var changed = false;
    var runtimeChanged = false;
    final changedEndpoints = <AiExposureProxyEndpoint>[];
    final requestHistory = <AiExposureProxyRequestRecord>[];
    final windowRecordIdsByUrl = <String, Set<String>>{};
    final beforeAwait = _proxyConfiguration.endpoints;
    final endpoints = beforeAwait
        .map((endpoint) {
          final runtime = byId[endpoint.runtimeId];
          if (runtime == null) return endpoint;
          final current = endpoint.statistics;
          final next = runtime.statistics;
          final statisticsChanged = !current.hasSamePersistedState(next);
          final updated = endpoint.copyWith(statistics: next);
          if (statisticsChanged) {
            changed = true;
            changedEndpoints.add(updated);
            final persisted =
                _persistedRequestRecordIds[endpoint.url] ?? const <String>{};
            final windowIds = <String>{};
            for (final sample in next.recentRequests) {
              // 未上报时间的样本存储层会跳过，且其 recordId 不稳定，直接忽略。
              if (!sample.atReported) continue;
              final record = AiExposureProxyRequestRecord(
                endpointUrl: endpoint.url,
                sample: sample,
              );
              final recordId = record.recordId;
              windowIds.add(recordId);
              if (!persisted.contains(recordId)) requestHistory.add(record);
            }
            windowRecordIdsByUrl[endpoint.url] = windowIds;
          }
          if (current.inFlight != next.inFlight) runtimeChanged = true;
          return updated;
        })
        .toList(growable: false);
    if (changed) {
      await _preferencesStore.saveProxyStatistics(changedEndpoints);
      try {
        await _preferencesStore.saveProxyRequestHistory(requestHistory);
        // 保存成功后才推进增量水位；失败时保持原水位，下一轮全量重发。
        final activeUrls = <String>{
          for (final endpoint in _proxyConfiguration.endpoints) endpoint.url,
        };
        _persistedRequestRecordIds
          ..addAll(windowRecordIdsByUrl)
          ..removeWhere((url, _) => !activeUrls.contains(url));
      } catch (error, stack) {
        silentLog('services_controller', '保存代理请求明细', error, stack);
      }
    }
    if (changed || runtimeChanged) {
      // await 期间其他操作可能已更新 endpoints（如巡检写入新样本），
      // 此处基于最新配置做增量合并，避免覆盖其他操作的修改。
      final latest = _proxyConfiguration.endpoints;
      final merged = List<AiExposureProxyEndpoint>.of(latest);
      final updatesByUrl = <String, AiExposureProxyEndpoint>{
        for (final endpoint in endpoints) endpoint.url: endpoint,
      };
      for (var index = 0; index < merged.length; index++) {
        final updated = updatesByUrl[merged[index].url];
        if (updated != null) merged[index] = updated;
      }
      _proxyConfiguration = _proxyConfiguration.copyWith(endpoints: merged);
    }
    return changed || runtimeChanged;
  }

  Future<bool> updateProxyIdentity(
    String url,
    AiExposureProxyIdentity identity,
  ) async {
    final index = _proxyConfiguration.endpoints.indexWhere(
      (endpoint) => endpoint.url == url,
    );
    if (index < 0) {
      _errorMessage = '代理节点不存在。';
      _notify();
      return false;
    }
    final previousIdentity = _proxyConfiguration.endpoints[index].identity;
    final endpoints = List<AiExposureProxyEndpoint>.of(
      _proxyConfiguration.endpoints,
    );
    endpoints[index] = endpoints[index].copyWith(identity: identity);
    _proxyConfiguration = _proxyConfiguration.copyWith(endpoints: endpoints);
    if (!await _persistPreferences()) {
      final currentEndpoints = List<AiExposureProxyEndpoint>.of(
        _proxyConfiguration.endpoints,
      );
      final currentIndex = currentEndpoints.indexWhere(
        (endpoint) => endpoint.url == url,
      );
      if (currentIndex >= 0) {
        final current = currentEndpoints[currentIndex];
        if (!identical(current.identity, identity)) {
          _notify();
          return false;
        }
        currentEndpoints[currentIndex] = AiExposureProxyEndpoint(
          url: current.url,
          name: current.name,
          enabled: current.enabled,
          samples: current.samples,
          statistics: current.statistics,
          identity: previousIdentity,
        );
        _proxyConfiguration = _proxyConfiguration.copyWith(
          endpoints: currentEndpoints,
        );
      }
      _notify();
      return false;
    }
    _errorMessage = null;
    _notify();
    return true;
  }

  Future<void> refreshServiceLogs({bool force = false}) async {
    final client = _client;
    if (_logRefreshBusy || client == null) return;
    _logRefreshBusy = true;
    try {
      final recent = _history
          .take(_kAiExposureMaxCachedHistoryJobs)
          .toList(growable: false);
      final batches = await Future.wait(
        recent.map((entry) async {
          final cached = force ? null : _cachedHistoryLogs(entry.id);
          if (cached != null) return cached;
          return client.logs(entry.id, limit: _kAiExposureLogFetchBatchSize);
        }),
      );
      if (!_isCurrentClient(client)) return;
      for (var index = 0; index < recent.length; index++) {
        _cacheHistoryLogs(recent[index].id, batches[index]);
      }
      final merged = <AiExposureLogEntry>[
        ..._logs,
        ...batches.expand((item) => item),
      ];
      final unique = <String, AiExposureLogEntry>{};
      for (final entry in merged) {
        final key =
            entry.id ??
            '${entry.jobId}\x00${entry.at.millisecondsSinceEpoch}\x00${entry.level}\x00${entry.message}';
        unique[key] = entry;
      }
      final sorted = unique.values.toList()
        ..sort((left, right) => left.at.compareTo(right.at));
      _logs
        ..clear()
        ..addAll(
          sorted.length <= _kAiExposureMaxLogs
              ? sorted
              : sorted.sublist(sorted.length - _kAiExposureMaxLogs),
        );
      _errorMessage = null;
    } catch (error, stack) {
      if (!_isCurrentClient(client)) return;
      _errorMessage = _reportServicesFailure('刷新扫描服务日志', error, stack);
    } finally {
      _logRefreshBusy = false;
      _notify();
    }
  }

  void clearLogs() {
    _logs.clear();
    _notify();
  }

  Future<bool> updateDependencies({
    String? postgresqlUrl,
    String? redisUrl,
  }) async {
    try {
      final client = _requireClient();
      await client.updateDependencies(
        postgresqlUrl: postgresqlUrl,
        redisUrl: redisUrl,
      );
      _dependencyStatus = await client.dependencyStatus();
      _errorMessage = null;
      _notify();
      return true;
    } catch (error, stack) {
      _errorMessage = _reportServicesFailure('更新扫描运行依赖', error, stack);
      _notify();
      return false;
    }
  }

  /// 保存结构化的运行依赖选择，并使用 OpenHand 托管实例的默认连接地址。
  Future<bool> updateManagedDependencyPreferences({
    required bool postgresqlEnabled,
    required bool redisEnabled,
  }) async {
    final previousPostgresqlEnabled = _postgresqlEnabled;
    final previousRedisEnabled = _redisEnabled;
    final changed =
        previousPostgresqlEnabled != postgresqlEnabled ||
        previousRedisEnabled != redisEnabled;
    _postgresqlEnabled = postgresqlEnabled;
    _redisEnabled = redisEnabled;

    if (!await _syncManagedDependencies()) {
      if (!changed) return false;
      final failure = _errorMessage ?? '更新扫描运行依赖失败。';
      _postgresqlEnabled = previousPostgresqlEnabled;
      _redisEnabled = previousRedisEnabled;
      final restored = await _syncManagedDependencies();
      _errorMessage = restored ? failure : '$failure 运行依赖恢复失败，请重启扫描服务。';
      _notify();
      return false;
    }

    if (!changed) return true;
    if (await _persistPreferences()) {
      _errorMessage = null;
      _notify();
      return true;
    }

    final failure = _errorMessage ?? '保存扫描运行依赖失败。';
    _postgresqlEnabled = previousPostgresqlEnabled;
    _redisEnabled = previousRedisEnabled;
    final restored = await _syncManagedDependencies();
    _errorMessage = restored ? failure : '$failure 运行依赖恢复失败，请重启扫描服务。';
    _notify();
    return false;
  }

  Future<bool> _syncManagedDependencies() =>
      _managedDependencyUpdateQueue.enqueue(_syncManagedDependenciesNow);

  Future<bool> _syncManagedDependenciesNow() async {
    final client = _client;
    if (client == null) return true;
    final plugins = _pluginServiceController;
    final postgresql = plugins?.pluginById(PluginCatalogIds.postgresql);
    final redis = plugins?.pluginById(PluginCatalogIds.redis);
    final postgresqlUrl =
        _postgresqlEnabled &&
            postgresql?.isInstalled == true &&
            postgresql!.enabled
        ? ManagedServiceDefaults.postgresqlEndpoint
        : '';
    final redisUrl =
        _redisEnabled && redis?.isInstalled == true && redis!.enabled
        ? ManagedServiceDefaults.redisEndpoint
        : '';
    final playwright = _playwrightDependencyPayload();
    try {
      await client.updateDependencies(
        postgresqlUrl: postgresqlUrl,
        redisUrl: redisUrl,
        playwright: playwright,
      );
      if (!_isCurrentClient(client)) return true;
      final status = await client.dependencyStatus();
      if (!_isCurrentClient(client)) return true;
      _dependencyStatus = status;
      _errorMessage = null;
      _notify();
      return true;
    } catch (error, stack) {
      if (!_isCurrentClient(client)) return true;
      _errorMessage = _reportServicesFailure('同步托管运行依赖', error, stack);
      _notify();
      return false;
    }
  }

  Future<bool> updateScanPreferences({
    required Set<AiExposureSource> enabledSources,
    required int concurrency,
    required AiExposureValidationMode validationMode,
    required AiExposureForumFetchMode forumFetchMode,
    bool? gptAssisted,
  }) async {
    final previousSources = _enabledSources;
    final previousConcurrency = _defaultConcurrency;
    final previousValidationMode = _defaultValidationMode;
    final previousForumFetchMode = _forumFetchMode;
    final previousGptAssisted = _defaultGptAssisted;
    _enabledSources = enabledSources.isEmpty
        ? <AiExposureSource>{AiExposureSource.manual}
        : Set<AiExposureSource>.of(enabledSources);
    _defaultConcurrency = concurrency.clamp(1, kAiExposureMaxScanConcurrency);
    _defaultValidationMode = validationMode;
    _forumFetchMode = forumFetchMode;
    if (gptAssisted != null) _defaultGptAssisted = gptAssisted;
    if (!await _persistPreferences()) {
      _enabledSources = previousSources;
      _defaultConcurrency = previousConcurrency;
      _defaultValidationMode = previousValidationMode;
      _forumFetchMode = previousForumFetchMode;
      _defaultGptAssisted = previousGptAssisted;
      _notify();
      return false;
    }
    _errorMessage = null;
    _notify();
    return true;
  }

  Future<bool> updateRuntimePreferences({
    required bool useBundledEngine,
    required String externalAddress,
  }) async {
    final previousUseBundledEngine = _useBundledEngine;
    final previousExternalAddress = _externalAddress;
    _useBundledEngine = useBundledEngine;
    final normalizedAddress = externalAddress.trim();
    if (normalizedAddress.isNotEmpty) _externalAddress = normalizedAddress;
    if (!await _persistPreferences()) {
      _useBundledEngine = previousUseBundledEngine;
      _externalAddress = previousExternalAddress;
      _notify();
      return false;
    }
    _errorMessage = null;
    _notify();
    return true;
  }

  Future<List<AiExposureLogEntry>> loadHistoryLogs(String jobId) async {
    final cached = _cachedHistoryLogs(jobId);
    if (cached != null) return cached;
    try {
      final logs = await _requireClient().logs(jobId);
      final cachedLogs = _cacheHistoryLogs(jobId, logs);
      _errorMessage = null;
      _notify();
      return cachedLogs;
    } catch (error, stack) {
      _errorMessage = _reportServicesFailure('读取扫描历史日志', error, stack);
      _notify();
      return const <AiExposureLogEntry>[];
    }
  }

  Future<void> _watchJob(String jobId, {bool reconnecting = false}) async {
    await _cancelEventSubscription();
    if (_disposed || _lifecycle == AiExposureServiceLifecycle.stopping) {
      throw StateError(_kServiceStoppingMessage);
    }
    final client = _requireClient();
    if (!reconnecting) _eventStreamReconnectAttempts = 0;
    final generation = ++_eventSubscriptionGeneration;
    final subscription = client
        .events(jobId)
        .listen(
          (event) {
            if (!_disposed && generation == _eventSubscriptionGeneration) {
              _eventStreamReconnectAttempts = 0;
              if (_errorMessage == _eventStreamErrorMessage) {
                _errorMessage = null;
              }
              _eventStreamErrorMessage = null;
              try {
                _handleEvent(jobId, event, generation: generation);
              } catch (error, stack) {
                _errorMessage = '扫描服务返回了无效的实时事件。';
                silentLog('services_controller', '解析扫描实时事件', error, stack);
                _notify();
              }
            }
          },
          onError: (Object error, StackTrace stack) {
            if (_disposed || generation != _eventSubscriptionGeneration) return;
            _eventStreamErrorMessage = _reportServicesFailure(
              '接收扫描实时事件',
              error,
              stack,
              fallback: '扫描实时事件连接异常。',
            );
            _errorMessage = _eventStreamErrorMessage;
            _notify();
          },
          onDone: () {
            if (!_disposed && generation == _eventSubscriptionGeneration) {
              unawaited(_handleEventStreamDone(jobId, generation: generation));
            }
          },
          cancelOnError: false,
        );
    _eventSubscription = subscription;
    if (_disposed ||
        _lifecycle == AiExposureServiceLifecycle.stopping ||
        !_isCurrentClient(client)) {
      await _cancelEventSubscription();
      throw StateError(_kServiceStoppingMessage);
    }
  }

  void _handleEvent(
    String jobId,
    Map<String, Object?> event, {
    required int generation,
  }) {
    switch (event['type']) {
      case 'progress':
        _progress = AiExposureProgress.fromJson(
          aiExposureJsonMap(event['progress']),
        );
        if (!(_progress?.isRunning ?? false)) {
          unawaited(_finishJobWatch(generation));
        }
      case 'result':
        final result = AiExposureResult.fromJson(
          aiExposureJsonMap(event['result']),
        );
        _results = List<AiExposureResult>.unmodifiable(<AiExposureResult>[
          result,
          ..._results.where((item) => item.id != result.id),
        ]);
      case 'log':
        _appendLog(AiExposureLogEntry.fromJson({...event, 'jobId': jobId}));
      default:
        silentLog(
          'services_controller',
          '处理扫描实时事件',
          StateError('未知事件类型: ${event['type']}'),
          StackTrace.current,
        );
    }
    _notify();
  }

  Future<void> _finishJobWatch(int generation) async {
    if (_disposed || generation != _eventSubscriptionGeneration) return;
    final completionGeneration = generation + 1;
    await _cancelEventSubscription();
    if (_disposed || completionGeneration != _eventSubscriptionGeneration) {
      return;
    }
    _eventStreamReconnectAttempts = 0;
    if (_errorMessage == _eventStreamErrorMessage) _errorMessage = null;
    _eventStreamErrorMessage = null;
    _detectEmptyCompletion();
    await _refreshHistoryAndResultsSafely();
  }

  /// 扫描任务进入终态但未发现任何候选目标时，给出明确提示。
  void _detectEmptyCompletion() {
    final progress = _progress;
    if (progress == null) return;
    if (progress.stage == 'completed' &&
        progress.discovered == 0 &&
        progress.candidates == 0) {
      final hasReaderFailure = _logs.any(
        (entry) => _kScanReaderFailureMarkers.any(
          (marker) => entry.message.contains(marker),
        ),
      );
      _errorMessage = hasReaderFailure
          ? '扫描完成但未发现目标，页面抓取失败。请检查系统代理设置后重试。'
          : '扫描完成但未发现目标，请确认数据源配置与授权范围。';
    }
  }

  Future<void> _handleEventStreamDone(
    String jobId, {
    required int generation,
  }) async {
    if (_disposed ||
        _client == null ||
        generation != _eventSubscriptionGeneration) {
      return;
    }
    try {
      _progress = await _requireClient().progress(jobId);
      if (_disposed || generation != _eventSubscriptionGeneration) return;
      if (!(_progress?.isRunning ?? false)) {
        await _finishJobWatch(generation);
        return;
      } else {
        if (_eventStreamReconnectAttempts >= _kEventStreamReconnectLimit) {
          // 实时事件持续中断时不再放弃，转入低频轮询兜底直至任务终态，
          // 避免 _progress 永远停在"运行中"导致工作台卡死、无法新建扫描。
          _eventStreamErrorMessage = '扫描实时事件连接持续中断，已转入轮询同步任务状态。';
          _errorMessage = _eventStreamErrorMessage;
          _notify();
          await _cancelEventSubscription();
          await _awaitScanTermination(
            jobId,
            maxAttempts: _kEventStreamPollFallbackMaxAttempts,
            interval: _kEventStreamPollFallbackInterval,
          );
          return;
        } else {
          _eventStreamReconnectAttempts += 1;
          await Future<void>.delayed(
            Duration(
              milliseconds:
                  _kEventStreamReconnectBaseDelay.inMilliseconds *
                  _eventStreamReconnectAttempts,
            ),
          );
          if (_disposed ||
              _client == null ||
              generation != _eventSubscriptionGeneration) {
            return;
          }
          await _watchJob(jobId, reconnecting: true);
          return;
        }
      }
    } catch (error, stack) {
      if (_disposed ||
          _client == null ||
          generation != _eventSubscriptionGeneration) {
        return;
      }
      _eventStreamErrorMessage = '同步扫描任务状态失败。';
      _errorMessage = _eventStreamErrorMessage;
      silentLog('services_controller', '同步扫描任务最终状态', error, stack);
    }
    if (!_disposed && generation == _eventSubscriptionGeneration) _notify();
  }

  Future<void> _refreshHistoryAndResults() async {
    final client = _client;
    if (client == null) return;
    final values = await Future.wait<Object>(<Future<Object>>[
      client.history(),
      client.results(),
    ]);
    if (!_isCurrentClient(client)) return;
    _setHistory(values[0] as List<AiExposureHistoryEntry>);
    _results = List<AiExposureResult>.unmodifiable(
      values[1] as List<AiExposureResult>,
    );
  }

  Future<void> _refreshHistoryAndResultsSafely() async {
    try {
      await _refreshHistoryAndResults();
    } catch (error, stack) {
      if (_disposed) return;
      _errorMessage = _reportServicesFailure('刷新扫描历史与结果', error, stack);
    } finally {
      _notify();
    }
  }

  void _appendRuntimeLog(String message) {
    _appendLog(
      AiExposureLogEntry(
        level: 'runtime',
        message: message,
        at: DateTime.now(),
      ),
    );
    _notify();
  }

  void _appendLog(AiExposureLogEntry entry) {
    if (entry.message.trim().isEmpty) return;
    final id = entry.id;
    if (id != null && id.isNotEmpty) {
      final index = _logs.indexWhere((item) => item.id == id);
      if (index >= 0) {
        _logs[index] = entry;
        return;
      }
    }
    _logs.add(entry);
    if (_logs.length > _kAiExposureMaxLogs) {
      _logs.removeRange(0, _logs.length - _kAiExposureMaxLogs);
    }
  }

  void _handleRuntimeExit(int exitCode) {
    if (_lifecycle == AiExposureServiceLifecycle.stopping || _disposed) return;
    _proxyStatisticsTimer?.cancel();
    _proxyStatisticsTimer = null;
    _managedDependencyListenerSyncQueue.discardPending();
    _systemProxySyncPending = false;
    _scanBusy = false;
    _logRefreshBusy = false;
    unawaited(_cancelEventSubscription());
    _eventStreamReconnectAttempts = 0;
    if (_errorMessage == _eventStreamErrorMessage) _errorMessage = null;
    _eventStreamErrorMessage = null;
    _lifecycle = exitCode == 0
        ? AiExposureServiceLifecycle.stopped
        : AiExposureServiceLifecycle.error;
    _health = null;
    _progress = null;
    _aiExtractorStatus = null;
    _dependencyStatus = null;
    _dependencyDataOverview = const <String, Object?>{};
    _dependencyTelemetryHistory.clear();
    _dependencyDataOverviewError = null;
    _proxyStatus = null;
    _errorMessage = exitCode == 0 ? null : '扫描引擎异常退出：$exitCode。';
    _notify();
  }

  bool _isCurrentClient(AiJunglerClient client) =>
      !_disposed && identical(_client, client);

  AiJunglerClient _requireClient() {
    final client = _client;
    if (client == null) throw StateError('扫描服务尚未启动。');
    return client;
  }

  Future<void> _configureAiExtractor(bool enabled) async {
    if (!enabled) return;
    final model = _selectedAiModelProvider?.call();
    if (model == null || model.apiDialect != AiApiDialect.openAiCompat) {
      throw StateError('GPT 辅助提取需要在全局设置中选择 OpenAI Compatible 模型。');
    }
    final endpoint = const AiEndpointRouter().resolve(
      model,
      AiApiFamily.chatCompletions,
    );
    final url = AiOperationHttp.uriWithExtraQuery(
      endpoint.url,
      model,
      AiApiFamily.chatCompletions,
    );
    final headers = AiOperationHttp.buildHeaders(
      model: model,
      endpointHeaders: endpoint.headers,
      family: AiApiFamily.chatCompletions,
    );
    final client = _requireClient();
    await client.configureAiExtractor(
      endpoint: url.toString(),
      model: model.resolveOperationModelId(AiApiFamily.chatCompletions),
      headers: headers,
    );
    _aiExtractorStatus = await client.aiExtractorStatus();
  }

  Future<bool> _persistPreferences() async {
    try {
      await _preferencesStore.save(
        AiExposurePreferences(
          enabledSources: _enabledSources,
          defaultConcurrency: _defaultConcurrency,
          defaultValidationMode: _defaultValidationMode,
          forumFetchMode: _forumFetchMode,
          defaultGptAssisted: _defaultGptAssisted,
          useBundledEngine: _useBundledEngine,
          externalAddress: _externalAddress,
          postgresqlEnabled: _postgresqlEnabled,
          redisEnabled: _redisEnabled,
          proxyConfiguration: _proxyConfiguration,
        ),
      );
      return true;
    } catch (error, stack) {
      _errorMessage = _reportServicesFailure('保存扫描服务设置', error, stack);
      return false;
    }
  }

  Future<void> _restoreSourceCredentials(AiJunglerClient client) async {
    try {
      final credentials = await _preferencesStore.loadSourceCredentials();
      if (credentials.isEmpty) return;
      await client.updateSourceCredentials(
        githubToken: credentials['githubToken'],
        giteeToken: credentials['giteeToken'],
        gitcodeToken: credentials['gitcodeToken'],
        fofaEmail: credentials['fofaEmail'],
        fofaKey: credentials['fofaKey'],
        shodanKey: credentials['shodanKey'],
      );
      _sourceStatus = Map<String, bool>.unmodifiable(
        await client.sourceStatus(),
      );
    } catch (error, stack) {
      _reportServicesFailure('恢复扫描数据源凭证', error, stack);
    }
  }

  Map<String, Object?>? _playwrightDependencyPayload() {
    if (!ownsProcess) return null;
    final plugins = _pluginServiceController;
    final node = plugins?.pluginById(PluginCatalogIds.nodejs);
    final playwright = plugins?.pluginById(PluginCatalogIds.playwright);
    final nodeExecutable = node?.installPath?.trim() ?? '';
    final packageDirectory =
        '${playwright?.metadata['installation_target'] ?? ''}'.trim();
    final browsersPath = '${playwright?.metadata['data_directory'] ?? ''}'
        .trim();
    final enabled =
        node?.isInstalled == true &&
        playwright?.isInstalled == true &&
        nodeExecutable.isNotEmpty &&
        packageDirectory.isNotEmpty;
    return <String, Object?>{
      'enabled': enabled,
      if (enabled) 'nodeExecutable': nodeExecutable,
      if (enabled) 'packageDirectory': packageDirectory,
      if (enabled && browsersPath.isNotEmpty) 'browsersPath': browsersPath,
      if (enabled) 'version': playwright?.installedVersion ?? '',
    };
  }

  Future<bool> _persistProxySamples(
    List<AiExposureProxyEndpoint> endpoints,
  ) async {
    try {
      await _preferencesStore.saveProxySamples(endpoints);
      return true;
    } catch (error, stack) {
      _errorMessage = _reportServicesFailure('保存代理巡检样本', error, stack);
      return false;
    }
  }

  Future<void> _cancelEventSubscription() async {
    _eventSubscriptionGeneration++;
    final subscription = _eventSubscription;
    _eventSubscription = null;
    await cancelStreamSubscriptionBounded<Map<String, Object?>>(
      subscription,
      onError: (error, stack) =>
          silentLog('services_controller', '取消扫描实时事件订阅', error, stack),
    );
  }

  Future<void> _drainRuntimeOperations() async {
    _proxyStatisticsTimer?.cancel();
    _proxyStatisticsTimer = null;
    _managedDependencyListenerSyncQueue.discardPending();
    _systemProxySyncPending = false;
    await _cancelEventSubscription();
    await runAsyncCleanupBounded(
      () => Future.wait<void>(<Future<void>>[
        _syncProxyStatistics(),
        _managedDependencyListenerSyncQueue.idle,
        _managedDependencyUpdateQueue.idle,
        _proxyRuntimeUpdateQueue.idle,
      ]),
      timeout: _kRuntimeOperationDrainTimeout,
      onError: (error, stack) =>
          silentLog('services_controller', '等待扫描运行操作结束', error, stack),
    );
  }

  Future<void> shutdown() => _shutdownOnce.run(_shutdown);

  @override
  void dispose() {
    if (_notifierDisposed) return;
    if (!_disposed) {
      unawaited(
        shutdown().then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) =>
              silentLog('services_controller', '释放扫描服务控制器', error, stack),
        ),
      );
    }
    _notifierDisposed = true;
    super.dispose();
  }

  Future<void> _shutdown() async {
    if (_disposed) return;
    _busy = true;
    _proxyInspectionGeneration++;
    _proxyInspectionScheduleGeneration++;
    _proxyInspectionCancelRequested = true;
    _proxyInspectionCancellation?.cancel();
    _proxyInspectionTimer?.cancel();
    _proxyInspectionTimer = null;
    _lifecycle = AiExposureServiceLifecycle.stopping;
    await _drainRuntimeOperations();
    _disposed = true;
    try {
      final pluginController = _pluginServiceController;
      final pluginListener = _pluginStateListener;
      if (pluginController != null && pluginListener != null) {
        pluginController.removeListener(pluginListener);
      }
      SystemProxyResolver.instance.revision.removeListener(
        _handleSystemProxyRevision,
      );
      _pluginStateListener = null;
      _pluginServiceController = null;
      await Future.wait<bool>(<Future<bool>>[
        cancelStreamSubscriptionBounded<String>(
          _runtimeLogSubscription,
          onError: (error, stack) =>
              silentLog('services_controller', '取消扫描运行日志订阅', error, stack),
        ),
        cancelStreamSubscriptionBounded<int>(
          _runtimeExitSubscription,
          onError: (error, stack) =>
              silentLog('services_controller', '取消扫描退出事件订阅', error, stack),
        ),
      ]);
      _runtimeLogSubscription = null;
      _runtimeExitSubscription = null;
      await _runtime.dispose();
    } finally {
      dispose();
    }
  }

  void _notify() {
    if (!_disposed && !_notifierDisposed) notifyListeners();
  }
}
