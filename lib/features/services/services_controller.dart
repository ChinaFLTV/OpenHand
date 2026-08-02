import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/support/silent_log.dart';
import '../ai/index.dart';
import '../plugin_service/index.dart';
import 'data/ai_exposure_preferences_store.dart';
import 'model/ai_exposure_models.dart';
import 'service/ai_exposure_proxy_probe.dart';
import 'service/ai_jungler_client.dart';
import 'service/ai_jungler_runtime.dart';

const int _kAiExposureMaxLogs = 5000;
const int _kMaxProxyInspectionConcurrency = 32;
const Duration _kProxyStatisticsSyncInterval = Duration(seconds: 5);

class ServicesController extends ChangeNotifier {
  ServicesController({
    AiJunglerRuntime? runtime,
    AiExposurePreferencesStore? preferencesStore,
    AiExposurePreferences? initialPreferences,
  }) : _runtime = runtime ?? AiJunglerRuntime(),
       _preferencesStore = preferencesStore ?? AiExposurePreferencesStore() {
    final preferences = initialPreferences ?? AiExposurePreferences.defaults();
    _enabledSources = Set<AiExposureSource>.of(preferences.enabledSources);
    _defaultConcurrency = preferences.defaultConcurrency;
    _defaultValidationMode = preferences.defaultValidationMode;
    _defaultGptAssisted = preferences.defaultGptAssisted;
    _useBundledEngine = preferences.useBundledEngine;
    _externalAddress = preferences.externalAddress;
    _postgresqlEnabled = preferences.postgresqlEnabled;
    _redisEnabled = preferences.redisEnabled;
    _proxyConfiguration = preferences.proxyConfiguration;
    _runtimeLogSubscription = _runtime.logs.listen(_appendRuntimeLog);
    _runtimeExitSubscription = _runtime.exits.listen(_handleRuntimeExit);
    _scheduleProxyInspection();
  }

  final AiJunglerRuntime _runtime;
  final AiExposurePreferencesStore _preferencesStore;
  final AiExposureProxyProbe _proxyProbe = const AiExposureProxyProbe();
  AiModelConfig? Function()? _selectedAiModelProvider;
  PluginServiceController? _pluginServiceController;
  VoidCallback? _pluginOperationListener;
  StreamSubscription<String>? _runtimeLogSubscription;
  StreamSubscription<int>? _runtimeExitSubscription;
  StreamSubscription<Map<String, Object?>>? _eventSubscription;
  AiExposureServiceLifecycle _lifecycle = AiExposureServiceLifecycle.stopped;
  AiExposureHealth? _health;
  AiExposureProgress? _progress;
  List<AiExposureHistoryEntry> _history = const <AiExposureHistoryEntry>[];
  List<AiExposureResult> _results = const <AiExposureResult>[];
  List<AiExposureScanRule> _rules = const <AiExposureScanRule>[];
  List<AiExposureQuota> _quotas = const <AiExposureQuota>[];
  AiExposureAiExtractorStatus? _aiExtractorStatus;
  AiExposureDependencyStatus? _dependencyStatus;
  AiExposureProxyStatus? _proxyStatus;
  Map<String, bool> _sourceStatus = const <String, bool>{};
  final Map<String, List<AiExposureLogEntry>> _historyLogs =
      <String, List<AiExposureLogEntry>>{};
  late Set<AiExposureSource> _enabledSources;
  late int _defaultConcurrency;
  late AiExposureValidationMode _defaultValidationMode;
  late bool _defaultGptAssisted;
  late bool _useBundledEngine;
  late String _externalAddress;
  late bool _postgresqlEnabled;
  late bool _redisEnabled;
  AiExposureProxyConfiguration _proxyConfiguration =
      AiExposureProxyConfiguration.defaults();
  Timer? _proxyInspectionTimer;
  Timer? _proxyStatisticsTimer;
  bool _proxyInspectionBusy = false;
  bool _proxyInspectionRunning = false;
  int _proxyInspectionGeneration = 0;
  bool _proxyStatisticsSyncing = false;
  final List<AiExposureLogEntry> _logs = <AiExposureLogEntry>[];
  String? _errorMessage;
  bool _busy = false;
  bool _scanBusy = false;
  bool _logRefreshBusy = false;
  bool _disposed = false;

  AiExposureServiceLifecycle get lifecycle => _lifecycle;
  AiExposureHealth? get health => _health;
  AiExposureProgress? get progress => _progress;
  List<AiExposureHistoryEntry> get history => _history;
  List<AiExposureResult> get results => _results;
  List<AiExposureScanRule> get rules => _rules;
  List<AiExposureQuota> get quotas => _quotas;
  AiExposureAiExtractorStatus? get aiExtractorStatus => _aiExtractorStatus;
  AiExposureDependencyStatus? get dependencyStatus => _dependencyStatus;
  AiExposureProxyStatus? get proxyStatus => _proxyStatus;
  AiExposureProxyConfiguration get proxyConfiguration => _proxyConfiguration;
  Map<String, bool> get sourceStatus => _sourceStatus;
  Set<AiExposureSource> get enabledSources => Set.unmodifiable(_enabledSources);
  int get defaultConcurrency => _defaultConcurrency;
  AiExposureValidationMode get defaultValidationMode => _defaultValidationMode;
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
  bool get busy => _busy;
  bool get scanBusy => _scanBusy;
  bool get isRunning => _lifecycle == AiExposureServiceLifecycle.running;
  bool get hasActiveScan => _progress?.isRunning ?? false;
  bool get proxyInspectionBusy => _proxyInspectionBusy;
  bool get ownsProcess => _runtime.ownsProcess;
  AiJunglerClient? get _client => _runtime.client;

  void attachSelectedAiModelProvider(AiModelConfig? Function() provider) {
    _selectedAiModelProvider = provider;
  }

  /// 让服务依赖与插件中心共用同一个状态源和生命周期结果。
  void attachPluginServiceController(PluginServiceController controller) {
    if (identical(_pluginServiceController, controller)) return;
    final previous = _pluginServiceController;
    final listener = _pluginOperationListener;
    if (previous != null && listener != null) {
      previous.operationSuccessSignal.removeListener(listener);
    }
    _pluginServiceController = controller;
    _pluginOperationListener = _handlePluginOperationSuccess;
    controller.operationSuccessSignal.addListener(_pluginOperationListener!);
  }

  void _handlePluginOperationSuccess() {
    final pluginId = _pluginServiceController?.lastSuccessfulPluginId;
    if (_disposed ||
        (pluginId != PluginCatalogIds.postgresql &&
            pluginId != PluginCatalogIds.redis)) {
      return;
    }
    unawaited(_syncManagedDependencies());
  }

  Future<void> startService() async {
    if (_busy || isRunning) return;
    if (!_useBundledEngine) {
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
      await client.updateProxy(_proxyConfiguration);
      await _syncManagedDependencies();
      _lifecycle = AiExposureServiceLifecycle.running;
      _appendLog(
        AiExposureLogEntry(
          level: 'info',
          message: 'AI 基础设施扫描服务已启动。',
          at: DateTime.now(),
        ),
      );
      await refreshData();
      _scheduleProxyStatisticsSync();
    } catch (error, stack) {
      _lifecycle = _runtime.client == null
          ? AiExposureServiceLifecycle.error
          : AiExposureServiceLifecycle.running;
      _errorMessage = '$error';
      silentLog('services_controller', '启动扫描服务', error, stack);
    } finally {
      _busy = false;
      _notify();
    }
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
      final uri = Uri.parse(address.trim());
      final client = await _runtime.connectExternal(
        address: uri,
        accessToken: accessToken,
      );
      _health = await client.health();
      await client.updateProxy(_proxyConfiguration);
      await _syncManagedDependencies();
      _lifecycle = AiExposureServiceLifecycle.running;
      await refreshData();
      _scheduleProxyStatisticsSync();
      return true;
    } catch (error, stack) {
      _lifecycle = _runtime.client == null
          ? AiExposureServiceLifecycle.error
          : AiExposureServiceLifecycle.running;
      _errorMessage = '$error';
      silentLog('services_controller', '连接外部扫描服务', error, stack);
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> stopService() async {
    if (_busy || _lifecycle == AiExposureServiceLifecycle.stopped) return;
    _busy = true;
    _lifecycle = AiExposureServiceLifecycle.stopping;
    _notify();
    try {
      await _syncProxyStatistics();
      _proxyStatisticsTimer?.cancel();
      _proxyStatisticsTimer = null;
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      await _runtime.stop();
      _lifecycle = AiExposureServiceLifecycle.stopped;
      _health = null;
      _progress = null;
      _aiExtractorStatus = null;
      _dependencyStatus = null;
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
      _errorMessage = '$error';
      silentLog('services_controller', '停止扫描服务', error, stack);
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> refreshData() async {
    final client = _requireClient();
    try {
      final values = await Future.wait<Object>(<Future<Object>>[
        client.health(),
        client.history(),
        client.results(),
        client.rules(),
        client.sourceStatus(),
        client.aiExtractorStatus(),
        client.dependencyStatus(),
        client.proxyStatus(),
      ]);
      _health = values[0] as AiExposureHealth;
      _history = values[1] as List<AiExposureHistoryEntry>;
      _results = values[2] as List<AiExposureResult>;
      _rules = values[3] as List<AiExposureScanRule>;
      _sourceStatus = values[4] as Map<String, bool>;
      _aiExtractorStatus = values[5] as AiExposureAiExtractorStatus;
      _dependencyStatus = values[6] as AiExposureDependencyStatus;
      _proxyStatus = values[7] as AiExposureProxyStatus;
      await _mergeProxyStatistics(_proxyStatus!);
      _errorMessage = null;
    } catch (error, stack) {
      _errorMessage = '$error';
      silentLog('services_controller', '刷新扫描服务数据', error, stack);
    }
    _notify();
  }

  Future<void> refreshServiceStatus() async {
    final client = _requireClient();
    try {
      final values = await Future.wait<Object>(<Future<Object>>[
        client.health(),
        client.quotas(),
        client.sourceStatus(),
        client.dependencyStatus(),
        client.proxyStatus(),
      ]);
      _health = values[0] as AiExposureHealth;
      _quotas = values[1] as List<AiExposureQuota>;
      _sourceStatus = values[2] as Map<String, bool>;
      _dependencyStatus = values[3] as AiExposureDependencyStatus;
      _proxyStatus = values[4] as AiExposureProxyStatus;
      await _mergeProxyStatistics(_proxyStatus!);
      _errorMessage = null;
    } catch (error, stack) {
      _errorMessage = '$error';
      silentLog('services_controller', '刷新扫描服务状态', error, stack);
    }
    _notify();
  }

  Future<void> startScan(AiExposureScanRequest request) async {
    if (_scanBusy || hasActiveScan) return;
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
      await _refreshHistoryAndResults();
    } catch (error, stack) {
      _errorMessage = '$error';
      silentLog('services_controller', '创建扫描任务', error, stack);
    } finally {
      _scanBusy = false;
      _notify();
    }
  }

  Future<void> stopScan() async {
    final jobId = _progress?.jobId;
    if (jobId == null || jobId.isEmpty || !hasActiveScan) return;
    try {
      await _requireClient().stopJob(jobId);
    } catch (error, stack) {
      _errorMessage = '$error';
      silentLog('services_controller', '停止扫描任务', error, stack);
    }
    _notify();
  }

  Future<void> resumeHistory(String jobId) async {
    if (_scanBusy || hasActiveScan) return;
    _scanBusy = true;
    _errorMessage = null;
    _notify();
    try {
      final resumedId = await _requireClient().resumeJob(jobId);
      _progress = await _requireClient().progress(resumedId);
      _logs.clear();
      await _watchJob(resumedId);
    } catch (error, stack) {
      _errorMessage = '$error';
      silentLog('services_controller', '恢复扫描任务', error, stack);
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
      _errorMessage = '$error';
      silentLog('services_controller', '删除扫描历史', error, stack);
    }
    _notify();
  }

  Future<void> saveRules(List<AiExposureScanRule> rules) async {
    try {
      await _requireClient().saveRules(rules);
      _rules = await _requireClient().rules();
      _errorMessage = null;
    } catch (error, stack) {
      _errorMessage = '$error';
      silentLog('services_controller', '保存扫描规则', error, stack);
    }
    _notify();
  }

  Future<void> updateSourceCredentials({
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
      _sourceStatus = await client.sourceStatus();
      _errorMessage = null;
    } catch (error, stack) {
      _errorMessage = '$error';
      silentLog('services_controller', '更新扫描数据源凭证', error, stack);
    }
    _notify();
  }

  Future<bool> updateProxyConfiguration(
    AiExposureProxyConfiguration configuration,
  ) => _applyProxyConfiguration(
    configuration,
    logMessage: configuration.enabled
        ? '代理池已启用，共 ${configuration.activeEndpoints.length} 个可用节点。'
        : '代理池已停用，网络请求将直接连接。',
  );

  Future<bool> updateProxyEndpoints(List<AiExposureProxyEndpoint> endpoints) {
    final activeCount = endpoints.where((endpoint) => endpoint.enabled).length;
    final current = _proxyConfiguration;
    return _applyProxyConfiguration(
      current.copyWith(
        enabled: current.enabled && activeCount > 0,
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
    try {
      if (configuration.endpoints.length > 10000) {
        throw const FormatException('代理池最多支持 10000 个代理。');
      }
      if ((configuration.enabled || configuration.inspectionEnabled) &&
          configuration.activeEndpoints.isEmpty) {
        throw const FormatException('启用代理或巡检前至少启用一个代理节点。');
      }
      final client = _client;
      if (client != null) {
        await client.updateProxy(configuration);
        _proxyStatus = await client.proxyStatus();
      }
      _proxyConfiguration = configuration;
      if (_proxyStatus != null) {
        await _mergeProxyStatistics(_proxyStatus!);
      }
      _scheduleProxyInspection();
      _scheduleProxyStatisticsSync();
      await _persistPreferences();
      _errorMessage = null;
      _appendLog(
        AiExposureLogEntry(
          level: 'info',
          message: logMessage,
          at: DateTime.now(),
        ),
      );
      _notify();
      return true;
    } catch (error, stack) {
      _errorMessage = '$error';
      silentLog('services_controller', '更新扫描网络代理', error, stack);
      _notify();
      return false;
    }
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
    for (final entry in samples.entries) {
      final index = indexes[entry.key];
      if (index == null) continue;
      endpoints[index] = endpoints[index].withSample(entry.value);
      changed = true;
    }
    if (!changed) return;
    _proxyConfiguration = _proxyConfiguration.copyWith(endpoints: endpoints);
    await _persistPreferences();
    _notify();
  }

  Future<void> inspectAllProxies() async {
    if (_proxyInspectionBusy || _proxyInspectionRunning || _disposed) return;
    final endpoints = _proxyConfiguration.activeEndpoints;
    if (endpoints.isEmpty) return;
    final generation = ++_proxyInspectionGeneration;
    _proxyInspectionRunning = true;
    _proxyInspectionBusy = true;
    _notify();
    final inspected = <String, AiExposureProxyProbeSample>{};
    var cursor = 0;
    final concurrency = _proxyConfiguration.inspectionConcurrency.clamp(
      1,
      _kMaxProxyInspectionConcurrency,
    );
    Future<void> worker() async {
      while (!_disposed && generation == _proxyInspectionGeneration) {
        final index = cursor++;
        if (index >= endpoints.length) return;
        final endpoint = endpoints[index];
        inspected[endpoint.url] = await _proxyProbe.inspect(endpoint);
      }
    }

    try {
      await Future.wait<void>(
        List<Future<void>>.generate(
          endpoints.length.clamp(1, concurrency),
          (_) => worker(),
        ),
      );
      if (_disposed || generation != _proxyInspectionGeneration) return;
      final updatedEndpoints = List<AiExposureProxyEndpoint>.of(
        _proxyConfiguration.endpoints,
      );
      final indexes = <String, int>{
        for (var index = 0; index < updatedEndpoints.length; index++)
          updatedEndpoints[index].url: index,
      };
      for (final entry in inspected.entries) {
        final index = indexes[entry.key];
        if (index != null) {
          updatedEndpoints[index] = updatedEndpoints[index].withSample(
            entry.value,
          );
        }
      }
      _proxyConfiguration = _proxyConfiguration.copyWith(
        endpoints: updatedEndpoints,
      );
      await _persistPreferences();
      final healthy = inspected.values
          .where((sample) => sample.reachable)
          .length;
      _appendLog(
        AiExposureLogEntry(
          level: healthy == inspected.length ? 'info' : 'warning',
          message: '代理巡检完成：${inspected.length} 个节点，$healthy 个可连通。',
          at: DateTime.now(),
        ),
      );
    } catch (error, stack) {
      _errorMessage = '$error';
      silentLog('services_controller', '巡检代理节点', error, stack);
    } finally {
      _proxyInspectionRunning = false;
      if (!_disposed) {
        _proxyInspectionBusy = false;
        _notify();
      }
    }
  }

  void _scheduleProxyInspection() {
    _proxyInspectionGeneration++;
    _proxyInspectionTimer?.cancel();
    _proxyInspectionTimer = null;
    final configuration = _proxyConfiguration;
    if (!configuration.inspectionEnabled ||
        configuration.activeEndpoints.isEmpty) {
      return;
    }
    _proxyInspectionTimer = Timer.periodic(
      Duration(minutes: configuration.inspectionIntervalMinutes.clamp(1, 1440)),
      (_) => unawaited(inspectAllProxies()),
    );
  }

  void _scheduleProxyStatisticsSync() {
    _proxyStatisticsTimer?.cancel();
    _proxyStatisticsTimer = null;
    if (_client == null || !_proxyConfiguration.enabled) return;
    _proxyStatisticsTimer = Timer.periodic(
      _kProxyStatisticsSyncInterval,
      (_) => unawaited(_syncProxyStatistics(notify: true)),
    );
  }

  Future<void> _syncProxyStatistics({bool notify = false}) async {
    if (_proxyStatisticsSyncing || _client == null || _disposed) return;
    _proxyStatisticsSyncing = true;
    try {
      final status = await _client!.proxyStatus();
      final changed = await _mergeProxyStatistics(status);
      _proxyStatus = status;
      if (notify && changed) _notify();
    } catch (error, stack) {
      silentLog('services_controller', '同步代理使用统计', error, stack);
    } finally {
      _proxyStatisticsSyncing = false;
    }
  }

  Future<bool> _mergeProxyStatistics(AiExposureProxyStatus status) async {
    final byId = <String, AiExposureProxyEndpointStatus>{
      for (final item in status.endpoints) item.id: item,
    };
    var changed = false;
    var runtimeChanged = false;
    final changedEndpoints = <AiExposureProxyEndpoint>[];
    final endpoints = _proxyConfiguration.endpoints
        .map((endpoint) {
          final runtime = byId[endpoint.runtimeId];
          if (runtime == null) return endpoint;
          final current = endpoint.statistics;
          final next = runtime.statistics;
          final statisticsChanged =
              current.requests != next.requests ||
              current.successes != next.successes ||
              current.failures != next.failures ||
              current.timeouts != next.timeouts ||
              current.totalResponseTimeMs != next.totalResponseTimeMs ||
              current.minResponseTimeMs != next.minResponseTimeMs ||
              current.maxResponseTimeMs != next.maxResponseTimeMs ||
              current.status2xx != next.status2xx ||
              current.status3xx != next.status3xx ||
              current.status4xx != next.status4xx ||
              current.status5xx != next.status5xx ||
              current.consecutiveFailures != next.consecutiveFailures ||
              current.lastUsedAt != next.lastUsedAt ||
              current.lastSuccessAt != next.lastSuccessAt ||
              current.lastFailureAt != next.lastFailureAt ||
              current.lastError != next.lastError ||
              current.recentRequests.length != next.recentRequests.length;
          final updated = endpoint.copyWith(statistics: next);
          if (statisticsChanged) {
            changed = true;
            changedEndpoints.add(updated);
          }
          if (current.inFlight != next.inFlight) runtimeChanged = true;
          return updated;
        })
        .toList(growable: false);
    if (changed) {
      await _preferencesStore.saveProxyStatistics(changedEndpoints);
    }
    if (changed || runtimeChanged) {
      _proxyConfiguration = _proxyConfiguration.copyWith(endpoints: endpoints);
    }
    return changed || runtimeChanged;
  }

  Future<void> updateProxyIdentity(
    String url,
    AiExposureProxyIdentity identity,
  ) async {
    final index = _proxyConfiguration.endpoints.indexWhere(
      (endpoint) => endpoint.url == url,
    );
    if (index < 0) return;
    final endpoints = List<AiExposureProxyEndpoint>.of(
      _proxyConfiguration.endpoints,
    );
    endpoints[index] = endpoints[index].copyWith(identity: identity);
    _proxyConfiguration = _proxyConfiguration.copyWith(endpoints: endpoints);
    await _persistPreferences();
    _notify();
  }

  Future<void> refreshServiceLogs() async {
    if (_logRefreshBusy || _client == null) return;
    _logRefreshBusy = true;
    try {
      final recent = _history.take(20).toList(growable: false);
      final batches = await Future.wait(
        recent.map((entry) async {
          final cached = _historyLogs[entry.id];
          if (cached != null) return cached;
          final loaded = await _requireClient().logs(entry.id, limit: 500);
          _historyLogs[entry.id] = loaded;
          return loaded;
        }),
      );
      final merged = <AiExposureLogEntry>[
        ..._logs,
        ...batches.expand((item) => item),
      ];
      final unique = <String, AiExposureLogEntry>{};
      for (final entry in merged) {
        unique['${entry.jobId}|${entry.at.toIso8601String()}|${entry.level}|${entry.message}'] =
            entry;
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
      _errorMessage = '$error';
      silentLog('services_controller', '刷新扫描服务日志', error, stack);
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
      _errorMessage = '$error';
      silentLog('services_controller', '更新扫描运行依赖', error, stack);
      _notify();
      return false;
    }
  }

  /// 保存结构化的运行依赖选择，并使用 OpenHand 托管实例的默认连接地址。
  Future<bool> updateManagedDependencyPreferences({
    required bool postgresqlEnabled,
    required bool redisEnabled,
  }) async {
    _postgresqlEnabled = postgresqlEnabled;
    _redisEnabled = redisEnabled;
    await _persistPreferences();
    final updated = await _syncManagedDependencies();
    _notify();
    return updated;
  }

  Future<bool> _syncManagedDependencies() async {
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
    try {
      await client.updateDependencies(
        postgresqlUrl: postgresqlUrl,
        redisUrl: redisUrl,
      );
      _dependencyStatus = await client.dependencyStatus();
      _errorMessage = null;
      _notify();
      return true;
    } catch (error, stack) {
      _errorMessage = '$error';
      silentLog('services_controller', '同步托管运行依赖', error, stack);
      _notify();
      return false;
    }
  }

  Future<void> updateScanPreferences({
    required Set<AiExposureSource> enabledSources,
    required int concurrency,
    required AiExposureValidationMode validationMode,
    bool? gptAssisted,
  }) async {
    _enabledSources = enabledSources.isEmpty
        ? <AiExposureSource>{AiExposureSource.manual}
        : Set<AiExposureSource>.of(enabledSources);
    _defaultConcurrency = concurrency.clamp(1, 128);
    _defaultValidationMode = validationMode;
    if (gptAssisted != null) _defaultGptAssisted = gptAssisted;
    await _persistPreferences();
    _notify();
  }

  Future<void> updateRuntimePreferences({
    required bool useBundledEngine,
    required String externalAddress,
  }) async {
    _useBundledEngine = useBundledEngine;
    final normalizedAddress = externalAddress.trim();
    if (normalizedAddress.isNotEmpty) _externalAddress = normalizedAddress;
    await _persistPreferences();
    _notify();
  }

  Future<List<AiExposureLogEntry>> loadHistoryLogs(String jobId) async {
    final cached = _historyLogs[jobId];
    if (cached != null) return cached;
    try {
      final logs = await _requireClient().logs(jobId);
      _historyLogs[jobId] = logs;
      _errorMessage = null;
      _notify();
      return logs;
    } catch (error, stack) {
      _errorMessage = '$error';
      silentLog('services_controller', '读取扫描历史日志', error, stack);
      _notify();
      return const <AiExposureLogEntry>[];
    }
  }

  Future<void> _watchJob(String jobId) async {
    await _eventSubscription?.cancel();
    _eventSubscription = _requireClient()
        .events(jobId)
        .listen(
          (event) => _handleEvent(jobId, event),
          onError: (Object error, StackTrace stack) {
            _errorMessage = '$error';
            silentLog('services_controller', '接收扫描实时事件', error, stack);
            _notify();
          },
          onDone: () => unawaited(_handleEventStreamDone(jobId)),
          cancelOnError: false,
        );
  }

  void _handleEvent(String jobId, Map<String, Object?> event) {
    switch (event['type']) {
      case 'progress':
        _progress = AiExposureProgress.fromJson(
          aiExposureJsonMap(event['progress']),
        );
        if (!(_progress?.isRunning ?? false)) {
          unawaited(_refreshHistoryAndResults());
        }
      case 'result':
        final result = AiExposureResult.fromJson(
          aiExposureJsonMap(event['result']),
        );
        _results = <AiExposureResult>[
          result,
          ..._results.where((item) => item.id != result.id),
        ];
      case 'log':
        _appendLog(
          AiExposureLogEntry(
            jobId: jobId,
            level: event['level'] as String? ?? 'info',
            message: event['message'] as String? ?? '',
            at:
                DateTime.tryParse(event['at'] as String? ?? '') ??
                DateTime.now(),
          ),
        );
    }
    _notify();
  }

  Future<void> _handleEventStreamDone(String jobId) async {
    if (_disposed || _client == null) return;
    try {
      _progress = await _requireClient().progress(jobId);
      await _refreshHistoryAndResults();
    } catch (error, stack) {
      silentLog('services_controller', '同步扫描任务最终状态', error, stack);
    }
    _notify();
  }

  Future<void> _refreshHistoryAndResults() async {
    final client = _client;
    if (client == null) return;
    final values = await Future.wait<Object>(<Future<Object>>[
      client.history(),
      client.results(),
    ]);
    _history = values[0] as List<AiExposureHistoryEntry>;
    _results = values[1] as List<AiExposureResult>;
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
    _logs.add(entry);
    if (_logs.length > _kAiExposureMaxLogs) {
      _logs.removeRange(0, _logs.length - _kAiExposureMaxLogs);
    }
  }

  void _handleRuntimeExit(int exitCode) {
    if (_lifecycle == AiExposureServiceLifecycle.stopping || _disposed) return;
    _lifecycle = exitCode == 0
        ? AiExposureServiceLifecycle.stopped
        : AiExposureServiceLifecycle.error;
    _health = null;
    _progress = null;
    _aiExtractorStatus = null;
    _dependencyStatus = null;
    if (exitCode != 0) _errorMessage = '扫描引擎异常退出：$exitCode。';
    _notify();
  }

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
    await _requireClient().configureAiExtractor(
      endpoint: url.toString(),
      model: model.resolveOperationModelId(AiApiFamily.chatCompletions),
      headers: headers,
    );
    _aiExtractorStatus = await _requireClient().aiExtractorStatus();
  }

  Future<void> _persistPreferences() async {
    try {
      await _preferencesStore.save(
        AiExposurePreferences(
          enabledSources: _enabledSources,
          defaultConcurrency: _defaultConcurrency,
          defaultValidationMode: _defaultValidationMode,
          defaultGptAssisted: _defaultGptAssisted,
          useBundledEngine: _useBundledEngine,
          externalAddress: _externalAddress,
          postgresqlEnabled: _postgresqlEnabled,
          redisEnabled: _redisEnabled,
          proxyConfiguration: _proxyConfiguration,
        ),
      );
    } catch (error, stack) {
      _errorMessage = '$error';
      silentLog('services_controller', '保存扫描服务设置', error, stack);
    }
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    await _syncProxyStatistics();
    _disposed = true;
    _proxyInspectionGeneration++;
    _proxyInspectionTimer?.cancel();
    _proxyInspectionTimer = null;
    _proxyStatisticsTimer?.cancel();
    _proxyStatisticsTimer = null;
    final pluginController = _pluginServiceController;
    final pluginListener = _pluginOperationListener;
    if (pluginController != null && pluginListener != null) {
      pluginController.operationSuccessSignal.removeListener(pluginListener);
    }
    _pluginOperationListener = null;
    _pluginServiceController = null;
    await _eventSubscription?.cancel();
    await _runtimeLogSubscription?.cancel();
    await _runtimeExitSubscription?.cancel();
    await _runtime.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
