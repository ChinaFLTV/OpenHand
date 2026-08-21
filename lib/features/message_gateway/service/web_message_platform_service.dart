import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../../app/model/app_info.dart';
import '../../../app/model/app_language.dart';
import '../../../app/model/app_settings_snapshot.dart';
import '../../../app/model/openhand_shortcut.dart';
import '../../../app/state/settings_controller.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../app/support/safe_subprocess.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/net/bounded_http_request.dart';
import '../../../shared/net/http_redirect_utils.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/bounded_base64.dart';
import '../../../shared/util/bounded_delete.dart';
import '../../../shared/util/bounded_directory_io.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/directory_cleanup.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/path_safety.dart';
import '../../../shared/util/physical_path_safety.dart';
import '../../../shared/util/sensitive_data.dart';
import '../../../shared/util/serial_task_queue.dart';
import '../../../shared/util/stable_hash.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/text_fingerprint.dart';
import '../../../shared/util/text_normalization.dart';
import '../../../shared/util/timer_safety.dart';
import '../../agents/index.dart';
import '../../ai/index.dart';
import '../../crons/index.dart';
import '../../harness/index.dart';
import '../../hooks/index.dart';
import '../../instructions/index.dart';
import '../../knowledge_base/index.dart';
import '../../machine_terminal/index.dart';
import '../../mcp/index.dart';
import '../../memory/index.dart';
import '../../plugin_service/index.dart';
import '../../skills/index.dart';
import '../../thread_template_runtime/index.dart';
import '../data/web_gateway_ops_store.dart';
import '../message_gateway_dependencies.dart';
import '../message_gateway_errors.dart';
import '../model/web_gateway_runtime.dart';
import '../model/web_gateway_session_metadata.dart';
import '../model/web_message_platform_config.dart';
import 'web_gateway_accessible_urls.dart';

// 公共类型已抽到 model/web_gateway_runtime.dart，re-export 让 view 现有 import 继续生效。
export '../model/web_gateway_runtime.dart';
export '../model/web_gateway_session_metadata.dart';

part 'web_message_platform_service_auth.part.dart';
// 内部子系统 — 通过 part 共享同一 library，保持私有 API 表面不变。
part 'web_message_platform_service_logger.part.dart';
part 'web_message_platform_service_telemetry.part.dart';

/// 会话不存在或已被删除的错误码，与 Web 端 `api/session_events.ts` 的判定一致。
const String _kWebGatewayErrorSessionMissing = 'session_deleted_or_not_found';
const String _modelSelectionLockedMessage = '已锁定服务商与模型以保证缓存命中。';
const String _webShellAssetPath = '$_kWebAssetRoot/index.html';
const String _kWebAssetRoot = 'assets/web';
const String _kJavaScriptContentType = 'application/javascript; charset=utf-8';
const String _kCssContentType = 'text/css; charset=utf-8';
const String _kManifestContentType = 'application/manifest+json; charset=utf-8';

class _WebWriteApprovalRequest {
  _WebWriteApprovalRequest({
    required this.id,
    required this.sessionId,
    required this.command,
    required this.workingDirectory,
    required this.isWriteCommand,
    required this.createdAt,
    required this.expiresAt,
    required this.completer,
    required this.source,
  });

  final String id;
  final String sessionId;
  final String command;
  final String workingDirectory;
  final bool isWriteCommand;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String source;
  final Completer<BashCommandApprovalDecision> completer;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'session_id': sessionId,
      'command': command,
      'working_directory': workingDirectory,
      'is_write_command': isWriteCommand,
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
      'source': source,
    };
  }
}

class _WebGatewayRequestException implements Exception {
  const _WebGatewayRequestException(this.statusCode, this.errorCode);

  final int statusCode;
  final String errorCode;

  @override
  String toString() => errorCode;
}

class WebWriteApprovalRequest {
  const WebWriteApprovalRequest({
    required this.id,
    required this.sessionId,
    required this.command,
    required this.workingDirectory,
    required this.isWriteCommand,
    required this.createdAt,
    required this.expiresAt,
    this.source = 'web',
  });

  factory WebWriteApprovalRequest._fromInternal(
    _WebWriteApprovalRequest approval,
  ) {
    return WebWriteApprovalRequest(
      id: approval.id,
      sessionId: approval.sessionId,
      command: approval.command,
      workingDirectory: approval.workingDirectory,
      isWriteCommand: approval.isWriteCommand,
      createdAt: approval.createdAt,
      expiresAt: approval.expiresAt,
      source: approval.source,
    );
  }

  final String id;
  final String sessionId;
  final String command;
  final String workingDirectory;
  final bool isWriteCommand;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String source;

  BashCommandApprovalRequest toBashCommandApprovalRequest() {
    return BashCommandApprovalRequest(
      command: command,
      workingDirectory: workingDirectory,
      isWriteCommand: isWriteCommand,
      requestedAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}

class _HttpByteRange {
  const _HttpByteRange({required this.start, required this.endInclusive});

  final int start;
  final int endInclusive;
}

class _GatewayBindResult {
  const _GatewayBindResult({required this.server, required this.requestedPort});

  final HttpServer server;
  final int requestedPort;

  bool get usedFallbackPort => server.port != requestedPort;
}

typedef _WebSessionMessageWindow = ({
  List<AiSessionMessage> messages,
  int offset,
  int limit,
  int total,
  bool hasMore,
  bool hasOlder,
  bool hasNewer,
  String window,
});

class WebMessagePlatformService {
  WebMessagePlatformService(
    MessageGatewayDependencies dependencies, {
    String? cacheDirectoryPath,
    String? logsDirectoryPath,
    String? workspaceDirectoryPath,
    WebGatewayOpsStore? opsStore,
  }) : _sessionController = dependencies.sessionController,
       _settingsController = dependencies.settingsController,
       _agentsController = dependencies.agentsController,
       _skillsController = dependencies.skillsController,
       _mcpController = dependencies.mcpController,
       _memoryController = dependencies.memoryController,
       _cronsController = dependencies.cronsController,
       _hooksController = dependencies.hooksController,
       _instructionsController = dependencies.instructionsController,
       _knowledgeBaseController = dependencies.knowledgeBaseController,
       _machineTerminalService = dependencies.machineTerminalService,
       _appInfo = dependencies.appInfo,
       _cacheDirectoryPath =
           cacheDirectoryPath ?? OpenHandPaths.defaultCacheDirectoryPath(),
       _workspaceDirectoryPath =
           workspaceDirectoryPath ?? OpenHandPaths.applicationDirectoryPath(),
       _opsStore = opsStore ?? WebGatewayOpsStore(),
       _fileLogger = _WebGatewayRotatingLogger(
         logsDirectoryPath: logsDirectoryPath,
       ) {
    _sessionController.addGoalContinuationYieldPredicate(
      _hasQueuedGoalInterruption,
    );
  }

  final AiSessionController _sessionController;
  final SettingsController _settingsController;
  final AgentsController _agentsController;
  final SkillsController _skillsController;
  final McpController _mcpController;
  final MemoryController _memoryController;
  final CronsController _cronsController;
  final HooksController _hooksController;
  final InstructionsController _instructionsController;
  final KnowledgeBaseController? _knowledgeBaseController;
  final MachineTerminalService _machineTerminalService;
  final AppInfo _appInfo;
  PluginServiceController? _pluginServiceController;

  /// 注入插件服务控制器（延迟注入，避免循环依赖）。
  set pluginServiceController(PluginServiceController? controller) {
    _pluginServiceController = controller;
  }

  final String _cacheDirectoryPath;
  final String _workspaceDirectoryPath;
  final WebGatewayOpsStore _opsStore;
  final _WebGatewayRotatingLogger _fileLogger;
  final StreamController<WebGatewayLogEntry> _logStreamController =
      StreamController<WebGatewayLogEntry>.broadcast();
  final StreamController<List<WebWriteApprovalRequest>>
  _pendingWriteApprovalStreamController =
      StreamController<List<WebWriteApprovalRequest>>.broadcast(sync: true);
  final AiTranslationService _translationService = AiTranslationService();
  final AiTtsPlaybackService _ttsPlaybackService = AiTtsPlaybackService();
  final OpenHandRetryableAsyncCache<String> _webShellCache =
      OpenHandRetryableAsyncCache<String>(
        () => rootBundle.loadString(_webShellAssetPath, cache: false),
      );
  final List<WebGatewayLogEntry> _memoryLogs = <WebGatewayLogEntry>[];
  final List<WebGatewayOpsSnapshotRecord> _persistedSnapshots =
      <WebGatewayOpsSnapshotRecord>[];
  final List<WebGatewayCleanupResult> _cleanupHistory =
      <WebGatewayCleanupResult>[];
  final Map<String, _WebGatewayAuthSession> _authSessions =
      <String, _WebGatewayAuthSession>{};
  final Map<String, List<Duration>> _loginAttemptsByRemoteAddress =
      <String, List<Duration>>{};
  final Map<String, _WebWriteApprovalRequest> _pendingWriteApprovals =
      <String, _WebWriteApprovalRequest>{};
  final Map<String, Map<String, Duration>> _queuedGoalYieldLeasesBySessionId =
      <String, Map<String, Duration>>{};
  int _nextWriteApprovalId = 1;

  HttpServer? _server;
  final SerialTaskQueue _lifecycleQueue = SerialTaskQueue();
  Future<void>? _disposeFuture;
  Future<void>? _startupCleanupFuture;
  bool _disposed = false;
  int _runtimeGeneration = 0;
  WebGatewayRuntimeState _state = WebGatewayRuntimeState.stopped;
  WebMessagePlatformConfig _config = const WebMessagePlatformConfig();
  WebGatewayThemeSnapshot _theme = const WebGatewayThemeSnapshot();
  final Stopwatch _runtimeStopwatch = Stopwatch();
  final Stopwatch _monotonicStopwatch = Stopwatch()..start();
  DateTime? _startedAt;
  int _inFlightRequests = 0;
  int _activeRequests = 0;
  int _totalRequests = 0;
  int _totalErrors = 0;
  int _blockedRequests = 0;
  int _totalBytesIn = 0;
  int _totalBytesOut = 0;
  int _fileMutationCount = 0;
  int _crashCount = 0;
  int _restartCount = 0;
  int _nextLogId = 1;
  String _lastError = '';
  // 扩展运维指标。遵循 SRE 四黄金信号和 OpenTelemetry HTTP 指标思路：
  // 延迟 / 流量 / 错误 / 饱和度均在进程内轻量采样，路由使用
  // 低基数字段，避免被 query 或动态 ID 撑爆。
  static const int _maxRouteEntries = 32;
  static const int _maxMetricDistributionKeys = 128;
  static const int _maxMetricKeyCharacters = 96;
  static const String _metricOverflowKey = 'other';
  static final RegExp _metricWhitespacePattern = kInlineWhitespacePattern;
  static const int _maxTrafficLatencySamplesPerMinute = 512;
  static const Duration _opsSnapshotPersistenceInterval = Duration(seconds: 15);

  /// SSE 会话快照的最小下发间隔。这是**节流**而不是防抖：流式输出期间
  /// AiSessionController 的通知间隔远小于这个值，若按防抖实现（每次通知都
  /// 取消并重排定时器），定时器会被无限推迟、整段回复期间 Web 端一帧都收不到。
  static const Duration _sseSnapshotMinInterval = Duration(milliseconds: 80);
  static const int _maxLatencyBuffer = 256;
  static const int _maxMessageWindowLimit = 200;
  static const int _sseMessageWindowSize = 20;
  static const int _sessionSummaryMessageWindowSize = 6;
  static const int _inMemoryMessageWindowDirectLimit = 240;
  static const int _sessionSummaryModelKeyScanLimit = 32;
  static const int _storedMessageWindowScanMultiplier = 1;
  static const int _storedMessageWindowScanContext = 8;
  static const int _storedMessageWindowExpandedScanMultiplier = 2;
  static const int _storedMessageWindowExpandedScanContext = 16;
  static const int _storedMessageWindowExpandedScanLimit = 96;
  static const int _maxHealthCheckResponseBytes = kBytesPerMiB;
  static const int _maxWorkspaceDirectoryScanEntries = 10000;
  static const Duration _workspaceMetadataTimeout = Duration(seconds: 2);
  static const Duration _workspaceMetadataTotalTimeout = Duration(seconds: 10);
  static const int _maxProcessFileHandleScanEntries = 64 * kBytesPerKiB;
  static const int _maxProcDiagnosticsFileBytes = 256 * kBytesPerKiB;
  static const int _maxRetainedUploadCacheFiles = 4096;
  static const int _maxUploadCacheScanEntries = 100000;
  static const int _uploadCacheCandidatePruneThreshold =
      _maxRetainedUploadCacheFiles * 2;
  static const int _maxUploadDirectoryCleanupCandidates = 4096;
  static const Duration _uploadCacheScanIdleTimeout = Duration(seconds: 3);
  static const Duration _uploadCacheScanTotalTimeout = Duration(seconds: 30);
  static const Duration _uploadCacheOperationTimeout = Duration(seconds: 5);
  static const BoundedDeletePolicy _uploadCacheDeletePolicy =
      BoundedDeletePolicy(
        maxEntries: _maxUploadCacheScanEntries + 1,
        maxDepth: 32,
        directoryIdleTimeout: Duration(seconds: 5),
        totalTimeout: _uploadCacheScanTotalTimeout,
      );
  static const Duration _networkInterfaceListTimeout = Duration(seconds: 3);
  static const Duration _localAddressesCacheTtl = Duration(seconds: 30);
  static const int _maxLocalAddresses = 64;
  static const Duration _requestBodyIdleTimeout = Duration(seconds: 30);
  static const Duration _requestBodyTotalTimeout = Duration(minutes: 2);
  static const int _connectivityProbeMinTimeoutMs = 500;
  static const int _connectivityProbeMaxTimeoutMs = 10000;
  static const Duration _queuedGoalYieldLeaseDuration = Duration(minutes: 15);
  static const Duration _authSessionTtl = Duration(hours: 24);
  static const Duration _loginRateLimitWindow = Duration(minutes: 1);
  static const int _maxAuthSessions = 128;
  static const int _maxTrackedLoginAddresses = 256;
  static const int _maxLoginAttemptsPerWindow = 12;
  static const int _maxLoginBodyBytes = 16 * kBytesPerKiB;
  static const int _maxAuthCredentialCharacters = 4096;
  static const int _maxAuthTokenCharacters = 128;
  static const int _maxAuthDeviceIdCharacters = 128;
  static const int _maxAuthMetadataCharacters = 256;
  static const int _maxAuthUserAgentCharacters = 512;
  static const int _maxQueuedGoalYieldLeaseSessions = 256;
  static const int _maxQueuedGoalYieldLeasesPerSession = 16;
  static const int _maxActiveSseSubscriptions = 64;
  static const int _maxSseSubscriptionsPerClient = 8;
  static const int _maxSseSubscriptionsPerSession = 8;
  static const int _maxPendingWriteApprovals = 128;
  static const int _maxOpsPersistenceErrorCharacters = 1000;
  static const Set<AiBuiltinToolKind> _knowledgeBaseBuiltinToolKinds =
      <AiBuiltinToolKind>{
        AiBuiltinToolKind.knowledgeSearch,
        AiBuiltinToolKind.knowledgeRead,
      };
  static final Set<AiBuiltinToolKind> _agentBuiltinToolKinds = AiBuiltinToolKind
      .values
      .where((kind) => kind.isAgentCoordinationTool)
      .toSet();
  final Map<String, int> _statusBuckets = <String, int>{
    '1xx': 0,
    '2xx': 0,
    '3xx': 0,
    '4xx': 0,
    '5xx': 0,
  };
  final Map<String, int> _methodCounts = <String, int>{};
  final Map<String, int> _routeCounts = <String, int>{};
  final Map<String, int> _ipDistribution = <String, int>{};
  final Map<String, int> _peerDistribution = <String, int>{};
  final Map<String, int> _clientDistribution = <String, int>{};
  final Map<String, int> _protocolDistribution = <String, int>{};
  final Map<DateTime, _WebGatewayMinuteBucket> _trafficBuckets =
      <DateTime, _WebGatewayMinuteBucket>{};
  final List<int> _latencyBuffer = <int>[];
  DateTime? _lastErrorAt;
  String _lastErrorPath = '';
  String _slowestRecentPath = '';
  String _slowestRecentMethod = '';
  int _slowestRecentDurationMs = 0;
  int _slowestRecentStatus = 0;
  DateTime? _slowestRecentAt;
  _ProcessDiagnostics _processDiagnostics = const _ProcessDiagnostics();
  Duration? _processDiagnosticsRefreshedAt;
  Future<void>? _processDiagnosticsRefreshFuture;
  _LinuxCpuSample? _previousLinuxCpuSample;
  late final OpenHandDebouncer _opsPersistDebouncer = OpenHandDebouncer(
    delay: const Duration(milliseconds: 900),
    onError: (error, stack) =>
        silentLog('web_message_platform_service', '持久化运维数据', error, stack),
  );
  final SerialTaskQueue _opsPersistenceQueue = SerialTaskQueue();
  Future<void>? _opsDataLoadFuture;
  bool _opsDataLoaded = false;
  bool _opsDataTrusted = false;
  ({Object error, StackTrace stack})? _opsDataLoadFailure;
  bool _opsMutationInProgress = false;
  bool _opsPersistencePending = false;
  bool _opsPersistenceClosing = false;

  /// 当前活跃的 SSE 订阅数（每个 `/api/sessions/<id>/events` 长连接 +1，
  /// onCancel 时 -1）。Ops 面板用它判断"是否有人在看活跃流"，并辅助识别
  /// 客户端泄漏（断网后未释放的悬挂连接）。
  int _activeSseSubscriptions = 0;
  final Map<String, int> _activeSseSubscriptionsByClient = <String, int>{};
  final Map<String, int> _activeSseSubscriptionsBySession = <String, int>{};
  final Set<void Function()> _activeSseDisposers = <void Function()>{};

  /// 最近 N 次 4xx/5xx 请求的环形缓冲。Ops 面板按时间倒序展示，便于"刚出错就能看到"。
  /// 每条 ≤ 256B（path 截 80, error 截 160），整体内存占用上限 ≈ 5KB。
  static const int _maxRecentErrors = 16;
  final List<Map<String, Object?>> _recentErrors = <Map<String, Object?>>[];

  /// 缓存当前主机非环回 IPv4 地址列表，作为 `accessibleUrls` 在
  /// 监听 `0.0.0.0` / `::` 时枚举局域网 URL 的数据源。`start()` 后填充，
  /// 消息网关页面与运维快照按 30s TTL 刷新。
  List<String> _localAddressesCache = const <String>[];
  int? _localAddressesRefreshedAtMs;
  Future<bool>? _localAddressesRefreshFuture;

  Stream<WebGatewayLogEntry> get logStream => _logStreamController.stream;
  Stream<List<WebWriteApprovalRequest>> get pendingWriteApprovalsStream =>
      _pendingWriteApprovalStreamController.stream;
  List<WebGatewayLogEntry> get logs =>
      List<WebGatewayLogEntry>.unmodifiable(_memoryLogs);
  List<WebGatewayRuntimeSnapshot> get persistedRuntimeSnapshots =>
      List<WebGatewayRuntimeSnapshot>.unmodifiable(
        _persistedSnapshots.map((item) => item.snapshot),
      );
  List<WebWriteApprovalRequest> get pendingWriteApprovals =>
      _pendingWriteApprovalSnapshot();
  List<WebGatewayCleanupResult> get cleanupHistory =>
      List<WebGatewayCleanupResult>.unmodifiable(_cleanupHistory);
  WebGatewayRuntimeState get state => _state;
  bool get isRunning =>
      _server != null && _state == WebGatewayRuntimeState.running;
  String get boundUrl => _server == null
      ? ''
      : 'http://${_displayHost(_config.listenHost)}:${_server!.port}';

  /// 当前可访问该 Web 服务的全部 URL：
  /// - 监听具体 IP（如 `192.168.1.5`）→ 仅返回 `[boundUrl]`
  /// - 监听通配符 (`0.0.0.0` / `::` / 空串) → 返回 `localhost` + `127.0.0.1`
  ///   + 所有非环回 IPv4 地址。`_localAddressesCache` 由 `_refreshLocalAddresses`
  ///   异步填充；服务未启动时返回空列表。
  List<String> get accessibleUrls => computeWebGatewayAccessibleUrls(
    listenHost: _config.listenHost,
    boundPort: _server?.port,
    localIPv4Addresses: _localAddressesCache,
  );

  Future<void> loadPersistedOpsData() {
    return ensurePersistedOpsDataLoaded();
  }

  Future<void> ensurePersistedOpsDataLoaded({
    bool requireTrusted = false,
  }) async {
    _throwIfDisposed();
    if (_opsDataLoaded && (_opsDataTrusted || !requireTrusted)) {
      return;
    }
    final pending = _opsDataLoadFuture;
    if (pending != null) {
      await pending;
      _throwIfOpsDataUntrusted(requireTrusted);
      return;
    }
    late final Future<void> tracked;
    tracked = _opsPersistenceQueue
        .enqueue(_loadPersistedOpsDataLocked)
        .whenComplete(() {
          if (identical(_opsDataLoadFuture, tracked)) {
            _opsDataLoadFuture = null;
          }
        });
    _opsDataLoadFuture = tracked;
    await tracked;
    _throwIfOpsDataUntrusted(requireTrusted);
  }

  Future<void> _loadPersistedOpsDataLocked() async {
    try {
      final data = await _opsStore.load();
      final liveSnapshots = List<WebGatewayOpsSnapshotRecord>.from(
        _persistedSnapshots,
      );
      final liveLogs = List<WebGatewayLogEntry>.from(_memoryLogs);
      final liveCleanupHistory = List<WebGatewayCleanupResult>.from(
        _cleanupHistory,
      );
      _persistedSnapshots
        ..clear()
        ..addAll(_mergeSnapshotRecords(data.snapshots, liveSnapshots));
      _memoryLogs
        ..clear()
        ..addAll(_mergeLogs(data.logs, liveLogs));
      _cleanupHistory
        ..clear()
        ..addAll(_mergeCleanupHistory(data.cleanupHistory, liveCleanupHistory));
      _nextLogId =
          _memoryLogs.fold<int>(
            0,
            (maxId, entry) => math.max(maxId, entry.id),
          ) +
          1;
      if (_persistedSnapshots.isNotEmpty) {
        _hydrateMetricsFromSnapshot(_persistedSnapshots.last.snapshot);
      }
      _opsDataTrusted = true;
      _opsDataLoadFailure = null;
    } catch (error, stack) {
      _markOpsDataUntrusted(error, stack);
    } finally {
      _opsDataLoaded = true;
    }
  }

  void _throwIfOpsDataUntrusted(bool required) {
    if (!required || _opsDataTrusted) return;
    final failure = _opsDataLoadFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure.error, failure.stack);
    }
    throw StateError('Web 消息网关没有可信的运维记录快照。');
  }

  Future<WebGatewayOpsPersistenceReport> measurePersistedOpsData() async {
    await ensurePersistedOpsDataLoaded(requireTrusted: true);
    _throwIfDisposed();
    return _opsPersistenceQueue.enqueue(_measureOpsHistoryLocked);
  }

  Future<WebGatewayOpsPersistenceReport> clearPersistedOpsData({
    DateTime? startUtc,
    DateTime? endUtc,
  }) async {
    final clearsAll = startUtc == null && endUtc == null;
    if (clearsAll) {
      return _clearAllPersistedOpsData();
    }
    await ensurePersistedOpsDataLoaded(requireTrusted: true);
    _throwIfDisposed();
    return _opsPersistenceQueue.enqueue(
      () => _clearPersistedOpsDataLocked(startUtc: startUtc, endUtc: endUtc),
    );
  }

  Future<WebGatewayOpsPersistenceReport> _clearPersistedOpsDataLocked({
    required DateTime? startUtc,
    required DateTime? endUtc,
  }) async {
    _opsMutationInProgress = true;
    _opsPersistencePending = false;
    _opsPersistDebouncer.cancel();
    try {
      final before = await _measureOpsHistoryLocked();
      final initialItemCount =
          _persistedSnapshots.length +
          _memoryLogs.length +
          _cleanupHistory.length;
      final next = WebGatewayOpsHistoryData(
        snapshots: _persistedSnapshots
            .where(
              (record) => !isDateTimeInUtcRange(
                record.timestamp,
                startUtc: startUtc,
                endUtc: endUtc,
              ),
            )
            .toList(growable: false),
        logs: _memoryLogs
            .where(
              (entry) => !isDateTimeInUtcRange(
                entry.timestamp,
                startUtc: startUtc,
                endUtc: endUtc,
              ),
            )
            .toList(growable: false),
        cleanupHistory: _cleanupHistory
            .where(
              (entry) => !isDateTimeInUtcRange(
                entry.timestamp,
                startUtc: startUtc,
                endUtc: endUtc,
              ),
            )
            .toList(growable: false),
      );
      await _saveOpsHistoryLocked(next);
      _persistedSnapshots.removeWhere(
        (record) => isDateTimeInUtcRange(
          record.timestamp,
          startUtc: startUtc,
          endUtc: endUtc,
        ),
      );
      _memoryLogs.removeWhere(
        (entry) => isDateTimeInUtcRange(
          entry.timestamp,
          startUtc: startUtc,
          endUtc: endUtc,
        ),
      );
      _cleanupHistory.removeWhere(
        (entry) => isDateTimeInUtcRange(
          entry.timestamp,
          startUtc: startUtc,
          endUtc: endUtc,
        ),
      );
      final after = await _measureOpsHistoryLocked();
      return WebGatewayOpsPersistenceReport(
        bytes: math.max(0, before.bytes - after.bytes),
        itemCount: math.max(0, initialItemCount - next.itemCount),
      );
    } finally {
      _opsMutationInProgress = false;
      final shouldPersist = _opsPersistencePending && _opsDataTrusted;
      _opsPersistencePending = false;
      if (shouldPersist) {
        _scheduleOpsPersistence();
      }
    }
  }

  Future<WebGatewayOpsPersistenceReport> _clearAllPersistedOpsData() {
    _throwIfDisposed();
    return _opsPersistenceQueue.enqueue(_clearAllPersistedOpsDataLocked);
  }

  Future<WebGatewayOpsPersistenceReport>
  _clearAllPersistedOpsDataLocked() async {
    final cutoff = DateTime.now().toUtc();
    final knownItemCount =
        _persistedSnapshots.length +
        _memoryLogs.length +
        _cleanupHistory.length;
    _opsMutationInProgress = true;
    _opsPersistencePending = false;
    _opsDataTrusted = false;
    _opsPersistDebouncer.cancel();
    var shouldPersistRetainedItems = false;
    try {
      late final WebGatewayOpsPersistenceReport before;
      try {
        final report = await _opsStore.measure();
        before = WebGatewayOpsPersistenceReport(
          bytes: report.bytes,
          itemCount: math.max(report.itemCount, knownItemCount),
        );
      } catch (_) {
        before = WebGatewayOpsPersistenceReport(
          bytes: await _opsStore.measureBytesOnly(),
          itemCount: knownItemCount,
        );
      }
      await _opsStore.clear();
      _persistedSnapshots.removeWhere(
        (item) => !item.timestamp.isAfter(cutoff),
      );
      _memoryLogs.removeWhere((item) => !item.timestamp.isAfter(cutoff));
      _cleanupHistory.removeWhere((item) => !item.timestamp.isAfter(cutoff));
      shouldPersistRetainedItems =
          _persistedSnapshots.isNotEmpty ||
          _memoryLogs.isNotEmpty ||
          _cleanupHistory.isNotEmpty;
      _opsDataLoaded = true;
      _opsDataTrusted = true;
      _opsDataLoadFailure = null;
      return before;
    } finally {
      _opsMutationInProgress = false;
      _opsPersistencePending = false;
      if (shouldPersistRetainedItems && _opsDataTrusted) {
        _scheduleOpsPersistence();
      }
    }
  }

  void _recordOpsSnapshot(WebGatewayRuntimeSnapshot snapshot) {
    final now = DateTime.now().toUtc();
    if (_persistedSnapshots.isNotEmpty) {
      final last = _persistedSnapshots.last;
      final elapsed = now.difference(last.timestamp);
      if (!elapsed.isNegative && elapsed < _opsSnapshotPersistenceInterval) {
        return;
      }
    }
    final record = WebGatewayOpsSnapshotRecord(
      timestamp: now,
      snapshot: snapshot,
    );
    if (_persistedSnapshots.isNotEmpty &&
        now.isBefore(_persistedSnapshots.last.timestamp)) {
      final index = _persistedSnapshots.indexWhere(
        (item) => item.timestamp.isAfter(now),
      );
      _persistedSnapshots.insert(
        index < 0 ? _persistedSnapshots.length : index,
        record,
      );
    } else {
      _persistedSnapshots.add(record);
    }
    if (_persistedSnapshots.length > webGatewayOpsMaxPersistedSnapshots) {
      _persistedSnapshots.removeRange(
        0,
        _persistedSnapshots.length - webGatewayOpsMaxPersistedSnapshots,
      );
    }
    _scheduleOpsPersistence();
  }

  void _hydrateMetricsFromSnapshot(WebGatewayRuntimeSnapshot snapshot) {
    _totalRequests = snapshot.totalRequests;
    _totalErrors = snapshot.totalErrors;
    _blockedRequests = snapshot.blockedRequests;
    _totalBytesIn = snapshot.totalBytesIn;
    _totalBytesOut = snapshot.totalBytesOut;
    _fileMutationCount = snapshot.fileMutationCount;
    _crashCount = snapshot.crashCount;
    _restartCount = snapshot.restartCount;
    _statusBuckets
      ..updateAll((_, _) => 0)
      ..addAll(snapshot.statusCodeBreakdown);
    _methodCounts
      ..clear()
      ..addAll(snapshot.methodBreakdown);
    _routeCounts
      ..clear()
      ..addAll(
        snapshot.requestDistribution.isEmpty
            ? Map<String, int>.fromEntries(snapshot.topRoutes)
            : snapshot.requestDistribution,
      );
    _ipDistribution
      ..clear()
      ..addAll(snapshot.ipDistribution);
    _peerDistribution
      ..clear()
      ..addAll(snapshot.peerDistribution);
    _clientDistribution
      ..clear()
      ..addAll(snapshot.clientDistribution);
    _protocolDistribution
      ..clear()
      ..addAll(snapshot.protocolDistribution);
    _trafficBuckets
      ..clear()
      ..addEntries(
        snapshot.trafficSeries.map(
          (sample) => MapEntry<DateTime, _WebGatewayMinuteBucket>(
            _webGatewayMinuteStart(sample.minute),
            _WebGatewayMinuteBucket.fromSample(sample),
          ),
        ),
      );
    _recentErrors
      ..clear()
      ..addAll(snapshot.recentErrors.take(_maxRecentErrors));
    _lastError = snapshot.lastError;
    _lastErrorAt = snapshot.lastErrorAt;
    _lastErrorPath = snapshot.lastErrorPath;
    final slow = snapshot.slowestRecent;
    if (slow != null) {
      _slowestRecentPath = slow.path;
      _slowestRecentMethod = slow.method;
      _slowestRecentDurationMs = slow.durationMs;
      _slowestRecentStatus = slow.statusCode;
      _slowestRecentAt = slow.at;
    }
    _latencyBuffer
      ..clear()
      ..addAll(_latencySamplesFromStats(snapshot.latencyStats));
  }

  void _scheduleOpsPersistence() {
    if (_opsPersistenceClosing || !_opsDataTrusted) return;
    if (_opsMutationInProgress) {
      _opsPersistencePending = true;
      return;
    }
    _opsPersistDebouncer.schedule(_persistOpsHistory);
  }

  Future<void> _persistOpsHistory({bool duringClose = false}) {
    if ((!duringClose && _opsPersistenceClosing) || !_opsDataTrusted) {
      return Future<void>.value();
    }
    return _opsPersistenceQueue.enqueue(() {
      final data = WebGatewayOpsHistoryData(
        snapshots: _trimSnapshotRecords(_persistedSnapshots),
        logs: _trimLogs(_memoryLogs),
        cleanupHistory: _trimCleanupHistory(_cleanupHistory),
      );
      return _saveOpsHistoryLocked(data);
    });
  }

  Future<void> _saveOpsHistoryLocked(WebGatewayOpsHistoryData data) async {
    if (!_opsDataTrusted) return;
    try {
      await _opsStore.save(data);
    } catch (error, stack) {
      _markOpsDataUntrusted(error, stack);
      rethrow;
    }
  }

  Future<WebGatewayOpsPersistenceReport> _measureOpsHistoryLocked() async {
    try {
      return await _opsStore.measure();
    } catch (error, stack) {
      _markOpsDataUntrusted(error, stack);
      rethrow;
    }
  }

  void _markOpsDataUntrusted(Object error, StackTrace stack) {
    final retainedError = error is FormatException
        ? FormatException(error.message, null, error.offset)
        : error;
    final previous = _opsDataLoadFailure?.error;
    final changed = previous == null || '$previous' != '$retainedError';
    _opsDataTrusted = false;
    _opsDataLoadFailure = (error: retainedError, stack: stack);
    if (changed) {
      _log(WebGatewayLogLevel.error, 'OPS', '运维历史不可用，持久化已暂停', <String, Object?>{
        'error': clipText('$retainedError', _maxOpsPersistenceErrorCharacters),
      });
    }
  }

  List<int> _latencySamplesFromStats(WebGatewayLatencyStats stats) {
    if (stats.sampleCount <= 0) return const <int>[];
    final values = <int>[
      if (stats.p50Ms > 0) stats.p50Ms,
      if (stats.avgMs > 0) stats.avgMs,
      if (stats.p95Ms > 0) stats.p95Ms,
      if (stats.p99Ms > 0) stats.p99Ms,
      if (stats.maxMs > 0) stats.maxMs,
    ];
    if (values.isEmpty) return const <int>[];
    final target = math.min(stats.sampleCount, _maxLatencyBuffer);
    final samples = <int>[];
    for (var i = 0; i < target; i++) {
      samples.add(values[i % values.length]);
    }
    return samples;
  }

  bool _hasQueuedGoalInterruption(String sessionId) {
    _pruneQueuedGoalYieldLeases(_monotonicStopwatch.elapsed);
    final leases = _queuedGoalYieldLeasesBySessionId[sessionId];
    return leases != null && leases.isNotEmpty;
  }

  void _setQueuedGoalInterruption({
    required _WebGatewayAuthSession auth,
    required String sessionId,
    required bool hasPendingQueue,
  }) {
    final authKey = auth.token.trim().isEmpty ? 'anonymous' : auth.token.trim();
    final now = _monotonicStopwatch.elapsed;
    _pruneQueuedGoalYieldLeases(now);
    if (!hasPendingQueue) {
      final leases = _queuedGoalYieldLeasesBySessionId[sessionId];
      leases?.remove(authKey);
      if (leases != null && leases.isEmpty) {
        _queuedGoalYieldLeasesBySessionId.remove(sessionId);
      }
      return;
    }
    if (!_queuedGoalYieldLeasesBySessionId.containsKey(sessionId) &&
        _queuedGoalYieldLeasesBySessionId.length >=
            _maxQueuedGoalYieldLeaseSessions) {
      String? oldestSessionId;
      Duration? oldestUpdatedAt;
      for (final entry in _queuedGoalYieldLeasesBySessionId.entries) {
        final latestUpdatedAt = entry.value.values.reduce(
          (left, right) => left > right ? left : right,
        );
        if (oldestUpdatedAt == null || latestUpdatedAt < oldestUpdatedAt) {
          oldestSessionId = entry.key;
          oldestUpdatedAt = latestUpdatedAt;
        }
      }
      if (oldestSessionId != null) {
        _queuedGoalYieldLeasesBySessionId.remove(oldestSessionId);
      }
    }
    final leases = _queuedGoalYieldLeasesBySessionId.putIfAbsent(
      sessionId,
      () => <String, Duration>{},
    );
    if (!leases.containsKey(authKey) &&
        leases.length >= _maxQueuedGoalYieldLeasesPerSession) {
      final oldestKey = leases.entries
          .reduce((left, right) => left.value < right.value ? left : right)
          .key;
      leases.remove(oldestKey);
    }
    leases[authKey] = now;
  }

  void _pruneQueuedGoalYieldLeases(Duration now) {
    final cutoff = now - _queuedGoalYieldLeaseDuration;
    _queuedGoalYieldLeasesBySessionId.removeWhere((_, leases) {
      leases.removeWhere((_, updatedAt) => updatedAt < cutoff);
      return leases.isEmpty;
    });
  }

  String _boundedAuthText(Object? value, int maxCharacters) {
    return clipText(_string(value, '').trim(), maxCharacters, suffix: '');
  }

  String _requestRemoteAddress(shelf.Request request) {
    return _boundedAuthText(
      (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
              ?.remoteAddress
              .address ??
          'unknown',
      _maxAuthMetadataCharacters,
    );
  }

  bool _admitLoginAttempt(String remoteAddress, Duration now) {
    final cutoff = now - _loginRateLimitWindow;
    _loginAttemptsByRemoteAddress.removeWhere((_, attempts) {
      attempts.removeWhere((attempt) => attempt < cutoff);
      return attempts.isEmpty;
    });
    if (!_loginAttemptsByRemoteAddress.containsKey(remoteAddress) &&
        _loginAttemptsByRemoteAddress.length >= _maxTrackedLoginAddresses) {
      _loginAttemptsByRemoteAddress.remove(
        _loginAttemptsByRemoteAddress.keys.first,
      );
    }
    final attempts = _loginAttemptsByRemoteAddress.putIfAbsent(
      remoteAddress,
      () => <Duration>[],
    );
    if (attempts.length >= _maxLoginAttemptsPerWindow) return false;
    attempts.add(now);
    return true;
  }

  void _removeAuthSession(String token) {
    if (_authSessions.remove(token) == null) return;
    _queuedGoalYieldLeasesBySessionId.removeWhere((_, leases) {
      leases.remove(token);
      return leases.isEmpty;
    });
  }

  void _pruneAuthSessions(Duration now) {
    final cutoff = now - _authSessionTtl;
    final expiredTokens = _authSessions.entries
        .where((entry) => entry.value.issuedAt < cutoff)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final token in expiredTokens) {
      _removeAuthSession(token);
    }
    while (_authSessions.length > _maxAuthSessions) {
      _removeAuthSession(_authSessions.keys.first);
    }
  }

  _WebGatewayAuthSession? _authSessionForToken(String token) {
    _pruneAuthSessions(_monotonicStopwatch.elapsed);
    final session = _authSessions.remove(token);
    if (session == null) return null;
    _authSessions[token] = session;
    return session;
  }

  void _storeAuthSession(_WebGatewayAuthSession session) {
    _pruneAuthSessions(_monotonicStopwatch.elapsed);
    final replacedTokens = _authSessions.entries
        .where(
          (entry) =>
              entry.value.source == session.source &&
              entry.value.deviceId == session.deviceId,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final token in replacedTokens) {
      _removeAuthSession(token);
    }
    while (_authSessions.length >= _maxAuthSessions) {
      _removeAuthSession(_authSessions.keys.first);
    }
    _authSessions[session.token] = session;
  }

  void updateTheme(WebGatewayThemeSnapshot theme) {
    _theme = theme;
  }

  Future<T> _enqueueLifecycle<T>(Future<T> Function() operation) {
    if (_disposed) return Future<T>.error(_disposedError);
    return _lifecycleQueue.enqueue(() {
      _throwIfDisposed();
      return operation();
    });
  }

  StateError get _disposedError => StateError('Web 消息网关服务已关闭。');

  void _throwIfDisposed() {
    if (_disposed) throw _disposedError;
  }

  Future<void> start(WebMessagePlatformConfig config) =>
      _enqueueLifecycle(() => _start(config));

  Future<void> _start(WebMessagePlatformConfig config) async {
    await ensurePersistedOpsDataLoaded();
    _throwIfDisposed();
    if (_server != null) {
      await _stop();
      _throwIfDisposed();
      if (_server != null) {
        _state = WebGatewayRuntimeState.crashed;
        throw StateError('现有 Web 消息网关未能安全停止。');
      }
    }
    _config = config;
    if (!config.enabled) {
      _state = WebGatewayRuntimeState.stopped;
      return;
    }
    _state = WebGatewayRuntimeState.starting;
    _log(WebGatewayLogLevel.info, 'BOOT', '正在启动 Web 通用消息平台', <String, Object?>{
      'host': config.listenHost,
      'port': config.listenPort,
    });
    try {
      final address = _bindAddress(config.listenHost);
      final pipeline = const shelf.Pipeline()
          .addMiddleware(_telemetryAndLimitMiddleware())
          .addMiddleware(_corsMiddleware());
      final handler = pipeline.addHandler(_buildRouter().call);
      final bindResult = await _serveGateway(
        handler: handler,
        address: address,
        config: config,
      );
      final server = bindResult.server;
      _server = server;
      server.serverHeader = 'OpenHand-WebGateway/1.0';
      if (_disposed) {
        await _closeServer(server, logAction: '关闭迟到绑定的 HTTP 服务');
        throw _disposedError;
      }
      _startedAt = DateTime.now().toUtc();
      _runtimeStopwatch
        ..reset()
        ..start();
      _lastError = '';
      _lastErrorAt = null;
      _lastErrorPath = '';
      _state = WebGatewayRuntimeState.running;
      // 启动后立刻探测一次主机 IP 列表，使 BOOT 日志可同时打出 LAN URL；
      // 枚举有显式超时，异常系统服务不会无限阻塞启动。
      await refreshAccessibleUrls(force: true);
      _throwIfDisposed();
      final urls = accessibleUrls;
      if (bindResult.usedFallbackPort) {
        _log(
          WebGatewayLogLevel.warn,
          'BOOT',
          '配置端口 ${bindResult.requestedPort} 已被占用，已临时监听 ${server.port}',
          <String, Object?>{
            'host': config.listenHost,
            'requested_port': bindResult.requestedPort,
            'bound_port': server.port,
            'bound_url': boundUrl,
            'accessible_urls': urls,
          },
        );
      }
      final logSummary = urls.length <= 1
          ? boundUrl
          : '$boundUrl  (LAN: ${urls.where((u) => u != boundUrl).join(", ")})';
      _log(
        WebGatewayLogLevel.success,
        'BOOT',
        'Web 服务已监听 $logSummary',
        <String, Object?>{'bound_url': boundUrl, 'accessible_urls': urls},
      );
      _logPublicAccessWarningIfNeeded(config, urls);
      _scheduleStartupCleanup();
    } catch (error) {
      final failedServer = _server;
      if (failedServer != null) {
        await _closeServer(failedServer, logAction: '关闭启动失败后的 HTTP 服务');
      }
      if (_disposed) {
        _state = WebGatewayRuntimeState.stopped;
        _clearStoppedRuntimeState();
        rethrow;
      }
      _state = WebGatewayRuntimeState.crashed;
      _crashCount++;
      _lastError = _startupFailureMessage(config, error);
      _log(WebGatewayLogLevel.error, 'BOOT', _lastError, <String, Object?>{
        'host': config.listenHost,
        'port': config.listenPort,
      });
      rethrow;
    }
  }

  void _scheduleStartupCleanup() {
    if (_disposed || _startupCleanupFuture != null) return;
    late final Future<void> cleanup;
    cleanup =
        () async {
          try {
            await cleanupArtifacts(
              logs: true,
              uploads: true,
              expiredOnly: true,
            );
          } catch (error, stack) {
            silentLog(
              'web_message_platform_service',
              '清理启动后的过期产物',
              error,
              stack,
            );
          }
        }().whenComplete(() {
          if (identical(_startupCleanupFuture, cleanup)) {
            _startupCleanupFuture = null;
          }
        });
    _startupCleanupFuture = cleanup;
    unawaited(cleanup);
  }

  Future<bool> _closeServer(
    HttpServer server, {
    required String logAction,
    void Function(Object error)? onError,
  }) {
    final close = Future<void>.sync(() async {
      await server.close(force: true);
      if (identical(_server, server)) {
        _server = null;
      }
    });
    return runAsyncCleanupBounded(
      () => close,
      onError: (error, stack) {
        onError?.call(error);
        silentLog('web_message_platform_service', logAction, error, stack);
      },
    );
  }

  Future<void> stop() => _enqueueLifecycle(_stop);

  Future<void> _stop() async {
    _runtimeGeneration += 1;
    final server = _server;
    _state = server == null
        ? WebGatewayRuntimeState.stopped
        : WebGatewayRuntimeState.stopping;
    if (server != null) {
      _log(WebGatewayLogLevel.warn, 'OPS', '正在停止 Web 服务');
    }
    _resolvePendingWriteApprovals(
      decision: BashCommandApprovalDecision.cancelled,
      source: 'service_stop',
    );
    await runAsyncCleanupBounded(
      _ttsPlaybackService.stop,
      timeout: const Duration(seconds: 8),
      onError: (error, stack) =>
          silentLog('web_message_platform_service', '停止语音播放', error, stack),
    );
    for (final dispose in List<void Function()>.from(_activeSseDisposers)) {
      try {
        dispose();
      } catch (error, stack) {
        silentLog('web_message_platform_service', '关闭 SSE 订阅', error, stack);
      }
    }
    _activeSseDisposers.clear();
    _activeSseSubscriptions = 0;
    _activeSseSubscriptionsByClient.clear();
    _activeSseSubscriptionsBySession.clear();
    if (server == null) {
      _clearStoppedRuntimeState();
      return;
    }
    Object? closeError;
    final closed = await _closeServer(
      server,
      logAction: '停止 HTTP 服务',
      onError: (error) => closeError = error,
    );
    if (closed) {
      _state = WebGatewayRuntimeState.stopped;
      _clearStoppedRuntimeState();
      _log(WebGatewayLogLevel.success, 'OPS', 'Web 服务已停止');
      return;
    }
    _state = WebGatewayRuntimeState.crashed;
    _crashCount++;
    _lastError = closeError == null
        ? 'HTTP 服务关闭超时。'
        : messageGatewayFailureMessage(
            closeError!,
            fallback: 'HTTP 服务停止失败，请稍后重试。',
          );
    _log(WebGatewayLogLevel.error, 'OPS', '停止 Web 服务失败：$_lastError');
    throw StateError(_lastError);
  }

  Future<void> restart(WebMessagePlatformConfig config) =>
      _enqueueLifecycle(() => _restart(config));

  Future<void> _restart(WebMessagePlatformConfig config) async {
    _restartCount++;
    await _stop();
    _throwIfDisposed();
    await _start(config);
  }

  Future<void> reloadConfig(WebMessagePlatformConfig config) =>
      _enqueueLifecycle(() => _reloadConfig(config));

  Future<void> _reloadConfig(WebMessagePlatformConfig config) async {
    await ensurePersistedOpsDataLoaded();
    _throwIfDisposed();
    final needsRestart =
        config.enabled != _config.enabled ||
        config.listenHost != _config.listenHost ||
        config.listenPort != _config.listenPort;
    final authChanged =
        config.authEnabled != _config.authEnabled ||
        config.username != _config.username ||
        config.password != _config.password;
    if (needsRestart) {
      await _restart(config);
    } else {
      _config = config;
      if (authChanged) {
        _authSessions.clear();
        _queuedGoalYieldLeasesBySessionId.clear();
      }
    }
    _log(WebGatewayLogLevel.info, 'OPS', '配置已重新加载');
  }

  Future<void> dispose() {
    final active = _disposeFuture;
    if (active != null) return active;
    _disposed = true;
    final disposal = _lifecycleQueue.idle.then((_) => _disposeLocked());
    _disposeFuture = disposal;
    return disposal;
  }

  Future<void> _disposeLocked() async {
    Future<bool> cleanup(
      String action,
      FutureOr<void> Function() operation, {
      Duration timeout = kOpenHandDefaultAsyncCleanupTimeout,
    }) {
      return runAsyncCleanupBounded(
        operation,
        timeout: timeout,
        onError: (error, stack) =>
            silentLog('web_message_platform_service', action, error, stack),
      );
    }

    await cleanup('停止消息网关服务', _stop, timeout: const Duration(seconds: 10));
    final startupCleanup = _startupCleanupFuture;
    if (startupCleanup != null) {
      await cleanup('等待启动清理任务结束', () => startupCleanup);
    }
    _opsPersistenceClosing = true;
    _opsPersistDebouncer.dispose();
    await cleanup('持久化运维记录', () => _persistOpsHistory(duringClose: true));
    await cleanup(
      '移除目标续跑判断器',
      () => _sessionController.removeGoalContinuationYieldPredicate(
        _hasQueuedGoalInterruption,
      ),
    );
    await Future.wait<bool>(<Future<bool>>[
      cleanup('关闭文件日志器', _fileLogger.close),
      cleanup('关闭翻译服务', _translationService.dispose),
      cleanup(
        '关闭语音播放服务',
        _ttsPlaybackService.dispose,
        timeout: const Duration(seconds: 8),
      ),
    ]);
    await Future.wait<bool>(<Future<bool>>[
      cleanup('关闭日志事件流', _logStreamController.close),
      cleanup('关闭写操作审批事件流', _pendingWriteApprovalStreamController.close),
    ]);
    if (_server == null) {
      _state = WebGatewayRuntimeState.stopped;
      _clearStoppedRuntimeState();
    }
  }

  void _clearStoppedRuntimeState() {
    _startedAt = null;
    _runtimeStopwatch
      ..stop()
      ..reset();
    _authSessions.clear();
    _loginAttemptsByRemoteAddress.clear();
    _queuedGoalYieldLeasesBySessionId.clear();
  }

  WebGatewayRuntimeSnapshot runtimeSnapshot() {
    final startedAt = _startedAt;
    final uptimeMs = startedAt == null
        ? 0
        : _runtimeStopwatch.elapsedMilliseconds;
    return WebGatewayRuntimeSnapshot(
      state: _state,
      startedAt: startedAt,
      uptimeMs: uptimeMs,
      boundUrl: boundUrl,
      accessibleUrls: accessibleUrls,
      activeRequests: _activeRequests,
      currentConnections: _activeRequests + _activeSseSubscriptions,
      maxConcurrentRequests: _config.maxConcurrentRequests,
      activeRequestRatio: _config.maxConcurrentRequests <= 0
          ? 0
          : _activeRequests / _config.maxConcurrentRequests,
      totalRequests: _totalRequests,
      totalErrors: _totalErrors,
      blockedRequests: _blockedRequests,
      totalBytesIn: _totalBytesIn,
      totalBytesOut: _totalBytesOut,
      fileMutationCount: _fileMutationCount,
      crashCount: _crashCount,
      restartCount: _restartCount,
      currentRssBytes: ProcessInfo.currentRss,
      maxRssBytes: ProcessInfo.maxRss,
      cpuPercent: _processDiagnostics.cpuPercent,
      threadCount: _processDiagnostics.threadCount,
      fileHandleCount: _processDiagnostics.fileHandleCount,
      swapBytes: _processDiagnostics.swapBytes,
      logBytes: _fileLogger.currentSizeBytes,
      openSessionCount: _sessionController.sessions.length,
      lastError: _lastError,
      // 扩展指标：将进程内观察到的 HTTP 流量切面向上传递给 UI / Web Ops。
      statusCodeBreakdown: Map<String, int>.unmodifiable(_statusBuckets),
      methodBreakdown: Map<String, int>.unmodifiable(_methodCounts),
      topRoutes: _topRoutes(),
      latencyStats: _computeLatencyStats(),
      latencyBuckets: _computeLatencyBuckets(),
      requestsPerMinute: _computeRequestsPerMinute(),
      errorsPerMinute: _computeErrorsPerMinute(),
      bytesInPerMinute: _computeBytesPerMinute(inbound: true),
      bytesOutPerMinute: _computeBytesPerMinute(inbound: false),
      slowestRecent: _slowestRecentDurationMs > 0
          ? WebGatewayRecentSlowRequest(
              path: _slowestRecentPath,
              method: _slowestRecentMethod,
              statusCode: _slowestRecentStatus,
              durationMs: _slowestRecentDurationMs,
              at: _slowestRecentAt,
            )
          : null,
      lastErrorAt: _lastErrorAt,
      lastErrorPath: _lastErrorPath,
      processId: pid,
      platform: Platform.operatingSystem,
      platformVersion: Platform.operatingSystemVersion,
      dartVersion: Platform.version,
      hostName: _safeHostName(),
      activeSseSubscriptions: _activeSseSubscriptions,
      recentErrors: List<Map<String, Object?>>.unmodifiable(
        _recentErrors.map((e) => Map<String, Object?>.unmodifiable(e)),
      ),
      logLevelBreakdown: _computeLogLevelBreakdown(),
      memoryLogCount: _memoryLogs.length,
      fileLogPendingWrites: _fileLogger.pendingWriteCount,
      fileLogPendingBytes: _fileLogger.pendingWriteBytes,
      fileLogDroppedWrites: _fileLogger.droppedWriteCount,
      sendPhaseBreakdown: _computeSendPhaseBreakdown(),
      allowedModelCount: _allowedModels().length,
      modelProviderCount: _settingsController.aiModels.length,
      templateCount: _allowedTemplates().length,
      cronEnabledCount: _cronsController.entries
          .where((entry) => entry.enabled)
          .length,
      cronTotalCount: _cronsController.entries.length,
      memoryEntryCount: _settingsController.memoryEnabled
          ? _memoryController.entries.length
          : 0,
      mcpServerEnabledCount: _mcpController.runtimeServers
          .where((s) => s.enabled)
          .length,
      mcpServerTotalCount: _mcpController.runtimeServers.length,
      ipDistribution: Map<String, int>.unmodifiable(_ipDistribution),
      peerDistribution: Map<String, int>.unmodifiable(_peerDistribution),
      clientDistribution: Map<String, int>.unmodifiable(_clientDistribution),
      requestDistribution: Map<String, int>.unmodifiable(_routeCounts),
      protocolDistribution: Map<String, int>.unmodifiable(
        _protocolDistribution,
      ),
      trafficSeries: _trafficSnapshot(),
    );
  }

  /// 把刚结束的一次请求观察并入指标缓冲。任何失败都不影响主请求 — 静默吞掉即可，
  /// 因为指标写入本身不应阻塞响应链路。
  void _observeRequestMetrics({
    required String method,
    required String path,
    required int statusCode,
    required int durationMs,
    required int requestBytes,
    required int responseBytes,
    required String remoteAddress,
    required String remoteEndpoint,
    required String clientName,
    required String protocol,
    String? errorPath,
    String? errorMessage,
  }) {
    try {
      // 状态码分桶：用首位数字定位。0 表示连接级异常未拿到上游 status code。
      final bucketKey = statusCode <= 0
          ? '5xx'
          : statusCode >= 500
          ? '5xx'
          : statusCode >= 400
          ? '4xx'
          : statusCode >= 300
          ? '3xx'
          : statusCode >= 200
          ? '2xx'
          : '1xx';
      _statusBuckets[bucketKey] = (_statusBuckets[bucketKey] ?? 0) + 1;
      // method 分布：MAX 8 个，超出走 OTHER。
      final upperMethod = method.toUpperCase();
      const knownMethods = <String>{
        'GET',
        'POST',
        'PUT',
        'PATCH',
        'DELETE',
        'HEAD',
        'OPTIONS',
      };
      final methodKey = knownMethods.contains(upperMethod)
          ? upperMethod
          : 'OTHER';
      _methodCounts[methodKey] = (_methodCounts[methodKey] ?? 0) + 1;
      // 路由分布：模板化动态 ID 与静态资源，超过容量后淘汰最低频项。
      final routeKey = webGatewayNormalizeMetricRoute(path);
      _routeCounts[routeKey] = (_routeCounts[routeKey] ?? 0) + 1;
      if (_routeCounts.length > _maxRouteEntries) {
        final smallest = _routeCounts.entries.reduce(
          (a, b) => a.value <= b.value ? a : b,
        );
        _routeCounts.remove(smallest.key);
      }
      _incrementMetricDistribution(_ipDistribution, remoteAddress);
      _incrementMetricDistribution(
        _peerDistribution,
        remoteEndpoint,
        rotateLowFrequencyKeys: true,
      );
      _incrementMetricDistribution(_clientDistribution, clientName);
      _incrementMetricDistribution(_protocolDistribution, protocol);
      _recordTrafficOutcome(
        statusCode,
        durationMs,
        requestBytes: requestBytes,
        responseBytes: responseBytes,
      );
      // 延迟环形缓冲：达到容量就 FIFO 出队。
      _latencyBuffer.add(durationMs);
      if (_latencyBuffer.length > _maxLatencyBuffer) {
        _latencyBuffer.removeAt(0);
      }
      // 慢请求记录：保留近期最慢的一次（不是历史最慢），便于发现新近退化。
      if (durationMs >= _slowestRecentDurationMs) {
        _slowestRecentDurationMs = durationMs;
        _slowestRecentPath = routeKey;
        _slowestRecentMethod = methodKey;
        _slowestRecentStatus = statusCode;
        _slowestRecentAt = DateTime.now().toUtc();
      }
      // 错误时间 / 路径快照：让面板显示"上次出错"上下文。
      if (errorPath != null || statusCode >= 500) {
        _lastErrorAt = DateTime.now().toUtc();
        _lastErrorPath = errorPath ?? routeKey;
      }
      // 4xx/5xx 进入最近错误环（200/3xx 不污染缓冲）。
      if (statusCode >= 400 || errorPath != null) {
        final entry = <String, Object?>{
          'at': DateTime.now().toUtc().toIso8601String(),
          'method': methodKey,
          'path': clipText(errorPath ?? routeKey, 80),
          'status': statusCode,
          'duration_ms': durationMs,
          if (errorMessage != null && errorMessage.isNotEmpty)
            'message': clipText(errorMessage, 160),
        };
        _recentErrors.add(entry);
        if (_recentErrors.length > _maxRecentErrors) {
          _recentErrors.removeRange(0, _recentErrors.length - _maxRecentErrors);
        }
      }
    } catch (error, stack) {
      silentLog('web_message_platform_service', '采集运行指标', error, stack);
    }
  }

  void _incrementMetricDistribution(
    Map<String, int> values,
    String rawKey, {
    bool rotateLowFrequencyKeys = false,
  }) {
    var key = rawKey.trim().replaceAll(_metricWhitespacePattern, ' ');
    if (key.isEmpty) key = 'unknown';
    if (key.length > _maxMetricKeyCharacters) {
      key = clipTextByCodeUnits(key, _maxMetricKeyCharacters, suffix: '');
    }
    final count = values[key];
    if (count != null) {
      values[key] = count + 1;
    } else if (values.length < _maxMetricDistributionKeys - 1) {
      values[key] = 1;
    } else if (rotateLowFrequencyKeys) {
      var overflow = 0;
      final reservedSlots = values.containsKey(_metricOverflowKey) ? 1 : 2;
      while (values.length > _maxMetricDistributionKeys - reservedSlots) {
        MapEntry<String, int>? smallest;
        for (final entry in values.entries) {
          if (entry.key == _metricOverflowKey) continue;
          if (smallest == null || entry.value < smallest.value) {
            smallest = entry;
          }
        }
        if (smallest == null) break;
        values.remove(smallest.key);
        overflow += smallest.value;
      }
      if (overflow > 0) {
        values[_metricOverflowKey] =
            (values[_metricOverflowKey] ?? 0) + overflow;
      }
      if (values.length < _maxMetricDistributionKeys) {
        values[key] = 1;
      } else {
        values[_metricOverflowKey] = (values[_metricOverflowKey] ?? 0) + 1;
      }
    } else {
      values[_metricOverflowKey] = (values[_metricOverflowKey] ?? 0) + 1;
    }
  }

  void _recordTrafficOutcome(
    int statusCode,
    int durationMs, {
    required int requestBytes,
    required int responseBytes,
  }) {
    final bucket = _currentTrafficBucket();
    switch (webGatewayRequestOutcomeForStatus(statusCode)) {
      case WebGatewayRequestOutcome.success:
        bucket.success += 1;
      case WebGatewayRequestOutcome.blocked:
        bucket.blocked += 1;
      case WebGatewayRequestOutcome.failed:
        bucket.failed += 1;
    }
    bucket.inboundBytes += math.max(0, requestBytes);
    bucket.outboundBytes += math.max(0, responseBytes);
    bucket.addLatency(
      math.max(0, durationMs),
      _maxTrafficLatencySamplesPerMinute,
    );
  }

  _WebGatewayMinuteBucket _currentTrafficBucket() {
    final minute = _webGatewayMinuteStart(DateTime.now().toUtc());
    final bucket = _trafficBuckets.putIfAbsent(
      minute,
      () => _WebGatewayMinuteBucket(minute),
    );
    if (_trafficBuckets.length > webGatewayOpsTrafficWindowMinutes * 3) {
      final cutoff = minute.subtract(
        const Duration(minutes: webGatewayOpsTrafficWindowMinutes * 3),
      );
      _trafficBuckets.removeWhere((key, _) => key.isBefore(cutoff));
    }
    return bucket;
  }

  List<WebGatewayTrafficSample> _trafficSnapshot() {
    final latest = _webGatewayMinuteStart(DateTime.now().toUtc());
    return List<WebGatewayTrafficSample>.unmodifiable(
      List<WebGatewayTrafficSample>.generate(
        webGatewayOpsTrafficWindowMinutes,
        (index) {
          final minute = latest.subtract(
            Duration(minutes: webGatewayOpsTrafficWindowMinutes - index - 1),
          );
          return _trafficBuckets[minute]?.toSample() ??
              WebGatewayTrafficSample(minute: minute);
        },
        growable: false,
      ),
    );
  }

  String _requestMetricClientName(shelf.Request request) {
    return webGatewaySummarizeClientUserAgent(
      userAgent: request.headers[HttpHeaders.userAgentHeader] ?? '',
      browserName: request.headers['x-openhand-browser-name'] ?? '',
      browserVersion: request.headers['x-openhand-browser-version'] ?? '',
      osName: request.headers['x-openhand-os-name'] ?? '',
      osVersion: request.headers['x-openhand-os-version'] ?? '',
      platform: request.headers['x-openhand-device-platform'] ?? '',
      source: request.headers['x-openhand-source'] ?? '',
    );
  }

  String _requestMetricProtocol(shelf.Request request) {
    if (request.requestedUri.path.endsWith('/events')) return 'SSE';
    final scheme = nullIfBlank(request.requestedUri.scheme) ?? 'http';
    return scheme.toUpperCase();
  }

  // 取 routeCounts 排名前 [limit] 的条目，按计数降序。
  List<MapEntry<String, int>> _topRoutes({int limit = 8}) {
    final entries = _routeCounts.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.length <= limit) return entries;
    return entries.sublist(0, limit);
  }

  // 计算延迟分位数：拿环上一份排序拷贝，按线性插值取 p50/p95/p99。
  // 缓冲长度 ≤256，CPU 成本可忽略；分位算法采用 Hyndman-Fan #7（Excel/numpy 默认）。
  WebGatewayLatencyStats _computeLatencyStats() {
    if (_latencyBuffer.isEmpty) {
      return const WebGatewayLatencyStats();
    }
    final sorted = List<int>.from(_latencyBuffer)..sort();
    final n = sorted.length;
    final sum = sorted.fold<int>(0, (a, b) => a + b);
    int pick(double q) {
      if (n == 1) return sorted.first;
      final pos = q * (n - 1);
      final lo = pos.floor();
      final hi = pos.ceil();
      if (lo == hi) return sorted[lo];
      final frac = pos - lo;
      return (sorted[lo] + (sorted[hi] - sorted[lo]) * frac).round();
    }

    return WebGatewayLatencyStats(
      sampleCount: n,
      avgMs: (sum / n).round(),
      p50Ms: pick(0.5),
      p95Ms: pick(0.95),
      p99Ms: pick(0.99),
      maxMs: sorted.last,
    );
  }

  // 当前 UTC 分钟桶的实时累计值，与 12 分钟趋势使用同一数据源。
  double _computeRequestsPerMinute() {
    return (_trafficBuckets[_webGatewayMinuteStart(DateTime.now().toUtc())]
                ?.total ??
            0)
        .toDouble();
  }

  double _computeErrorsPerMinute() {
    final bucket =
        _trafficBuckets[_webGatewayMinuteStart(DateTime.now().toUtc())];
    return ((bucket?.blocked ?? 0) + (bucket?.failed ?? 0)).toDouble();
  }

  double _computeBytesPerMinute({required bool inbound}) {
    final bucket =
        _trafficBuckets[_webGatewayMinuteStart(DateTime.now().toUtc())];
    if (bucket == null) return 0;
    return (inbound ? bucket.inboundBytes : bucket.outboundBytes).toDouble();
  }

  void _recordStreamingOutboundBytes(int bytes) {
    if (bytes <= 0) return;
    _totalBytesOut += bytes;
    _currentTrafficBucket().outboundBytes += bytes;
  }

  Stream<List<int>> _observeOutboundByteStream(
    Stream<List<int>> source,
  ) async* {
    await for (final chunk in source) {
      _recordStreamingOutboundBytes(chunk.length);
      yield chunk;
    }
  }

  Map<String, int> _computeLatencyBuckets() {
    const labels = <String>[
      '<=50ms',
      '<=100ms',
      '<=250ms',
      '<=500ms',
      '<=1s',
      '<=2.5s',
      '>2.5s',
    ];
    final buckets = <String, int>{for (final label in labels) label: 0};
    for (final value in _latencyBuffer) {
      final label = value <= 50
          ? '<=50ms'
          : value <= 100
          ? '<=100ms'
          : value <= 250
          ? '<=250ms'
          : value <= 500
          ? '<=500ms'
          : value <= 1000
          ? '<=1s'
          : value <= 2500
          ? '<=2.5s'
          : '>2.5s';
      buckets[label] = (buckets[label] ?? 0) + 1;
    }
    return buckets;
  }

  Map<String, int> _computeLogLevelBreakdown() {
    final out = <String, int>{};
    for (final entry in _memoryLogs) {
      final key = entry.level.name;
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

  Map<String, int> _computeSendPhaseBreakdown() {
    final out = <String, int>{};
    for (final session in _sessionController.sessions) {
      final key = _sessionController.sendPhaseForSession(session.id).name;
      out[key] = (out[key] ?? 0) + 1;
    }
    return out;
  }

  String _safeHostName() {
    try {
      return Platform.localHostname;
    } catch (error, stack) {
      silentLog('web_message_platform_service', '读取本地主机名', error, stack);
      return '';
    }
  }

  Future<WebGatewayRuntimeSnapshot> runtimeSnapshotAsync() async {
    await ensurePersistedOpsDataLoaded();
    await _refreshProcessDiagnosticsIfStale();
    await refreshAccessibleUrls();
    final snapshot = runtimeSnapshot();
    _recordOpsSnapshot(snapshot);
    return snapshot;
  }

  /// 刷新通配符监听对应的可访问 IPv4 地址。失败时保留上次结果。
  Future<bool> refreshAccessibleUrls({bool force = false}) {
    if (_server == null || !_isWildcardListenHost(_config.listenHost)) {
      return Future<bool>.value(false);
    }
    return _refreshLocalAddressesIfStale(
      ttl: force ? Duration.zero : _localAddressesCacheTtl,
    );
  }

  Future<bool> _refreshLocalAddressesIfStale({required Duration ttl}) {
    final refreshedAtMs = _localAddressesRefreshedAtMs;
    if (refreshedAtMs != null &&
        _monotonicStopwatch.elapsedMilliseconds - refreshedAtMs <
            ttl.inMilliseconds) {
      return Future<bool>.value(false);
    }
    final pending = _localAddressesRefreshFuture;
    if (pending != null) return pending;
    late final Future<bool> refresh;
    refresh = _refreshLocalAddresses().whenComplete(() {
      if (identical(_localAddressesRefreshFuture, refresh)) {
        _localAddressesRefreshFuture = null;
      }
    });
    _localAddressesRefreshFuture = refresh;
    return refresh;
  }

  Future<bool> _refreshLocalAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      ).timeout(_networkInterfaceListTimeout);
      final addrs = <String>{};
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final value = addr.address.trim();
          if (value.isEmpty || addr.isLoopback || value == '0.0.0.0') continue;
          addrs.add(value);
          if (addrs.length >= _maxLocalAddresses) break;
        }
        if (addrs.length >= _maxLocalAddresses) break;
      }
      final next = addrs.toList(growable: false)..sort();
      final changed = !listEquals(_localAddressesCache, next);
      if (changed) _localAddressesCache = List<String>.unmodifiable(next);
      _localAddressesRefreshedAtMs = _monotonicStopwatch.elapsedMilliseconds;
      return changed;
    } catch (error, stack) {
      silentLog('web_message_platform_service', '刷新本地地址', error, stack);
      return false;
    }
  }

  Future<WebGatewayHealthResult> runHealthCheck() async {
    if (_server == null) {
      return const WebGatewayHealthResult(
        ok: false,
        statusCode: 0,
        durationMs: 0,
        summary: 'Web 服务未运行',
      );
    }
    final health = _config.healthCheck;
    final query = <String, String>{...health.queryParameters};
    final uri = Uri(
      scheme: 'http',
      host: _displayHost(_config.listenHost),
      port: _server!.port,
      path: health.path.startsWith('/') ? health.path : '/${health.path}',
      queryParameters: query.isEmpty ? null : query,
    );
    final stopwatch = Stopwatch()..start();
    final timeout = Duration(milliseconds: health.timeoutMs);
    final deadline = MonotonicDeadline(timeout, timeoutMessage: 'Web 健康检查超时。');
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await openHttpClientRequestBounded(
        () => client.openUrl(health.method, uri),
        timeout: deadline.remaining(),
        timeoutMessage: 'Web 健康检查请求打开超时。',
      );
      request.followRedirects = health.followRedirects;
      final response = await closeHttpClientRequestBounded(
        request,
        timeout: deadline.remaining(),
        timeoutMessage: 'Web 健康检查响应头获取超时。',
      );
      final remaining = deadline.remaining();
      final body = await readBoundedHttpResponseText(
        response,
        maxBytes: _maxHealthCheckResponseBytes,
        idleTimeout: remaining,
        totalTimeout: remaining,
        allowMalformed: true,
      );
      stopwatch.stop();
      final containsOk =
          health.responseContains.trim().isEmpty ||
          body.contains(health.responseContains.trim());
      final ok = response.statusCode == health.expectedStatusCode && containsOk;
      final result = WebGatewayHealthResult(
        ok: ok,
        statusCode: response.statusCode,
        durationMs: stopwatch.elapsedMilliseconds,
        summary: ok ? '健康检查通过' : '健康检查未满足断言',
        bodyPreview: clipText(body, 600),
      );
      _log(
        ok ? WebGatewayLogLevel.success : WebGatewayLogLevel.warn,
        'HEALTH',
        result.summary,
        result.toJson(),
      );
      return result;
    } catch (error, stack) {
      stopwatch.stop();
      silentLog('web_message_platform_service', '执行健康检查', error, stack);
      final result = WebGatewayHealthResult(
        ok: false,
        statusCode: 0,
        durationMs: stopwatch.elapsedMilliseconds,
        summary: messageGatewayFailureMessage(
          error,
          fallback: '健康检查失败，请检查服务状态与健康检查配置。',
        ),
      );
      _log(WebGatewayLogLevel.error, 'HEALTH', result.summary);
      return result;
    } finally {
      deadline.stop();
      client.close(force: true);
    }
  }

  Future<WebGatewayConnectivityTestResult> runConnectivityTest() async {
    final startedAt = DateTime.now().toUtc();
    final flowLogs = <String>[];
    void addLog(String message) {
      flowLogs.add('${DateTime.now().toUtc().toIso8601String()}  $message');
    }

    if (_server == null) {
      addLog('服务未运行，跳过端口连通性测试。');
      final result = WebGatewayConnectivityTestResult(
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        targets: const <WebGatewayConnectivityProbeResult>[],
        logs: List<String>.unmodifiable(flowLogs),
      );
      _log(WebGatewayLogLevel.warn, 'CONNECT', result.summary, result.toJson());
      return result;
    }

    await refreshAccessibleUrls(force: true);
    final targets = <String>{...accessibleUrls}.toList(growable: false);
    addLog('发现 ${targets.length} 个当前可访问入口。');
    final timeout = Duration(
      milliseconds: _clampMilliseconds(
        _config.healthCheck.timeoutMs,
        min: _connectivityProbeMinTimeoutMs,
        max: _connectivityProbeMaxTimeoutMs,
      ),
    );
    final client = HttpClient()..connectionTimeout = timeout;
    final results = <WebGatewayConnectivityProbeResult>[];

    try {
      for (final baseUrl in targets) {
        final probeStarted = Stopwatch()..start();
        final baseUri = Uri.tryParse(baseUrl);
        if (baseUri == null ||
            !baseUri.hasScheme ||
            baseUri.host.isEmpty ||
            baseUri.scheme != 'http') {
          probeStarted.stop();
          const errorMessage = 'URL 格式无效。';
          addLog('URL 解析失败：$baseUrl');
          results.add(
            WebGatewayConnectivityProbeResult(
              baseUrl: baseUrl,
              endpointUrl: baseUrl,
              host: baseUrl,
              port: 0,
              ok: false,
              statusCode: 0,
              durationMs: probeStarted.elapsedMilliseconds,
              errorMessage: errorMessage,
            ),
          );
          continue;
        }
        final endpoint = baseUri.replace(path: '/api/health');
        final deadline = MonotonicDeadline(
          timeout,
          timeoutMessage: 'Web 连通性探测超时。',
        );

        addLog('开始探测 ${endpoint.host}:${endpoint.port} -> $endpoint');
        try {
          final request = await openHttpClientRequestBounded(
            () => client.getUrl(endpoint),
            timeout: deadline.remaining(),
            timeoutMessage: 'Web 连通性请求打开超时。',
          );
          request.followRedirects = false;
          final response = await closeHttpClientRequestBounded(
            request,
            timeout: deadline.remaining(),
            timeoutMessage: 'Web 连通性响应头获取超时。',
          );
          final remaining = deadline.remaining();
          final body = await readBoundedHttpResponseText(
            response,
            maxBytes: _maxHealthCheckResponseBytes,
            idleTimeout: remaining,
            totalTimeout: remaining,
            allowMalformed: true,
          );
          probeStarted.stop();
          final ok =
              response.statusCode == HttpStatus.ok && body.contains('ok');
          addLog(
            ok
                ? '探测通过 ${endpoint.host}:${endpoint.port} · ${probeStarted.elapsedMilliseconds}ms'
                : '探测未通过 ${endpoint.host}:${endpoint.port} · HTTP ${response.statusCode}',
          );
          results.add(
            WebGatewayConnectivityProbeResult(
              baseUrl: baseUrl,
              endpointUrl: endpoint.toString(),
              host: endpoint.host,
              port: endpoint.port,
              ok: ok,
              statusCode: response.statusCode,
              durationMs: probeStarted.elapsedMilliseconds,
              bodyPreview: clipText(body, 600),
              errorMessage: ok ? '' : 'HTTP ${response.statusCode}',
            ),
          );
        } catch (error, stack) {
          probeStarted.stop();
          if (error is! TimeoutException) {
            silentLog('web_message_platform_service', '执行连通性探测', error, stack);
          }
          final errorMessage = messageGatewayFailureMessage(
            error,
            fallback: error is TimeoutException ? '探测超时。' : '探测失败。',
          );
          addLog(
            '探测失败 ${endpoint.host}:${endpoint.port} · ${probeStarted.elapsedMilliseconds}ms · $errorMessage',
          );
          results.add(
            WebGatewayConnectivityProbeResult(
              baseUrl: baseUrl,
              endpointUrl: endpoint.toString(),
              host: endpoint.host,
              port: endpoint.port,
              ok: false,
              statusCode: 0,
              durationMs: probeStarted.elapsedMilliseconds,
              errorMessage: errorMessage,
            ),
          );
        } finally {
          deadline.stop();
        }
      }
    } finally {
      client.close(force: true);
    }

    final result = WebGatewayConnectivityTestResult(
      startedAt: startedAt,
      finishedAt: DateTime.now().toUtc(),
      targets: List<WebGatewayConnectivityProbeResult>.unmodifiable(results),
      logs: List<String>.unmodifiable(flowLogs),
    );
    _log(
      result.ok ? WebGatewayLogLevel.success : WebGatewayLogLevel.warn,
      'CONNECT',
      result.summary,
      result.toJson(),
    );
    return result;
  }

  Future<WebGatewayCleanupResult> cleanupArtifacts({
    required bool logs,
    required bool uploads,
    bool expiredOnly = false,
  }) async {
    await ensurePersistedOpsDataLoaded();
    var stats = const _CleanupStats();
    var memoryLogEntriesCleared = 0;
    if (logs) {
      if (expiredOnly) {
        stats += await _fileLogger.prune(_config.logConfig);
      } else {
        memoryLogEntriesCleared = _memoryLogs.length;
        _memoryLogs.clear();
        stats += await _fileLogger.clear();
      }
    }
    if (uploads) {
      stats += await _cleanupUploadCache(expiredOnly: expiredOnly);
    }
    final target = logs && uploads
        ? 'all'
        : logs
        ? 'logs'
        : uploads
        ? 'uploads'
        : 'none';
    final result = WebGatewayCleanupResult(
      timestamp: DateTime.now().toUtc(),
      target: target,
      expiredOnly: expiredOnly,
      deletedFiles: stats.deletedFiles,
      deletedDirectories: stats.deletedDirectories,
      bytesFreed: stats.bytesFreed,
      memoryLogEntriesCleared: memoryLogEntriesCleared,
    );
    if (target != 'none') {
      _cleanupHistory.add(result);
      if (_cleanupHistory.length > webGatewayOpsMaxCleanupHistory) {
        _cleanupHistory.removeRange(
          0,
          _cleanupHistory.length - webGatewayOpsMaxCleanupHistory,
        );
      }
      _scheduleOpsPersistence();
      _log(
        WebGatewayLogLevel.warn,
        'CLEANUP',
        expiredOnly ? '已执行过期资源清理' : '已执行资源清理',
        result.toJson(),
      );
    }
    return result;
  }

  Future<String> exportLogBundleJson() async {
    await ensurePersistedOpsDataLoaded();
    return prettyPrintJson(await _logBundlePayload());
  }

  Future<String> exportCurrentLogText() async {
    await ensurePersistedOpsDataLoaded();
    final currentFileText = await _fileLogger.readCurrentLogText();
    if (currentFileText.trim().isNotEmpty) {
      return currentFileText;
    }
    return _memoryLogs.map((entry) => entry.toLogLine()).join('\n');
  }

  void _registerBundleAssetRoute(
    Router router, {
    required String route,
    required String assetPath,
    required String contentType,
  }) {
    router.get(
      route,
      (shelf.Request _) => _serveBundleAsset(assetPath, contentType),
    );
  }

  void _registerBundleDirectoryRoute(
    Router router, {
    required String route,
    required String assetDirectory,
  }) {
    router.get(
      route,
      (shelf.Request _, String path) => _serveBundleAsset(
        '$_kWebAssetRoot/$assetDirectory/$path',
        _guessContentType(path),
      ),
    );
  }

  /// shelf 路由表。所有 handler 经过：
  /// `_corsMiddleware` → `_telemetryAndLimitMiddleware` → router。
  ///
  /// 匿名公开路由（不走鉴权）：`GET /`、`GET /login`、`GET /thread`、
  /// `GET /api/health`、`GET /api/meta`、`POST /api/login`。
  /// 其余全部经 `_withAuth` 包装：未鉴权返回 401，鉴权后注入
  /// `_WebGatewayAuthSession` 给 handler。
  Router _buildRouter() {
    final router = Router(notFoundHandler: _shelfNotFound);
    // SPA shell：仅返回 clients/web 构建产物（assets/web/index.html）。
    // 缺失时由 _serveWebShell 返回 503 和构建脚本提示。
    router.get('/', (shelf.Request _) => _serveWebShell());
    router.get('/login', (shelf.Request _) => _serveWebShell());
    router.get('/thread', (shelf.Request _) => _serveWebShell());
    router.get('/threads', (shelf.Request _) => _serveWebShell());
    // Vite 产物及旧缓存 shell 的静态资源别名。
    for (final route in const <String>['/app.js', '/threads/app.js']) {
      _registerBundleAssetRoute(
        router,
        route: route,
        assetPath: '$_kWebAssetRoot/app.js',
        contentType: _kJavaScriptContentType,
      );
    }
    for (final route in const <String>['/app.css', '/threads/app.css']) {
      _registerBundleAssetRoute(
        router,
        route: route,
        assetPath: '$_kWebAssetRoot/app.css',
        contentType: _kCssContentType,
      );
    }
    // 通配子路径覆盖 chunks/*.js 与 assets/*.{png,svg,woff2,...}。
    for (final directory in const <String>['chunks', 'assets']) {
      _registerBundleDirectoryRoute(
        router,
        route: '/$directory/<path|.+>',
        assetDirectory: directory,
      );
      _registerBundleDirectoryRoute(
        router,
        route: '/threads/$directory/<path|.+>',
        assetDirectory: directory,
      );
    }
    // public/ 拷贝到 assets/web/ 根的静态资源（logo、favicon 等）。Vite build
    // 把 clients/web/public/* 平铺至产物根目录，Flutter pubspec 把整个目录纳入
    // bundle，这里按白名单显式 expose 以避免被 SPA shell 路由 catch-all 截胡。
    for (final route in const <String>[
      '/openhand_logo.png',
      '/threads/openhand_logo.png',
      '/favicon.ico',
      '/threads/favicon.ico',
    ]) {
      _registerBundleAssetRoute(
        router,
        route: route,
        assetPath: '$_kWebAssetRoot/openhand_logo.png',
        contentType: kImagePngMimeType,
      );
    }
    // PWA: Service Worker 必须挂在站点根 scope, manifest.webmanifest 给浏览器
    // 装机使用. 两者通过 vite public/ 目录被 Flutter rootBundle 一并打包。
    for (final route in const <String>['/sw.js', '/threads/sw.js']) {
      _registerBundleAssetRoute(
        router,
        route: route,
        assetPath: '$_kWebAssetRoot/sw.js',
        contentType: _kJavaScriptContentType,
      );
    }
    for (final route in const <String>[
      '/manifest.webmanifest',
      '/threads/manifest.webmanifest',
    ]) {
      _registerBundleAssetRoute(
        router,
        route: route,
        assetPath: '$_kWebAssetRoot/manifest.webmanifest',
        contentType: _kManifestContentType,
      );
    }
    // SPA 深路由：/threads/<id> 直接刷新或粘贴打开都能命中前端 Router。
    // 必须放在静态资源别名之后，避免 /threads/app.css 被 HTML shell 截获。
    router.get(
      '/threads/<rest|.+>',
      (shelf.Request _, String rest) => _serveWebShell(),
    );
    router.get('/api/health', _apiHealth);
    router.get('/api/meta', _apiMeta);
    router.post('/api/login', _login);
    router.post('/api/logout', (shelf.Request r) => _withAuth(r, _logout));
    router.get(
      '/api/tts/playback',
      (shelf.Request r) => _withAuth(r, _getTtsPlaybackState),
    );
    router.post(
      '/api/tts/stop',
      (shelf.Request r) => _withAuth(r, _stopTtsPlayback),
    );

    router.get(
      '/api/sessions',
      (shelf.Request r) => _withAuth(r, _listSessions),
    );
    router.post(
      '/api/sessions',
      (shelf.Request r) => _withAuth(r, _createSession),
    );
    router.get(
      '/api/sessions/<sessionId>',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _getSession(req, auth, sessionId)),
    );
    router.patch(
      '/api/sessions/<sessionId>',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _renameSession(req, auth, sessionId)),
    );
    router.delete(
      '/api/sessions/<sessionId>',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _deleteSession(req, auth, sessionId)),
    );
    router.get(
      '/api/sessions/<sessionId>/messages',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _listMessages(req, auth, sessionId)),
    );
    router.get(
      '/api/sessions/<sessionId>/messages/<messageId>',
      (shelf.Request r, String sessionId, String messageId) => _withAuth(
        r,
        (req, auth) => _getMessage(req, auth, sessionId, messageId),
      ),
    );
    router.post(
      '/api/sessions/<sessionId>/messages',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _sendMessage(req, auth, sessionId)),
    );
    router.get(
      '/api/sessions/<sessionId>/terminal',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _getTerminal(req, auth, sessionId)),
    );
    router.post(
      '/api/sessions/<sessionId>/terminal/write',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _writeTerminal(req, auth, sessionId)),
    );
    router.post(
      '/api/sessions/<sessionId>/terminal/execute',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _executeTerminal(req, auth, sessionId)),
    );
    router.post(
      '/api/sessions/<sessionId>/terminal/control',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _controlTerminal(req, auth, sessionId)),
    );
    router.put(
      '/api/sessions/<sessionId>/messages/<messageId>/feedback',
      (shelf.Request r, String sessionId, String messageId) => _withAuth(
        r,
        (req, auth) => _updateMessageFeedback(req, auth, sessionId, messageId),
      ),
    );
    router.post(
      '/api/sessions/<sessionId>/messages/<messageId>/translate',
      (shelf.Request r, String sessionId, String messageId) => _withAuth(
        r,
        (req, auth) => _translateMessage(req, auth, sessionId, messageId),
      ),
    );
    router.post(
      '/api/sessions/<sessionId>/messages/<messageId>/tts/toggle',
      (shelf.Request r, String sessionId, String messageId) => _withAuth(
        r,
        (req, auth) => _toggleMessageTts(req, auth, sessionId, messageId),
      ),
    );
    router.post(
      '/api/sessions/<sessionId>/messages/<messageId>/regenerate',
      (shelf.Request r, String sessionId, String messageId) => _withAuth(
        r,
        (req, auth) => _regenerateMessage(req, auth, sessionId, messageId),
      ),
    );
    router.post(
      '/api/sessions/<sessionId>/stop',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _stopSendMessage(req, auth, sessionId)),
    );
    router.post(
      '/api/sessions/<sessionId>/goal/pause',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _pauseGoal(req, auth, sessionId)),
    );
    router.post(
      '/api/sessions/<sessionId>/goal/resume',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _resumeGoal(req, auth, sessionId)),
    );
    router.post(
      '/api/sessions/<sessionId>/goal/terminate',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _terminateGoal(req, auth, sessionId)),
    );
    router.post(
      '/api/sessions/<sessionId>/goal/queue-yield',
      (shelf.Request r, String sessionId) => _withAuth(
        r,
        (req, auth) => _syncQueuedGoalYield(req, auth, sessionId),
      ),
    );
    // 用户主动触发的会话历史压缩。复用桌面端
    // [AiSessionController.requestManualCompaction]：包含 30s 防抖、占用率
    // 过低拒绝、熔断、并发互斥等多重保护。返回值 `ok / status /
    // rejection_reason / retry_after_ms` 与 App 端 enum 一一对应。
    router.post(
      '/api/sessions/<sessionId>/compact',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _compactSession(req, auth, sessionId)),
    );
    router.get(
      '/api/sessions/<sessionId>/title-source-messages',
      (shelf.Request r, String sessionId) => _withAuth(
        r,
        (req, auth) => _listTitleSourceMessages(req, auth, sessionId),
      ),
    );
    router.post(
      '/api/sessions/<sessionId>/generate-title',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _generateTitle(req, auth, sessionId)),
    );
    router.post(
      '/api/sessions/<sessionId>/write-approvals/<approvalId>',
      (shelf.Request r, String sessionId, String approvalId) => _withAuth(
        r,
        (req, auth) => _respondWriteApproval(req, auth, sessionId, approvalId),
      ),
    );
    // 会话级节流覆盖。PUT 写入覆盖（body:
    // {chars_per_second?, cards_per_second?, enabled?}），DELETE 清除全部
    // 覆盖并回到全局设置。
    router.put(
      '/api/sessions/<sessionId>/throttle',
      (shelf.Request r, String sessionId) => _withAuth(
        r,
        (req, auth) => _setSessionThrottle(req, auth, sessionId),
      ),
    );
    router.delete(
      '/api/sessions/<sessionId>/throttle',
      (shelf.Request r, String sessionId) => _withAuth(
        r,
        (req, auth) => _clearSessionThrottle(req, auth, sessionId),
      ),
    );
    // 删除单条消息（对齐 APP 端 _home_message_bubble.dart 长按菜单 → 删除）。
    router.delete(
      '/api/sessions/<sessionId>/messages/<messageId>',
      (shelf.Request r, String sessionId, String messageId) => _withAuth(
        r,
        (req, auth) => _deleteMessage(req, auth, sessionId, messageId),
      ),
    );
    // 从指定消息派生新会话：新会话保留该消息及之前的消息，后续消息不进入派生线程。
    router.post(
      '/api/sessions/<sessionId>/messages/<messageId>/fork',
      (shelf.Request r, String sessionId, String messageId) => _withAuth(
        r,
        (req, auth) => _forkSessionFromMessage(req, auth, sessionId, messageId),
      ),
    );
    // 删除该消息及其之后的全部消息（对齐 APP 端「删除此条及后续」）。
    router.delete(
      '/api/sessions/<sessionId>/messages/<messageId>/cascade',
      (shelf.Request r, String sessionId, String messageId) => _withAuth(
        r,
        (req, auth) => _deleteMessageCascade(req, auth, sessionId, messageId),
      ),
    );
    // SSE 实时事件流：浏览器 EventSource 不支持自定义 header，因此 token 走
    // query string `?token=...`（匿名模式可省略）。该端点会推送整张
    // displayMessages 快照 + send_phase + last_error，前端按 message id 增量
    // 合并即可，无需服务端 diff。
    router.get(
      '/api/sessions/<sessionId>/events',
      (shelf.Request r, String sessionId) =>
          _sessionEventsHandler(r, sessionId),
    );
    // 媒体资产: 仅放行已被该会话消息 metadata.attachments[].path /
    // generated_image_paths / generated_video_paths / generated_audio_paths
    // 等白名单引用过的本地文件路径, 防止任意路径读取。
    router.get(
      '/api/sessions/<sessionId>/asset',
      (shelf.Request r, String sessionId) => _sessionAssetHandler(r, sessionId),
    );
    // 导出会话：返回 application/x-ndjson + Content-Disposition attachment，
    // 以便浏览器一键下载。包含 session 头信息 + 全量未删除消息（不分页）。
    router.get(
      '/api/sessions/<sessionId>/export',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _exportSession(req, auth, sessionId)),
    );

    router.get(
      '/api/ops',
      (shelf.Request r) => _withAuth(r, (_, _) => _opsSnapshot()),
    );
    router.get(
      '/api/ops/cleanup/history',
      (shelf.Request r) => _withAuth(r, (_, _) => _cleanupHistoryPayload()),
    );
    router.post(
      '/api/ops/cleanup',
      (shelf.Request r) => _withAuth(r, (req, _) => _cleanupOps(req)),
    );
    router.get(
      '/api/logs',
      (shelf.Request r) => _withAuth(r, (req, _) => _listLogs(req)),
    );
    router.get(
      '/api/logs/export',
      (shelf.Request r) => _withAuth(r, (_, _) => _exportLogs()),
    );
    router.get(
      '/api/workspace/files',
      (shelf.Request r) => _withAuth(r, (req, _) => _listWorkspaceFiles(req)),
    );
    router.get(
      '/api/workspace/file',
      (shelf.Request r) => _withAuth(r, (req, _) => _readWorkspaceFile(req)),
    );
    router.put(
      '/api/workspace/file',
      (shelf.Request r) => _withAuth(r, (req, _) => _writeWorkspaceFile(req)),
    );
    router.post(
      '/api/workspace/directory',
      (shelf.Request r) =>
          _withAuth(r, (req, _) => _createWorkspaceDirectory(req)),
    );
    router.delete(
      '/api/workspace/file',
      (shelf.Request r) => _withAuth(r, (req, _) => _deleteWorkspaceFile(req)),
    );

    // Toolbox: 只读列出应用资源与调用统计。
    // App 端是这些资源的真权威 (增删改全在 GUI), Web 端只读消费即可。
    router.get(
      '/api/mcp/servers',
      (shelf.Request r) => _withAuth(r, (_, _) => _listMcpServersHandler()),
    );
    router.get(
      '/api/tools',
      (shelf.Request r) => _withAuth(r, (_, _) => _listBuiltinToolsHandler()),
    );
    router.get(
      '/api/skills',
      (shelf.Request r) => _withAuth(r, (_, _) => _listSkillsHandler()),
    );
    router.get(
      '/api/memories',
      (shelf.Request r) => _withAuth(r, (_, _) => _listMemoriesHandler()),
    );
    router.get(
      '/api/crons',
      (shelf.Request r) => _withAuth(r, (_, _) => _listCronsHandler()),
    );
    router.get(
      '/api/hooks',
      (shelf.Request r) => _withAuth(r, (_, _) => _listHooksHandler()),
    );
    router.get(
      '/api/knowledge/sources',
      (shelf.Request r) =>
          _withAuth(r, (_, _) => _listKnowledgeSourcesHandler()),
    );
    router.get(
      '/api/agents',
      (shelf.Request r) => _withAuth(r, (_, _) => _listAgentsHandler()),
    );
    router.get(
      '/api/resource-usage',
      (shelf.Request r) => _withAuth(r, (req, _) => _resourceUsageHandler(req)),
    );
    router.get(
      '/api/knowledge/vector-distribution',
      (shelf.Request r) =>
          _withAuth(r, (req, _) => _knowledgeVectorDistributionHandler(req)),
    );
    router.get(
      '/api/knowledge/hit-detail',
      (shelf.Request r) =>
          _withAuth(r, (req, _) => _knowledgeHitDetailHandler(req)),
    );
    router.get(
      '/api/harness/session',
      (shelf.Request r) => _withAuth(r, (_, _) => _harnessSessionHandler()),
    );
    // Plugin Service: 列出插件状态 / 安装 / 更新 / 卸载 / 重新扫描
    router.get(
      '/api/plugins',
      (shelf.Request r) => _withAuth(r, (_, _) => _listPluginsHandler()),
    );
    router.post(
      '/api/plugins/install',
      (shelf.Request r) => _withAuth(r, (req, _) => _pluginInstallHandler(req)),
    );
    router.post(
      '/api/plugins/update',
      (shelf.Request r) => _withAuth(r, (req, _) => _pluginUpdateHandler(req)),
    );
    router.post(
      '/api/plugins/uninstall',
      (shelf.Request r) =>
          _withAuth(r, (req, _) => _pluginUninstallHandler(req)),
    );
    router.post(
      '/api/plugins/rescan',
      (shelf.Request r) => _withAuth(r, (_, _) => _pluginRescanHandler()),
    );
    router.post(
      '/api/plugins/check-update',
      (shelf.Request r) =>
          _withAuth(r, (req, _) => _pluginCheckUpdateHandler(req)),
    );
    router.get(
      '/api/settings/preferences',
      (shelf.Request r) => _withAuth(r, (_, _) => _getPreferencesHandler()),
    );
    router.put(
      '/api/settings/preferences',
      (shelf.Request r) =>
          _withAuth(r, (req, _) => _putPreferencesHandler(req)),
    );
    router.put(
      '/api/settings/models/reasoning-effort',
      (shelf.Request r) => _withAuth(
        r,
        (req, auth) => _putModelReasoningEffortHandler(req, auth),
      ),
    );

    return router;
  }

  shelf.Response _shelfNotFound(shelf.Request request) =>
      _json(HttpStatus.notFound, <String, Object?>{'error': 'not_found'});

  /// CORS 头 + OPTIONS 预检统一处理。
  shelf.Middleware _corsMiddleware() {
    const baseHeaders = <String, String>{
      'access-control-allow-methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
      'access-control-allow-headers':
          'authorization,content-type,x-openhand-device-id,x-openhand-source,x-openhand-device-mac,x-openhand-device-name,x-openhand-device-platform,x-openhand-os-name,x-openhand-os-version,x-openhand-browser-name,x-openhand-browser-version,x-openhand-web-client-version,x-openhand-locale,x-openhand-timezone,x-openhand-screen-class',
    };
    return (innerHandler) {
      return (shelf.Request request) async {
        final origin = request.headers['origin']?.trim();
        final hasOrigin = origin != null && origin.isNotEmpty;
        final allowsOrigin =
            hasOrigin && isSameHttpOrigin(request.requestedUri, origin);
        if (hasOrigin && !allowsOrigin) {
          return _json(HttpStatus.forbidden, const <String, Object?>{
            'error': 'cross_origin_request_blocked',
          });
        }
        final corsHeaders = allowsOrigin
            ? <String, String>{
                ...baseHeaders,
                'access-control-allow-origin': origin,
                'vary': 'Origin',
              }
            : const <String, String>{};
        if (request.method == 'OPTIONS') {
          return shelf.Response(HttpStatus.noContent, headers: corsHeaders);
        }
        final response = await innerHandler(request);
        return corsHeaders.isEmpty
            ? response
            : response.change(headers: corsHeaders);
      };
    };
  }

  /// 并发限流 + 请求/字节计数 + 异常兜底 + 访问日志。
  /// 与旧 `_handleRequest` 的副作用一一对应：超过 `maxConcurrentRequests`
  /// 直接返回 429，否则在 finally 写访问日志，按状态码挑选 level。
  shelf.Middleware _telemetryAndLimitMiddleware() {
    return (innerHandler) {
      return (shelf.Request request) async {
        final connectionInfo =
            request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
        final remoteAddress =
            connectionInfo?.remoteAddress.address ?? 'unknown';
        final remoteEndpoint = webGatewayFormatRemoteEndpoint(
          remoteAddress,
          connectionInfo?.remotePort,
        );
        final clientName = _requestMetricClientName(request);
        final protocol = _requestMetricProtocol(request);
        var collectMetrics = !webGatewayIsOpsSnapshotRequest(
          request.method,
          request.requestedUri.path,
        );
        var requestBytes = request.contentLength ?? 0;
        final observedRequest = request.contentLength == null
            ? request.change(
                body: request.read().map((chunk) {
                  requestBytes += chunk.length;
                  return chunk;
                }),
              )
            : request;
        if (collectMetrics) {
          _totalRequests++;
        }
        final stopwatch = Stopwatch()..start();
        if (_inFlightRequests >= _config.maxConcurrentRequests) {
          stopwatch.stop();
          final limited = _json(
            HttpStatus.tooManyRequests,
            const <String, Object?>{'error': 'too_many_requests'},
          );
          final responseBytes = limited.contentLength ?? 0;
          if (!collectMetrics) {
            collectMetrics = true;
            _totalRequests++;
          }
          if (collectMetrics) {
            _totalErrors++;
            _blockedRequests++;
            _totalBytesIn += requestBytes;
            _totalBytesOut += responseBytes;
            _observeRequestMetrics(
              method: request.method,
              path: request.requestedUri.path,
              statusCode: HttpStatus.tooManyRequests,
              durationMs: stopwatch.elapsedMilliseconds,
              requestBytes: requestBytes,
              responseBytes: responseBytes,
              remoteAddress: remoteAddress,
              remoteEndpoint: remoteEndpoint,
              clientName: clientName,
              protocol: protocol,
              errorPath: request.requestedUri.path,
              errorMessage: 'too_many_requests',
            );
            _log(
              WebGatewayLogLevel.warn,
              'HTTP',
              '请求被并发限制拒绝',
              <String, Object?>{
                'path': request.requestedUri.path,
                'active_requests': _activeRequests,
                'limit': _config.maxConcurrentRequests,
              },
            );
          }
          return limited;
        }
        _inFlightRequests++;
        final countedActiveRequest = collectMetrics;
        if (countedActiveRequest) _activeRequests++;
        var statusCode = 0;
        var responseBytes = 0;
        String? errorText;
        try {
          final response = await innerHandler(observedRequest);
          statusCode = response.statusCode;
          responseBytes = response.contentLength ?? 0;
          return response;
        } on _WebGatewayRequestException catch (error) {
          statusCode = error.statusCode;
          errorText = error.errorCode;
          final rejected = _json(statusCode, <String, Object?>{
            'error': error.errorCode,
          });
          responseBytes = rejected.contentLength ?? 0;
          return rejected;
        } catch (error, stack) {
          statusCode = HttpStatus.internalServerError;
          errorText = messageGatewayFailureMessage(error, fallback: '请求处理失败。');
          _lastError = errorText;
          silentLog('web_message_platform_service', '处理请求', error, stack);
          final fallback = _json(
            HttpStatus.internalServerError,
            const <String, Object?>{'error': 'internal_error'},
          );
          responseBytes = fallback.contentLength ?? 0;
          return fallback;
        } finally {
          stopwatch.stop();
          _inFlightRequests = math.max(0, _inFlightRequests - 1);
          if (!collectMetrics &&
              webGatewayShouldCollectRequestMetrics(
                method: request.method,
                path: request.requestedUri.path,
                statusCode: statusCode,
              )) {
            collectMetrics = true;
            _totalRequests++;
          }
          if (collectMetrics) {
            if (countedActiveRequest) {
              _activeRequests = math.max(0, _activeRequests - 1);
            }
            _totalBytesIn += requestBytes;
            _totalBytesOut += responseBytes;
            if (statusCode >= 400 || statusCode <= 0) {
              _totalErrors++;
              if (webGatewayIsBlockedStatusCode(statusCode)) {
                _blockedRequests++;
              }
            }
            // 在 telemetry 写日志前更新指标，确保 snapshot 与日志同源（同一窗口同一观察者）。
            _observeRequestMetrics(
              method: request.method,
              path: request.requestedUri.path,
              statusCode: statusCode,
              durationMs: stopwatch.elapsedMilliseconds,
              requestBytes: requestBytes,
              responseBytes: responseBytes,
              remoteAddress: remoteAddress,
              remoteEndpoint: remoteEndpoint,
              clientName: clientName,
              protocol: protocol,
              errorPath: errorText != null ? request.requestedUri.path : null,
              errorMessage: errorText,
            );
            final level = statusCode >= 500
                ? WebGatewayLogLevel.error
                : statusCode >= 400
                ? WebGatewayLogLevel.warn
                : (_config.telemetryEnabled
                      ? WebGatewayLogLevel.telemetry
                      : WebGatewayLogLevel.info);
            final shouldLog =
                _config.loggingEnabled ||
                _config.telemetryEnabled ||
                statusCode >= 400;
            if (shouldLog) {
              _log(
                level,
                'HTTP',
                '${request.method} ${request.requestedUri.path} -> $statusCode ${stopwatch.elapsedMilliseconds}ms',
                <String, Object?>{
                  'method': request.method,
                  'path': request.requestedUri.path,
                  'query': redactSensitiveStringMap(
                    request.requestedUri.queryParameters,
                  ),
                  'status_code': statusCode,
                  'duration_ms': stopwatch.elapsedMilliseconds,
                  'remote_ip': connectionInfo?.remoteAddress.address,
                  'remote_port': connectionInfo?.remotePort,
                  'user_agent': clipNullableText(
                    request.headers[HttpHeaders.userAgentHeader],
                    _maxAuthUserAgentCharacters,
                    suffix: '',
                  ),
                  'content_length': requestBytes,
                  'response_bytes': responseBytes,
                  'active_requests': _activeRequests,
                  if (errorText != null) 'error': errorText,
                },
              );
            }
          }
        }
      };
    };
  }

  /// 把 handler 包成「先鉴权后调用」的入口；401 时返回 JSON 错误。
  Future<shelf.Response> _withAuth(
    shelf.Request request,
    Future<shelf.Response> Function(shelf.Request, _WebGatewayAuthSession)
    handler,
  ) async {
    final auth = _authorize(request);
    if (auth == null) {
      return _errorJson(HttpStatus.unauthorized, 'unauthorized');
    }
    return handler(request, auth);
  }

  shelf.Response _apiHealth(shelf.Request request) {
    return _json(HttpStatus.ok, <String, Object?>{
      'status': 'ok',
      'service': webMessagePlatformBuiltinName,
      'state': _state.name,
      'time': DateTime.now().toUtc().toIso8601String(),
    });
  }

  shelf.Response _apiMeta(shelf.Request request) {
    // 完整 payload 里有用户自定义指令正文、模型与供应商清单、模板、快捷键、
    // 工作区文件策略——都是私密配置。开了鉴权就只对已登录会话给完整版，
    // 未登录只给登录页渲染真正需要的那几项。
    if (_config.authEnabled && _authorize(request) == null) {
      return _json(HttpStatus.ok, _publicMetaPayload());
    }
    return _json(HttpStatus.ok, _metaPayload());
  }

  /// 登录前可匿名读取的最小元数据：服务标识、是否需要鉴权，以及登录页保持
  /// 与桌面端一致外观所需的主题与偏好。不含任何用户内容。
  Map<String, Object?> _publicMetaPayload() {
    return <String, Object?>{
      'service': <String, Object?>{
        'id': webMessagePlatformBuiltinId,
        'name': webMessagePlatformBuiltinName,
        'description': _config.description,
        'auth_enabled': _config.authEnabled,
      },
      'preferences': <String, Object?>{
        'reduce_motion': _settingsController.reduceMotion,
        'locale': _settingsController.locale.toLanguageTag(),
        'language_storage_value': _settingsController.language.storageValue,
        'dialog_animation_settings': _settingsController.dialogAnimationSettings
            .toJson(),
      },
      'theme': _theme.toJson(),
    };
  }

  Future<shelf.Response> _opsSnapshot() async {
    if (!_config.opsEnabled) {
      return _errorJson(HttpStatus.forbidden, 'ops_disabled');
    }
    return _json(HttpStatus.ok, (await runtimeSnapshotAsync()).toJson());
  }

  List<Map<String, Object?>> _templateAssociationsForMcpServer(
    McpServer server,
  ) {
    final visibleTemplateIds = server.visibleTemplateIds;
    if (visibleTemplateIds == null) {
      return const <Map<String, Object?>>[
        <String, Object?>{
          'template_id': '*',
          'label_zh': '全部线程模板',
          'label_en': 'All thread templates',
          'capabilities': <Object?>[],
        },
      ];
    }
    final raw = _mcpController.serverSearchText(server);
    final templatesById = <String, AiPromptTemplateInfo>{
      for (final template in AiPromptTemplatePolicies.templateInfos)
        template.id: template,
    };
    final sortedTemplateIds = visibleTemplateIds.toList(growable: false)
      ..sort((left, right) {
        final leftIndex = AiPromptTemplatePolicies.templateInfos.indexWhere(
          (template) => template.id == left,
        );
        final rightIndex = AiPromptTemplatePolicies.templateInfos.indexWhere(
          (template) => template.id == right,
        );
        if (leftIndex == -1 && rightIndex == -1) return left.compareTo(right);
        if (leftIndex == -1) return 1;
        if (rightIndex == -1) return -1;
        return leftIndex.compareTo(rightIndex);
      });
    return sortedTemplateIds
        .map((templateId) {
          final template = templatesById[templateId];
          final spec = TemplateRuntimeDependencyRegistry.byTemplateId(
            templateId,
          );
          return <String, Object?>{
            'template_id': templateId,
            'label_zh': template?.name ?? templateId,
            'label_en': template?.nameEn ?? template?.name ?? templateId,
            'capabilities': (spec?.matchingCapabilities(raw) ?? const [])
                .map(
                  (capability) => <String, Object?>{
                    'id': capability.id,
                    'label_zh': capability.labelZh,
                    'label_en': capability.labelEn,
                    if (capability.packageName != null)
                      'package_name': capability.packageName,
                    'openhand_managed': capability.openHandManaged,
                  },
                )
                .toList(growable: false),
          };
        })
        .toList(growable: false);
  }

  List<Map<String, Object?>> _templateAssociationsForPlugin(String pluginId) {
    return TemplateRuntimeDependencyRegistry.specsForPlugin(pluginId)
        .map(
          (spec) => <String, Object?>{
            'template_id': spec.templateId,
            'label_zh': spec.labelZh,
            'label_en': spec.labelEn,
          },
        )
        .toList(growable: false);
  }

  /// Toolbox: 列出当前已加载 MCP 服务器（含 enabled / type / 摘要）。
  Future<shelf.Response> _listMcpServersHandler() async {
    final items = _mcpController.runtimeServers
        .map(
          (server) => <String, Object?>{
            'name': server.name,
            'type': server.type.name,
            'enabled': server.enabled,
            'summary': server.summary,
            'url': server.url,
            'command': server.command,
            'args': server.args,
            'tool_count': _mcpController
                .toolCatalogFor(server.name)
                .tools
                .length,
            'template_associations': _templateAssociationsForMcpServer(server),
          },
        )
        .toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{'items': items});
  }

  Future<shelf.Response> _listBuiltinToolsHandler() async {
    final items = _settingsController.builtinToolConfigs
        .map((config) {
          final runtimeTool = AiToolRuntimeService.builtinToolDefault(
            config.kind,
          );
          return <String, Object?>{
            'id': runtimeTool?.definition.name ?? config.effectiveName,
            'name': config.effectiveName,
            'kind': config.kind.name,
            'enabled': config.enabled,
            'load_strategy': config.loadStrategy.name,
          };
        })
        .toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{'items': items});
  }

  /// Toolbox: 列出已安装本地技能（来自 SkillsController）。
  Future<shelf.Response> _listSkillsHandler() async {
    final Iterable<LocalSkill> visibleSkills =
        webGatewayIsDenyAllSelection(_config.allowedSkillNames)
        ? const <LocalSkill>[]
        : _config.allowedSkillNames.isEmpty
        ? _skillsController.skills
        : _skillsController.skills.where(
            (skill) => _config.allowedSkillNames.contains(skill.name),
          );
    final items = visibleSkills
        .map(
          (skill) => <String, Object?>{
            'name': skill.name,
            'description': skill.description,
            'directory_path': skill.displayDirectoryPath,
            'relative_directory_path': skill.relativeDirectoryPath,
            'has_default_prompt': (skill.defaultPrompt ?? '').trim().isNotEmpty,
            'emoji_icon': skill.emojiIcon,
          },
        )
        .toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{
      'items': items,
      'storage_path': _skillsController.storagePath,
    });
  }

  /// Toolbox: 列出用户记忆（按时间倒序）。仅暴露 id / type / preview /
  /// title / tags / created_at — 不暴露完整 content 以降低敏感信息泄露面。
  Future<shelf.Response> _listMemoriesHandler() async {
    final items = _memoryController.entries
        .map(
          (entry) => <String, Object?>{
            'id': entry.id,
            'type': entry.type,
            'title': entry.displayTitle,
            'preview': entry.preview,
            'tags': entry.tags,
            'created_at': entry.createdAtStorageValue,
            'is_user_profile': entry.isUserProfile,
            'is_auto_learned': entry.isAutoLearned,
          },
        )
        .toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{'items': items});
  }

  /// Toolbox: 列出定时任务（CronEntry）。包含状态 / 下次运行时间 /
  /// 最近退出码 / 连续失败计数等，便于 Web 侧只读监控。
  Future<shelf.Response> _listCronsHandler() async {
    final items = _cronsController.entries
        .map(
          (entry) => <String, Object?>{
            'id': entry.id,
            'name': entry.name,
            'description': entry.description,
            'enabled': entry.enabled,
            'status': entry.status.name,
            'cron_expression': entry.cronExpression,
            'script_type': entry.scriptType.name,
            'tags': entry.tags,
            'last_run_at': entry.lastRunAt?.toUtc().toIso8601String(),
            'next_run_at': entry.nextRunAt?.toUtc().toIso8601String(),
            'last_exit_code': entry.lastExitCode,
            'consecutive_failures': entry.consecutiveFailures,
          },
        )
        .toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{'items': items});
  }

  Future<shelf.Response> _listHooksHandler() async {
    final items = _hooksController.entries
        .map(
          (entry) => <String, Object?>{
            'id': entry.id,
            'label': entry.label,
            'event': entry.event.storageValue,
            'enabled': entry.enabled,
            'timeout_seconds': entry.timeoutSeconds,
          },
        )
        .toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{'items': items});
  }

  Future<shelf.Response> _listKnowledgeSourcesHandler() async {
    if (!_config.knowledgeBaseEnabled) {
      return _json(HttpStatus.ok, <String, Object?>{
        'items': const <Object?>[],
        'disabled': true,
      });
    }
    final controller = _knowledgeBaseController;
    if (controller == null) {
      return _errorJson(
        HttpStatus.serviceUnavailable,
        'knowledge_base_unavailable',
      );
    }
    final items = controller.sources
        .map(
          (source) => <String, Object?>{
            'id': source.id,
            'title': source.title,
            'kind': source.kind,
            'status': source.status,
            'size_bytes': source.sizeBytes,
            'updated_at': source.updatedAt.toUtc().toIso8601String(),
          },
        )
        .toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{'items': items});
  }

  Future<shelf.Response> _listAgentsHandler() async {
    final items = _exposedWebAgents()
        .map(
          (agent) => <String, Object?>{
            'id': agent.id,
            'name': agent.name,
            'position': agent.position,
            'department': agent.department,
            'enabled': agent.enabled,
            'lifecycle_state': agent.lifecycleState.storageValue,
            'skill_count': agent.skillNames.length,
            'knowledge_count': agent.knowledgeSourceIds.length,
            'memory_count': agent.memoryIds.length,
          },
        )
        .toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{'items': items});
  }

  Future<shelf.Response> _resourceUsageHandler(shelf.Request request) async {
    final kind = AiResourceUsageKind.fromStorage(
      request.url.queryParameters['kind'],
    );
    if (kind == null) {
      return _errorJson(HttpStatus.badRequest, 'resource_usage_kind_invalid');
    }
    final store = _sessionController.toolUsagePromotionStore;
    await store.initialize();
    final snapshot = store.snapshot(
      kind: kind,
      preferredSessionId: request.url.queryParameters['session_id'],
    );
    return _json(HttpStatus.ok, snapshot.toJson());
  }

  Future<shelf.Response> _knowledgeVectorDistributionHandler(
    shelf.Request request,
  ) async {
    if (!_config.knowledgeBaseEnabled) {
      return _errorJson(HttpStatus.forbidden, 'knowledge_base_disabled');
    }
    final controller = _knowledgeBaseController;
    if (controller == null) {
      return _errorJson(
        HttpStatus.serviceUnavailable,
        'knowledge_base_unavailable',
      );
    }
    final rawMaxPoints = request.url.queryParameters['max_points'] ?? '';
    final maxPoints = nonNegativeIntFromText(
      rawMaxPoints,
      fallback: kKnowledgeVectorDistributionDefaultMaxPoints,
    ).clamp(1, 2000).toInt();
    try {
      final distribution = await controller.loadVectorDistribution(
        maxPoints: maxPoints,
      );
      return _json(HttpStatus.ok, <String, Object?>{
        'distribution': distribution.toJson(),
      });
    } catch (error, stack) {
      silentLog('web_message_platform_service', '读取知识向量分布', error, stack);
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'error': 'knowledge_vector_distribution_failed',
        'message': messageGatewayFailureMessage(error, fallback: '知识向量分布读取失败。'),
      });
    }
  }

  Future<shelf.Response> _knowledgeHitDetailHandler(
    shelf.Request request,
  ) async {
    if (!_config.knowledgeBaseEnabled) {
      return _errorJson(HttpStatus.forbidden, 'knowledge_base_disabled');
    }
    final controller = _knowledgeBaseController;
    if (controller == null) {
      return _errorJson(
        HttpStatus.serviceUnavailable,
        'knowledge_base_unavailable',
      );
    }
    final sourceId = (request.url.queryParameters['source_id'] ?? '').trim();
    final chunkId = (request.url.queryParameters['chunk_id'] ?? '').trim();
    if (sourceId.isEmpty || chunkId.isEmpty) {
      return _errorJson(
        HttpStatus.badRequest,
        'source_id_and_chunk_id_required',
      );
    }
    try {
      final source = await controller.loadSource(sourceId);
      if (source == null) {
        return _errorJson(HttpStatus.notFound, 'knowledge_source_not_found');
      }
      final chunks = await controller.loadChunksForSource(sourceId);
      KnowledgeChunk? chunk;
      for (final item in chunks) {
        if (item.id == chunkId) {
          chunk = item;
          break;
        }
      }
      if (chunk == null) {
        return _json(HttpStatus.notFound, <String, Object?>{
          'error': 'knowledge_chunk_not_found',
          'source': _knowledgeSourcePayload(source),
        });
      }
      return _json(HttpStatus.ok, <String, Object?>{
        'source': _knowledgeSourcePayload(source),
        'chunk': _knowledgeChunkPayload(chunk),
      });
    } catch (error, stack) {
      silentLog('web_message_platform_service', '读取知识命中详情', error, stack);
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'error': 'knowledge_hit_detail_failed',
        'message': messageGatewayFailureMessage(error, fallback: '知识命中详情读取失败。'),
      });
    }
  }

  Map<String, Object?> _knowledgeSourcePayload(KnowledgeSource source) {
    return <String, Object?>{
      'id': source.id,
      'title': source.title,
      'kind': source.kind,
      'original_path': source.originalPath,
      'stored_path': source.storedPath,
      'mime_type': source.mimeType,
      'size_bytes': source.sizeBytes,
      'content_hash': source.contentHash,
      'status': source.status,
      'error_message': source.errorMessage,
      'document_time': source.documentTime?.toUtc().toIso8601String(),
      'imported_at': source.importedAt.toUtc().toIso8601String(),
      'indexed_at': source.indexedAt?.toUtc().toIso8601String(),
      'created_at': source.createdAt.toUtc().toIso8601String(),
      'updated_at': source.updatedAt.toUtc().toIso8601String(),
      'metadata': source.metadata,
    };
  }

  Map<String, Object?> _knowledgeChunkPayload(KnowledgeChunk chunk) {
    return <String, Object?>{
      'id': chunk.id,
      'source_id': chunk.sourceId,
      'chunk_index': chunk.chunkIndex,
      'parent_chunk_id': chunk.parentChunkId,
      'title': chunk.title,
      'heading_path': chunk.headingPath,
      'content': chunk.content,
      'content_hash': chunk.contentHash,
      'char_count': chunk.charCount,
      'token_estimate': chunk.tokenEstimate,
      'start_offset': chunk.startOffset,
      'end_offset': chunk.endOffset,
      'page_number': chunk.pageNumber,
      'document_time': chunk.documentTime?.toUtc().toIso8601String(),
      'created_at': chunk.createdAt.toUtc().toIso8601String(),
      'updated_at': chunk.updatedAt.toUtc().toIso8601String(),
      'metadata': chunk.metadata,
      'tags': chunk.tags,
    };
  }

  /// Toolbox: 持久化的 Harness Engineering 会话快照 (单实例)。
  /// App 同时只跑一个 Harness session, 持久化在 SQLite 的 harness_sessions 表;
  /// orchestrator 是 home page 内部状态, 不直接暴露到 service, 故 web 走 store
  /// 的最近一次写入。返回 `{record: null}` 表示尚未运行过 Harness。
  Future<shelf.Response> _harnessSessionHandler() async {
    try {
      final record = await HarnessSessionStore().load();
      return _json(HttpStatus.ok, <String, Object?>{
        'record': record?.toJson(),
      });
    } catch (e, st) {
      silentLog('web_message_platform_service', '加载 Harness 会话', e, st);
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'error': 'harness_load_failed',
        'message': messageGatewayFailureMessage(e, fallback: 'Harness 会话加载失败。'),
      });
    }
  }

  /// Settings: 暴露一组 Web 远程可读 / 可改的核心 prefs。
  /// 字段精挑细选: reduce_motion (动画) / locale (UI 语言) /
  /// dialog_animation_settings (只读弹窗动画同步) /
  /// memory_enabled (是否在 prompt 注入用户记忆) /
  /// ai_message_compression_threshold_chars (单消息压缩阈值)。
  /// 其余设置仍只能在 App 端修改 (避免 Web 误改影响本机正在跑的会话)。
  Future<shelf.Response> _getPreferencesHandler() async {
    return _json(HttpStatus.ok, _preferencesPayload());
  }

  Map<String, Object?> _preferencesPayload({Map<String, Object?>? updated}) {
    return <String, Object?>{
      if (updated != null) 'updated': updated,
      'reduce_motion': _settingsController.reduceMotion,
      'locale': _settingsController.locale.toLanguageTag(),
      'language_storage_value': _settingsController.language.storageValue,
      'dialog_animation_settings': _settingsController.dialogAnimationSettings
          .toJson(),
      'memory_enabled': _settingsController.memoryEnabled,
      'ai_message_compression_threshold_chars':
          _settingsController.aiMessageCompressionThresholdChars,
      'limits': <String, Object?>{
        'ai_message_compression_threshold_chars_min':
            AppSettingsSnapshot.minAiMessageCompressionThresholdChars,
        'ai_message_compression_threshold_chars_max':
            AppSettingsSnapshot.maxAiMessageCompressionThresholdChars,
      },
      'language_options': AppLanguage.values
          .map((l) => l.storageValue)
          .toList(growable: false),
    };
  }

  Future<shelf.Response> _putPreferencesHandler(shelf.Request request) async {
    final body = await _readJsonBody(request, maxBytes: 4 * kBytesPerKiB);
    final updated = <String, Object?>{};
    if (body.containsKey('reduce_motion')) {
      final value = body['reduce_motion'] == true;
      await _settingsController.updateReduceMotion(value);
      updated['reduce_motion'] = _settingsController.reduceMotion;
    }
    if (body.containsKey('language_storage_value')) {
      final raw = body['language_storage_value'];
      if (raw is String && raw.isNotEmpty) {
        final lang = appLanguageFromStorage(raw);
        await _settingsController.updateLanguage(lang);
        updated['language_storage_value'] =
            _settingsController.language.storageValue;
      }
    }
    if (body.containsKey('ai_message_compression_threshold_chars')) {
      final raw = body['ai_message_compression_threshold_chars'];
      if (raw is num) {
        await _settingsController.updateAiMessageCompressionThresholdChars(
          raw.toInt(),
        );
        updated['ai_message_compression_threshold_chars'] =
            _settingsController.aiMessageCompressionThresholdChars;
      }
    }
    _log(WebGatewayLogLevel.warn, 'SETTINGS', 'Web 修改偏好设置', updated);
    return _json(HttpStatus.ok, _preferencesPayload(updated: updated));
  }

  Future<shelf.Response> _putModelReasoningEffortHandler(
    shelf.Request request,
    _WebGatewayAuthSession auth,
  ) async {
    final body = await _readJsonBody(request, maxBytes: 4 * kBytesPerKiB);
    final modelKey = _string(body['model_key'], '').trim();
    final effort = _string(body['effort'], '').trim().toLowerCase();
    final sessionId = _string(body['session_id'], '').trim();
    final parsed = _parseModelKey(modelKey);
    if (parsed == null || effort.isEmpty || sessionId.isEmpty) {
      return _errorJson(
        HttpStatus.badRequest,
        'model_key_effort_and_session_id_required',
      );
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    if (await _resolveSessionInputCacheModelSelectionLocked(session)) {
      return _json(HttpStatus.conflict, <String, Object?>{
        'error': 'input_cache_model_selection_locked',
        'message': '已锁定服务商、模型与推理强度以保证缓存命中。',
      });
    }
    if (!_allowedModels().any((model) => model.key == modelKey)) {
      return _errorJson(HttpStatus.notFound, 'model_not_found_or_not_allowed');
    }
    AiModelConfig? provider;
    for (final item in _settingsController.aiModels) {
      if (item.id == parsed.providerId &&
          item.allModelIds.contains(parsed.modelId)) {
        provider = item;
        break;
      }
    }
    if (provider == null) {
      return _errorJson(HttpStatus.notFound, 'model_not_found_or_not_allowed');
    }
    final resolvedModel = provider.copyWith(modelId: parsed.modelId);
    final profile = resolvedModel.profileFor(parsed.modelId);
    final selectable = profile.reasoningEffortOptions
        .where((option) => option.isSelectable)
        .toList(growable: false);
    if (!resolvedModel.resolvedReasoningEffortControlEnabled ||
        !selectable.any((option) => option.value.toLowerCase() == effort)) {
      return _errorJson(HttpStatus.conflict, 'reasoning_effort_not_supported');
    }
    final saved = await _settingsController.updateAiModelReasoningEffort(
      parsed.providerId,
      parsed.modelId,
      effort,
    );
    if (!saved) {
      return _errorJson(
        HttpStatus.internalServerError,
        'reasoning_effort_save_failed',
      );
    }
    final updatedProvider = _settingsController.aiModels
        .where((item) => item.id == parsed.providerId)
        .firstOrNull;
    final updatedModel = updatedProvider?.copyWith(modelId: parsed.modelId);
    _log(
      WebGatewayLogLevel.success,
      'SETTINGS',
      'Web 修改模型推理强度',
      <String, Object?>{
        'model_key': modelKey,
        'effort': updatedModel?.resolvedReasoningEffort ?? effort,
      },
    );
    return _json(HttpStatus.ok, <String, Object?>{
      'model_key': modelKey,
      'reasoning_effort': updatedModel?.resolvedReasoningEffort ?? effort,
    });
  }

  // 插件服务处理器

  Map<String, Object?> _pluginPayload(PluginInfo p) {
    return <String, Object?>{
      'id': p.id,
      'name': p.name,
      'description': p.description,
      'status': p.status.name,
      'enabled': p.enabled,
      'installed_version': p.installedVersion,
      'latest_version': p.latestVersion,
      'install_path': p.installPath,
      'dependencies': p.dependencies,
      'dependents': p.dependents,
      'supports_uninstall': p.supportsUninstall,
      'error_message': p.errorMessage,
      'has_update': p.hasUpdate,
      'template_associations': _templateAssociationsForPlugin(p.id),
    };
  }

  Future<shelf.Response> _listPluginsHandler() async {
    try {
      final controller = _pluginServiceController;
      if (controller == null) {
        return _json(HttpStatus.ok, <String, Object?>{'items': <Object?>[]});
      }
      final items = controller.plugins
          .map(_pluginPayload)
          .toList(growable: false);
      return _json(HttpStatus.ok, <String, Object?>{'items': items});
    } catch (error, stack) {
      silentLog('web_message_platform_service', '读取插件列表', error, stack);
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'error': 'plugin_list_failed',
        'message': messageGatewayFailureMessage(error, fallback: '插件列表读取失败。'),
      });
    }
  }

  Future<shelf.Response> _pluginInstallHandler(shelf.Request request) {
    return _pluginMutationHandler(
      request,
      (controller, pluginId) => controller.installPlugin(pluginId),
      includeInstalledVersion: true,
    );
  }

  Future<shelf.Response> _pluginUpdateHandler(shelf.Request request) {
    return _pluginMutationHandler(
      request,
      (controller, pluginId) => controller.updatePlugin(pluginId),
      includeInstalledVersion: true,
    );
  }

  Future<shelf.Response> _pluginUninstallHandler(shelf.Request request) {
    return _pluginMutationHandler(
      request,
      (controller, pluginId) => controller.uninstallPlugin(pluginId),
    );
  }

  Future<shelf.Response> _pluginMutationHandler(
    shelf.Request request,
    Future<bool> Function(PluginServiceController controller, String pluginId)
    operation, {
    bool includeInstalledVersion = false,
  }) {
    return _pluginOperationHandler(request, (controller, pluginId) async {
      final success = await operation(controller, pluginId);
      return _json(HttpStatus.ok, <String, Object?>{
        'success': success,
        'message': controller.errorMessage,
        if (includeInstalledVersion)
          'new_version': controller.pluginById(pluginId)?.installedVersion,
      });
    });
  }

  Future<shelf.Response> _pluginOperationHandler(
    shelf.Request request,
    Future<shelf.Response> Function(
      PluginServiceController controller,
      String pluginId,
    )
    operation,
  ) async {
    final body = await _readJsonBody(request, maxBytes: 1024);
    final pluginId = body['plugin_id'] as String?;
    if (pluginId == null || pluginId.isEmpty) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'success': false,
        'message': 'plugin_id is required',
      });
    }
    final controller = _pluginServiceController;
    if (controller == null) {
      return _json(HttpStatus.serviceUnavailable, <String, Object?>{
        'success': false,
        'message': 'Plugin service not available',
      });
    }
    final busyResponse = _pluginBusyResponse(controller);
    if (busyResponse != null) return busyResponse;
    return operation(controller, pluginId);
  }

  Future<shelf.Response> _pluginRescanHandler() async {
    final controller = _pluginServiceController;
    if (controller == null) {
      return _json(HttpStatus.ok, <String, Object?>{'items': <Object?>[]});
    }
    final busyResponse = _pluginBusyResponse(controller);
    if (busyResponse != null) return busyResponse;
    await controller.rescan();
    final items = controller.plugins
        .map(_pluginPayload)
        .toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{'items': items});
  }

  Future<shelf.Response> _pluginCheckUpdateHandler(shelf.Request request) {
    return _pluginOperationHandler(request, (controller, pluginId) async {
      final plugin = await controller.checkPluginUpdate(pluginId);
      if (plugin == null) {
        return _json(HttpStatus.notFound, <String, Object?>{
          'success': false,
          'message': controller.errorMessage ?? 'Plugin not found',
        });
      }
      return _json(HttpStatus.ok, <String, Object?>{
        'success': true,
        'message': controller.errorMessage,
        'item': _pluginPayload(controller.pluginById(pluginId) ?? plugin),
      });
    });
  }

  shelf.Response? _pluginBusyResponse(PluginServiceController controller) {
    if (!controller.isBusy) return null;
    return _json(HttpStatus.conflict, <String, Object?>{
      'success': false,
      'message': 'Another plugin operation is already in progress',
    });
  }

  Map<String, Object?> _metaPayload() {
    return <String, Object?>{
      'service': <String, Object?>{
        'id': webMessagePlatformBuiltinId,
        'name': webMessagePlatformBuiltinName,
        'description': _config.description,
        'listen_host': _config.listenHost,
        'listen_port': _config.listenPort,
        'bound_url': boundUrl,
        'bound_port': _server?.port,
        'port_fallback_active':
            _server != null && _server!.port != _config.listenPort,
        'accessible_urls': accessibleUrls,
        'auto_start_on_launch': _config.autoStartOnLaunch,
        'auto_reload_on_change': _config.autoReloadOnChange,
        'auth_enabled': _config.authEnabled,
        'telemetry_enabled': _config.telemetryEnabled,
        'logging_enabled': _config.loggingEnabled,
        'ops_enabled': _config.opsEnabled,
        'plan_mode_enabled': _config.planModeEnabled,
        'agents_enabled': _config.agentsEnabled,
        'knowledge_base_enabled': _config.knowledgeBaseEnabled,
        'read_aloud_enabled': _config.readAloudEnabled,
        'translation_enabled': _config.translationEnabled,
        'feedback_enabled': _config.feedbackEnabled,
        'regeneration_enabled': _config.regenerationEnabled,
        'session_management_enabled': _config.sessionManagementEnabled,
        'single_message_token_limit': _config.singleMessageTokenLimit,
        'max_messages_per_session': _config.maxMessagesPerSession,
      },
      'message_content_settings': <String, Object?>{
        'tts_enabled': _settingsController.aiTtsSettings.enabled,
        'translation_enabled':
            _settingsController.aiTranslationSettings.enabled,
        'translation_settings_fingerprint':
            _settingsController.aiTranslationSettings.cacheFingerprint,
        'translation_model_settings_fingerprint':
            _translationModelSettingsFingerprint(),
        'message_content_format':
            _settingsController.aiMessageContentFormat.storageKey,
      },
      'workspace_files': <String, Object?>{
        'enabled': true,
        'operations_enabled': _config.workspaceFileWriteEnabled,
        'write_enabled': _config.workspaceFileWriteEnabled,
        'max_file_bytes': _config.workspaceFileMaxBytes,
        'allowed_extensions': _config.workspaceFileAllowedExtensions,
      },
      'attachments': <String, Object?>{
        'max_count': aiMessageAttachmentLimit,
        'max_file_bytes': kWebGatewayAttachmentMaxFileBytes,
        'max_total_bytes': kWebGatewayAttachmentMaxTotalBytes,
      },
      'agents': _webAgentSummaryJson(),
      'preferences': <String, Object?>{
        'reduce_motion': _settingsController.reduceMotion,
        'locale': _settingsController.locale.toLanguageTag(),
        'language_storage_value': _settingsController.language.storageValue,
        'dialog_animation_settings': _settingsController.dialogAnimationSettings
            .toJson(),
      },
      'shortcut_bindings': _shortcutBindingsPayload(),
      'theme': _theme.toJson(),
      'templates': _allowedTemplates()
          .map(
            (template) => <String, Object?>{
              'id': template.id,
              'name': template.name,
              'description': template.description,
              'icon': template.iconName,
              'internal_version': template.internalVersion,
            },
          )
          .toList(growable: false),
      'conversation_modes': _config.allowedConversationModes
          .map((item) => item.storageValue)
          .toList(growable: false),
      'message_types': _config.allowedMessageTypes
          .map((item) => item.storageValue)
          .toList(growable: false),
      'active_model_key': _activeModelKey(),
      // 暴露给 Web 端「指令胶囊条」展示用的可用用户指令清单。
      // 仅返回 allowedInstructionIds 过滤后的 enabled 条目，与 App 端
      // _ComposerInstructionsStrip 的 enabledEntries 完全对齐。
      'instructions':
          (webGatewayIsDenyAllSelection(_config.allowedInstructionIds)
                  ? const <UserInstructionEntry>[]
                  : _instructionsController.entries.where((entry) {
                      if (!entry.enabled) return false;
                      if (_config.allowedInstructionIds.isEmpty) return true;
                      return _config.allowedInstructionIds.contains(entry.id);
                    }))
              .map(
                (entry) => <String, Object?>{
                  'id': entry.id,
                  'name': entry.name,
                  'description': entry.description,
                  // body 截断到 4 KiB 防止巨型指令把 /api/meta payload 撑爆。
                  // Web 端 hover 卡片预览只用于「快速一瞥」，超过截断长度的指令，
                  // 用户在 App 端原始编辑面板查看完整 body。
                  'body': entry.body.length > 4096
                      ? clipTextByCodeUnits(entry.body, 4096, suffix: '…')
                      : entry.body,
                  'body_truncated': entry.body.length > 4096,
                },
              )
              .toList(growable: false),
      'models': _allowedModels()
          .map(
            (item) => <String, Object?>{
              'key': item.key,
              'provider_id': item.providerId,
              'provider': item.providerLabel,
              'protocol': item.protocolLabel,
              'model_id': item.modelId,
              'label': item.label,
              'supports_attachments': item.supportsAttachments,
              'supports_image_input': item.supportsImageInput,
              'supports_video_input': item.supportsVideoInput,
              'supports_audio_input': item.supportsAudioInput,
              'supports_file_input': item.supportsFileInput,
              'attachment_extensions': item.attachmentExtensions,
              'supports_image_generation': item.supportsImageGeneration,
              'supports_video_generation': item.supportsVideoGeneration,
              'supports_audio_generation': item.supportsAudioGeneration,
              'supports_text_title_generation':
                  item.supportsTextTitleGeneration,
              'supports_embeddings': item.supportsEmbeddings,
              'supports_rerank': item.supportsRerank,
              'provider_default_title_model_key':
                  item.providerDefaultTitleModelKey,
              'is_global_default_title_model': item.isGlobalDefaultTitleModel,
              'reasoning_effort_control_enabled':
                  item.reasoningEffortControlEnabled,
              'reasoning_effort': item.reasoningEffort,
              'reasoning_effort_options': item.reasoningEffortOptions
                  .where((option) => option.isSelectable)
                  .map(
                    (option) => <String, Object?>{
                      'value': option.value,
                      'label': option.labelForLocaleName(
                        _settingsController.locale.toLanguageTag(),
                      ),
                    },
                  )
                  .toList(growable: false),
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, Object?> _shortcutBindingsPayload() {
    final bindings = _settingsController.shortcutBindings;
    return <String, Object?>{
      for (final action in OpenHandShortcutAction.values)
        openHandShortcutActionStorageKey(action): <String, Object?>{
          'key_ids': bindings[action] ?? const <int>[],
          'label': formatShortcutLabel(bindings[action] ?? const <int>[]),
        },
    };
  }

  Future<shelf.Response> _login(shelf.Request request) async {
    final now = DateTime.now().toUtc();
    final remoteAddress = _requestRemoteAddress(request);
    if (!_admitLoginAttempt(remoteAddress, _monotonicStopwatch.elapsed)) {
      _log(WebGatewayLogLevel.warn, 'AUTH', '登录请求触发频率限制', <String, Object?>{
        'remote_ip': remoteAddress,
        'limit': _maxLoginAttemptsPerWindow,
      });
      return _json(HttpStatus.tooManyRequests, const <String, Object?>{
        'error': 'login_rate_limited',
      }).change(headers: const <String, String>{'retry-after': '60'});
    }
    final body = await _readJsonBody(request, maxBytes: _maxLoginBodyBytes);
    final source = WebGatewayLoginSource.fromStorage(
      _boundedAuthText(body['source'], _maxAuthMetadataCharacters),
    );
    final rawDeviceId = _string(body['device_id'], '').trim();
    final deviceId = _boundedAuthText(rawDeviceId, _maxAuthDeviceIdCharacters);
    if (deviceId.isEmpty || deviceId != rawDeviceId) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': deviceId.isEmpty ? 'device_id_required' : 'device_id_too_long',
      });
    }
    if (_config.authEnabled) {
      // 开了鉴权却没设密码时一律拒绝：口令为空字符串意味着任何客户端只要
      // 提交空密码就能通过相等比较，而网关默认监听 0.0.0.0，等于对外裸奔。
      // 这里选择拒绝而不是放行——把配置改对（设密码或关掉鉴权）才是出路。
      if (_config.password.isEmpty) {
        _log(
          WebGatewayLogLevel.warn,
          'AUTH',
          '鉴权已开启但未设置密码，拒绝全部登录',
          <String, Object?>{'device_id': deviceId, 'remote_ip': remoteAddress},
        );
        return _errorJson(HttpStatus.unauthorized, 'password_not_configured');
      }
      final username = _string(body['username'], '').trim();
      final password = _string(body['password'], '');
      final credentialsTooLong =
          clipText(username, _maxAuthCredentialCharacters, suffix: '') !=
              username ||
          clipText(password, _maxAuthCredentialCharacters, suffix: '') !=
              password;
      if (credentialsTooLong ||
          username != _config.username ||
          password != _config.password) {
        _log(WebGatewayLogLevel.warn, 'AUTH', '登录失败', <String, Object?>{
          'username': _boundedAuthText(username, _maxAuthMetadataCharacters),
          'device_id': deviceId,
          'remote_ip': remoteAddress,
        });
        return _errorJson(HttpStatus.unauthorized, 'invalid_credentials');
      }
    }
    final token = _makeToken();
    final session = _WebGatewayAuthSession(
      token: token,
      source: source,
      deviceId: deviceId,
      deviceMacAddress: _boundedAuthText(
        body['device_mac_address'],
        _maxAuthMetadataCharacters,
      ),
      deviceName: _boundedAuthText(
        body['device_name'],
        _maxAuthMetadataCharacters,
      ),
      devicePlatform: _boundedAuthText(
        body['device_platform'],
        _maxAuthMetadataCharacters,
      ),
      osName: _boundedAuthText(body['os_name'], _maxAuthMetadataCharacters),
      osVersion: _boundedAuthText(
        body['os_version'],
        _maxAuthMetadataCharacters,
      ),
      browserName: _boundedAuthText(
        body['browser_name'],
        _maxAuthMetadataCharacters,
      ),
      browserVersion: _boundedAuthText(
        body['browser_version'],
        _maxAuthMetadataCharacters,
      ),
      webClientVersion: _boundedAuthText(
        body['web_client_version'],
        _maxAuthMetadataCharacters,
      ),
      locale: _boundedAuthText(body['locale'], _maxAuthMetadataCharacters),
      timezone: _boundedAuthText(body['timezone'], _maxAuthMetadataCharacters),
      screenClass: _boundedAuthText(
        body['screen_class'],
        _maxAuthMetadataCharacters,
      ),
      loginAt: now,
      issuedAt: _monotonicStopwatch.elapsed,
      remoteAddress: remoteAddress,
      userAgent: _boundedAuthText(
        request.headers[HttpHeaders.userAgentHeader],
        _maxAuthUserAgentCharacters,
      ),
    );
    _storeAuthSession(session);
    _log(WebGatewayLogLevel.success, 'AUTH', '登录成功', session.toMetadata());
    return _json(HttpStatus.ok, <String, Object?>{
      'token': token,
      'expires_in': _authSessionTtl.inSeconds,
      'profile': session.toMetadata(),
    });
  }

  Future<shelf.Response> _logout(
    shelf.Request _,
    _WebGatewayAuthSession auth,
  ) async {
    _removeAuthSession(auth.token);
    return _json(HttpStatus.ok, const <String, Object?>{'ok': true});
  }

  Future<shelf.Response> _listSessions(
    shelf.Request request,
    _WebGatewayAuthSession auth,
  ) async {
    final page = _queryInt(request, 'page', fallback: 1, min: 1);
    final pageSize = _queryInt(
      request,
      'page_size',
      fallback: 10,
      min: 1,
      max: 50,
    );
    final canAccessAll = _authCanAccessAllSessions(auth);
    final sourceQuery =
        request.requestedUri.queryParameters['source']?.trim() ?? '';
    final deviceQuery =
        request.requestedUri.queryParameters['device_id']?.trim() ?? '';
    final scopeQuery =
        request.requestedUri.queryParameters['scope']?.trim().toLowerCase() ??
        '';
    final useAllScope = canAccessAll && scopeQuery == 'all';
    final source = useAllScope
        ? sourceQuery
        : (sourceQuery.isEmpty ? auth.source.storageValue : sourceQuery);
    final deviceId = useAllScope
        ? deviceQuery
        : (deviceQuery.isEmpty ? auth.deviceId : deviceQuery);
    final filtered =
        _sessionController.sessions
            .where((session) {
              final context = _webContext(session.metadata);
              if (source.isNotEmpty &&
                  _string(context['login_source'], '') != source) {
                return false;
              }
              if (deviceId.isNotEmpty &&
                  _string(context['device_id'], '') != deviceId) {
                return false;
              }
              return true;
            })
            .toList(growable: false)
          ..sort((a, b) {
            final updated = b.updatedAt.compareTo(a.updatedAt);
            return updated != 0 ? updated : b.id.compareTo(a.id);
          });
    final start = (page - 1) * pageSize;
    final end = math.min(filtered.length, start + pageSize);
    final items = <Map<String, Object?>>[];
    if (start < filtered.length) {
      for (final session in filtered.sublist(start, end)) {
        items.add(await _sessionSummaryWithStoredMessages(session));
      }
    }
    return _json(HttpStatus.ok, <String, Object?>{
      'items': items,
      'page': page,
      'page_size': pageSize,
      'total': filtered.length,
      'has_more': end < filtered.length,
      'sort': 'updated_at_desc,id_desc',
      'scope': useAllScope ? 'authenticated_all' : 'current_device',
    });
  }

  int _queryInt(
    shelf.Request request,
    String name, {
    required int fallback,
    int? min,
    int? max,
  }) {
    var value =
        optionalIntFromValue(request.requestedUri.queryParameters[name]) ??
        fallback;
    if (min != null && value < min) value = min;
    if (max != null && value > max) value = max;
    return value;
  }

  Future<shelf.Response> _createSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
  ) async {
    if (!_config.sessionManagementEnabled) {
      return _errorJson(HttpStatus.forbidden, 'session_management_disabled');
    }
    final body = await _readJsonBody(request);
    final templateId = _string(body['template_id'], 'default').trim();
    if (!_templateAllowed(templateId)) {
      return _errorJson(HttpStatus.forbidden, 'template_not_allowed');
    }
    final requestedMode = _string(body['mode'], 'chat').trim();
    if (requestedMode == 'goal' &&
        !aiSessionGoalModeAllowedForTemplate(templateId)) {
      return _errorJson(HttpStatus.forbidden, 'goal_mode_not_available');
    }
    if (requestedMode.isNotEmpty &&
        requestedMode != 'chat' &&
        requestedMode != 'plan' &&
        requestedMode != 'goal') {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'session_mode_invalid',
        'mode': requestedMode,
      });
    }
    if (requestedMode == 'plan' && !_config.planModeEnabled) {
      return _errorJson(HttpStatus.forbidden, 'plan_mode_disabled');
    }
    final mode = switch (requestedMode) {
      'plan' => AiSessionMode.plan,
      'goal' when aiSessionGoalModeAllowedForTemplate(templateId) =>
        AiSessionMode.goal,
      _ => AiSessionMode.chat,
    };
    final requestedModelKey = _string(body['model_key'], '').trim();
    final requestedModel = requestedModelKey.isEmpty
        ? null
        : _resolveModel(requestedModelKey);
    if (requestedModelKey.isNotEmpty && requestedModel == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'model_not_configured',
        'model_key': requestedModelKey,
      });
    }
    final title = collapseInlineWhitespace(_string(body['title'], ''));
    if (title.characters.length >
        AiSessionController.maxManualTitleCharacters) {
      return _errorJson(HttpStatus.badRequest, 'title_too_long');
    }
    final metadata = _metadataForRequest(auth, request, <String, Object?>{
      'created_via': 'web_api',
      'requested_template_id': templateId,
      'requested_mode': mode.storageValue,
      if (requestedModelKey.isNotEmpty)
        'requested_model_key': requestedModelKey,
    });
    final ok = await _sessionController.createSession(
      templateId: templateId,
      runtimeContext: await _buildRuntimeContext(templateId: templateId),
      mode: mode,
      title: title,
      initialModelProviderConfigId: requestedModel?.id ?? '',
      initialModelId: requestedModel?.modelId ?? '',
      metadata: metadata,
      awaitStartHook: false,
    );
    if (!ok || _sessionController.currentSession == null) {
      return _errorJson(HttpStatus.internalServerError, 'create_failed');
    }
    var session = _sessionController.currentSession!;
    final warnings = <String>[];
    if (templateId == kMachineExpertTemplateId) {
      try {
        final terminalMetadata = await _machineTerminalService.initialMetadata(
          sessionId: session.id,
          workingDirectory: _workspaceDirectoryPath,
          existingMetadata: session.metadata[kMachineTerminalMetadataKey],
        );
        final metadataUpdated = await _sessionController.updateSessionMetadata(
          session.id,
          <String, Object?>{kMachineTerminalMetadataKey: terminalMetadata},
        );
        if (!metadataUpdated) {
          warnings.add('machine_terminal_metadata_not_saved');
        }
        session = _sessionController.sessions.firstWhere(
          (item) => item.id == session.id,
          orElse: () => session,
        );
      } catch (error, stack) {
        warnings.add('machine_terminal_initialization_failed');
        silentLog('web_message_platform_service', '初始化机器终端', error, stack);
        final errorMessage = messageGatewayFailureMessage(
          error,
          fallback: '机器终端初始化失败。',
        );
        _log(
          WebGatewayLogLevel.warn,
          'SESSION',
          '机器终端初始化失败，会话已保留',
          <String, Object?>{'session_id': session.id, 'error': errorMessage},
        );
      }
    }
    _log(
      WebGatewayLogLevel.success,
      'SESSION',
      'Web 新建会话 ${session.id}',
      <String, Object?>{
        'template_id': templateId,
        'mode': mode.storageValue,
        'device_id': auth.deviceId,
        if (requestedModelKey.isNotEmpty) 'model_key': requestedModelKey,
      },
    );
    return _json(HttpStatus.created, <String, Object?>{
      'session': _sessionSummary(session),
      if (warnings.isNotEmpty) 'warnings': warnings,
    });
  }

  Future<shelf.Response> _getSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final includeCacheHitTrend = _truthy(
      request.requestedUri.queryParameters['hydrate_cache_statistics'],
    );
    final effectiveSession = includeCacheHitTrend
        ? await _sessionController.ensureSessionCacheStatisticsHydrated(
                session.id,
              ) ??
              session
        : session;
    return _json(HttpStatus.ok, <String, Object?>{
      'session': await _sessionSummaryWithStoredMessageCount(
        effectiveSession,
        includeDetails: true,
        includeCacheHitTrend: includeCacheHitTrend,
      ),
      'runtime': <String, Object?>{
        'send_phase': _sessionController
            .sendPhaseForSession(effectiveSession.id)
            .name,
        'can_stop': _sessionController.canStopResponding(effectiveSession.id),
        'last_error': _sessionController.lastErrorMessageForSession(
          effectiveSession.id,
        ),
      },
    });
  }

  /// 机器终端接口的公共前置：校验会话可见性、记忆会话元数据并读取请求体，
  /// 保证四个终端入口的鉴权与历史返回口径完全一致。
  /// 缓存锁定校验：会话已锁定服务商与模型时拒绝切换模型。
  ///
  /// 返回非 null 表示应把该响应直接回给调用方；未锁定或模型一致时返回 null。
  Future<shelf.Response?> _rejectIfModelSelectionLocked(
    AiSession session,
    AiModelConfig model,
  ) async {
    final lockedModelKey = _lastModelKeyForSession(session);
    if (lockedModelKey == null ||
        _modelKey(model.id, model.modelId) == lockedModelKey ||
        !await _resolveSessionInputCacheModelSelectionLocked(session)) {
      return null;
    }
    return _json(HttpStatus.conflict, <String, Object?>{
      'error': 'input_cache_model_selection_locked',
      'message': _modelSelectionLockedMessage,
      'model_key': lockedModelKey,
    });
  }

  Future<shelf.Response> _withMachineTerminalSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
    Future<shelf.Response> Function(
      AiSession session,
      Map<String, Object?> body,
      bool includeHistory,
    )
    handle,
  ) async {
    final session = _findAuthorizedMachineTerminalSession(auth, sessionId);
    if (session == null) {
      return _machineTerminalUnavailable(auth, sessionId);
    }
    _rememberMachineTerminalSessionMetadata(session);
    final body = await _readJsonBody(request);
    return handle(session, body, _includeTerminalHistory(request, body));
  }

  Future<shelf.Response> _getTerminal(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) {
    return _withMachineTerminalSession(request, auth, sessionId, (
      session,
      _,
      includeHistory,
    ) async {
      final start = request.requestedUri.queryParameters['start'] != 'false';
      final snapshot = await _machineTerminalService.ensureWorkspace(
        sessionId: session.id,
        workingDirectory: _machineTerminalWorkingDirectory(session),
        start: start,
      );
      return _json(HttpStatus.ok, <String, Object?>{
        'terminal': snapshot.toJson(includeHistory: includeHistory),
      });
    });
  }

  Future<shelf.Response> _writeTerminal(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) {
    return _withMachineTerminalSession(request, auth, sessionId, (
      session,
      body,
      includeHistory,
    ) async {
      final data = _string(body['data'] ?? body['text'] ?? body['input'], '');
      if (data.isEmpty) {
        return _errorJson(HttpStatus.badRequest, 'terminal_input_required');
      }
      await _machineTerminalService.writeInput(
        sessionId: session.id,
        terminalId: _string(body['terminal_id'], '').trim(),
        data: data,
        appendNewline:
            boolFromValue(body['append_newline']) ||
            boolFromValue(body['enter']),
      );
      final snapshot = _machineTerminalService.snapshot(session.id);
      return _json(HttpStatus.ok, <String, Object?>{
        'ok': true,
        'terminal': snapshot?.toJson(includeHistory: includeHistory),
      });
    });
  }

  Future<shelf.Response> _executeTerminal(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) {
    return _withMachineTerminalSession(request, auth, sessionId, (
      session,
      body,
      includeHistory,
    ) async {
      final command = _string(body['command'] ?? body['cmd'], '').trimRight();
      if (command.trim().isEmpty) {
        return _errorJson(HttpStatus.badRequest, 'terminal_command_required');
      }
      final result = await _machineTerminalService.executeCommand(
        sessionId: session.id,
        terminalId: _string(body['terminal_id'], '').trim(),
        command: command,
        timeout: Duration(milliseconds: _terminalTimeoutMs(body)),
      );
      return _json(HttpStatus.ok, <String, Object?>{
        'ok': result.succeeded,
        'result': result.toJson(),
        'terminal': _machineTerminalService
            .snapshot(session.id)
            ?.toJson(includeHistory: includeHistory),
      });
    });
  }

  Future<shelf.Response> _controlTerminal(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) {
    return _withMachineTerminalSession(request, auth, sessionId, (
      session,
      body,
      includeHistory,
    ) async {
      final action = _string(body['action'], '').trim();
      if (action.isEmpty) {
        return _errorJson(HttpStatus.badRequest, 'terminal_action_required');
      }
      try {
        final snapshot = await _machineTerminalService.control(
          sessionId: session.id,
          action: action,
          terminalId: _string(body['terminal_id'], '').trim(),
          workingDirectory: _string(
            body['working_directory'] ?? body['cwd'],
            '',
          ).trim(),
          columns: optionalIntFromValue(body['columns']),
          rows: optionalIntFromValue(body['rows']),
        );
        return _json(HttpStatus.ok, <String, Object?>{
          'ok': true,
          'terminal': snapshot.toJson(includeHistory: includeHistory),
        });
      } catch (error, stack) {
        silentLog('web_message_platform_service', '控制机器终端', error, stack);
        return _json(HttpStatus.badRequest, <String, Object?>{
          'error': 'terminal_control_failed',
          'message': messageGatewayFailureMessage(error, fallback: '机器终端操作失败。'),
        });
      }
    });
  }

  bool _includeTerminalHistory(
    shelf.Request request, [
    Map<String, Object?>? body,
  ]) {
    final query = request.requestedUri.queryParameters;
    return boolFromValue(query['history']) ||
        boolFromValue(query['include_history']) ||
        boolFromValue(body?['history']) ||
        boolFromValue(body?['include_history']);
  }

  Future<shelf.Response> _renameSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final body = await _readJsonBody(request);
    final hasTitle = body.containsKey('title');
    final hasMode = body.containsKey('mode');
    final hasFullAccess = body.containsKey('full_access_permission');
    if (!_config.sessionManagementEnabled &&
        (hasTitle || hasMode || hasFullAccess)) {
      return _errorJson(HttpStatus.forbidden, 'session_management_disabled');
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    if (!hasTitle && !hasMode && !hasFullAccess) {
      return _errorJson(HttpStatus.badRequest, 'session_patch_empty');
    }
    var ok = true;
    var updated = session;
    final changed = <String, Object?>{};

    if (hasTitle) {
      final title = collapseInlineWhitespace(_string(body['title'], ''));
      if (title.isEmpty) {
        return _errorJson(HttpStatus.badRequest, 'title_required');
      }
      if (title.characters.length >
          AiSessionController.maxManualTitleCharacters) {
        return _errorJson(HttpStatus.badRequest, 'title_too_long');
      }
      final renamed = await _sessionController.renameSession(session.id, title);
      ok = ok && renamed;
      final committed = _sessionController.sessions.firstWhere(
        (item) => item.id == session.id,
        orElse: () => updated.copyWith(title: title),
      );
      updated = renamed ? committed.copyWith(title: title) : committed;
      changed['title'] = title;
    }

    if (hasMode) {
      final rawMode = _string(body['mode'], updated.mode.storageValue).trim();
      if (rawMode != AiSessionMode.chat.storageValue &&
          rawMode != AiSessionMode.plan.storageValue &&
          rawMode != AiSessionMode.goal.storageValue) {
        return _json(HttpStatus.badRequest, <String, Object?>{
          'error': 'session_mode_invalid',
          'mode': rawMode,
        });
      }
      final mode = AiSessionMode.fromStorage(rawMode);
      if (mode == AiSessionMode.plan && !_config.planModeEnabled) {
        return _errorJson(HttpStatus.forbidden, 'plan_mode_disabled');
      }
      if (mode == AiSessionMode.goal &&
          !aiSessionGoalModeAllowedForTemplate(session.templateId)) {
        return _errorJson(HttpStatus.forbidden, 'goal_mode_not_available');
      }
      final updatedMode = await _sessionController.updateSessionMode(
        session.id,
        mode,
      );
      ok = ok && updatedMode;
      updated = _sessionController.sessions.firstWhere(
        (item) => item.id == session.id,
        orElse: () => updated.copyWith(mode: mode),
      );
      changed['mode'] = mode.storageValue;
    }

    if (hasFullAccess) {
      final enabled = boolFromValue(body['full_access_permission']);
      final updatedPermission = await _sessionController
          .updateSessionFullAccessPermission(session.id, enabled);
      ok = ok && updatedPermission;
      updated = _sessionController.sessions.firstWhere(
        (item) => item.id == session.id,
        orElse: () => updated.copyWith(fullAccessPermission: enabled),
      );
      changed['full_access_permission'] = enabled;
    }

    _log(
      WebGatewayLogLevel.info,
      'SESSION',
      'Web 更新会话 ${session.id}',
      <String, Object?>{'device_id': auth.deviceId, ...changed},
    );
    return _json(ok ? HttpStatus.ok : HttpStatus.conflict, <String, Object?>{
      'ok': ok,
      'session': await _sessionSummaryWithStoredMessages(updated),
    });
  }

  Future<shelf.Response> _deleteSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    if (!_config.sessionManagementEnabled) {
      return _errorJson(HttpStatus.forbidden, 'session_management_disabled');
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final deletedBy = auth.deviceName.trim().isEmpty
        ? auth.source.storageValue
        : auth.browserName.trim().isEmpty
        ? auth.deviceName.trim()
        : '${auth.deviceName.trim()} · ${auth.browserName.trim()}';
    final ok = await _sessionController.deleteSession(
      session.id,
      deletedByLabel: deletedBy,
      deletionSource: 'web',
    );
    if (ok) {
      _queuedGoalYieldLeasesBySessionId.remove(session.id);
    }
    _log(
      WebGatewayLogLevel.warn,
      'SESSION',
      'Web 删除会话 ${session.id}',
      <String, Object?>{'title': session.title, 'device_id': auth.deviceId},
    );
    return _json(ok ? HttpStatus.ok : HttpStatus.conflict, <String, Object?>{
      'ok': ok,
      'deleted_session_id': session.id,
    });
  }

  Future<shelf.Response> _listMessages(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final limit = _queryInt(request, 'limit', fallback: 80, min: 1, max: 200);
    final rawOffset = _queryInt(request, 'offset', fallback: 0, min: 0);
    final tail =
        _truthy(request.requestedUri.queryParameters['tail']) ||
        request.requestedUri.queryParameters['window'] == 'tail';
    final revealMessageId =
        request.requestedUri.queryParameters['reveal_message_id']?.trim() ?? '';
    final revealAnchor = revealMessageId.isEmpty || revealMessageId.length > 200
        ? null
        : await _resolveTranscriptRevealAnchor(session, revealMessageId);
    final window = revealAnchor == null
        ? await _loadStoredMessageWindow(
            session,
            limit: limit,
            offset: rawOffset,
            tail: tail,
          )
        : await _loadTranscriptRevealWindow(
            session,
            anchor: revealAnchor,
            limit: limit,
          );
    final lastMessage = window.messages.isEmpty ? null : window.messages.last;
    return _json(HttpStatus.ok, <String, Object?>{
      'session': _sessionSummary(
        session,
        messageCountOverride: window.total,
        lastMessageOverride: lastMessage,
        lastModelKeyCandidates: window.messages,
      ),
      'items': window.messages.map(_messageJson).toList(growable: false),
      'offset': window.offset,
      'limit': window.limit,
      'total': window.total,
      'has_more': window.hasMore,
      'has_older': window.hasOlder,
      'has_newer': window.hasNewer,
      'window': window.window,
      if (revealAnchor != null)
        'resolved_reveal_message_id': revealAnchor.messageId,
      'send_phase': _sessionController.sendPhaseForSession(session.id).name,
      'last_error': _sessionController.lastErrorMessageForSession(session.id),
      'pending_write_approval': _pendingWriteApprovalJson(session.id),
    });
  }

  Future<shelf.Response> _getMessage(
    shelf.Request _,
    _WebGatewayAuthSession auth,
    String sessionId,
    String messageId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    AiSessionMessage? message;
    try {
      message = await _sessionController.store.loadMessage(
        session.id,
        messageId,
      );
    } on ArgumentError {
      return _errorJson(HttpStatus.badRequest, 'invalid_message_id');
    }
    if (message == null) {
      return _errorJson(HttpStatus.notFound, 'message_not_found');
    }
    return _json(HttpStatus.ok, <String, Object?>{
      'message': _messageJson(message, includeTelemetryMetadata: true),
    });
  }

  Future<shelf.Response> _listTitleSourceMessages(
    shelf.Request _,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    try {
      final sourceMessages = await _loadTitleSourceMessages(session);
      final userMessages = sourceMessages
          .where(
            (message) =>
                !message.isDeleted &&
                message.kind == AiSessionMessageKind.user &&
                message.content.trim().isNotEmpty,
          )
          .toList(growable: false);
      return _json(HttpStatus.ok, <String, Object?>{
        'ok': true,
        'items': userMessages.map(_messageJson).toList(growable: false),
        'total': userMessages.length,
      });
    } catch (error, stackTrace) {
      silentLog('web_message_platform_service', '读取标题摘要消息源', error, stackTrace);
      final errorMessage = messageGatewayFailureMessage(
        error,
        fallback: '标题摘要消息读取失败。',
      );
      _log(
        WebGatewayLogLevel.warn,
        'SESSION',
        'Web 获取标题摘要消息源失败',
        <String, Object?>{'session_id': session.id, 'error': errorMessage},
      );
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'error': 'title_source_messages_failed',
        'message': errorMessage,
      });
    }
  }

  Future<List<AiSessionMessage>> _loadTitleSourceMessages(
    AiSession session,
  ) async {
    if (session.hasCompleteMessages) {
      return session.messages;
    }
    final stored = await _sessionController.store.loadSession(session.id);
    if (stored == null) {
      return session.messages;
    }
    return _mergeStoredAndLiveMessages(stored.messages, session.messages);
  }

  Future<AiSession> _loadExportSessionSnapshot(AiSession session) async {
    try {
      final stored = await _sessionController.store.loadSession(session.id);
      if (stored == null) {
        return session;
      }
      final messages = _mergeStoredAndLiveMessages(
        stored.messages,
        session.messages,
      );
      return stored.copyWith(
        title: session.title,
        updatedAt: session.updatedAt.isAfter(stored.updatedAt)
            ? session.updatedAt
            : stored.updatedAt,
        messages: messages,
        lastUsedModelId: session.lastUsedModelId ?? stored.lastUsedModelId,
        lastUsedModelLabel:
            session.lastUsedModelLabel ?? stored.lastUsedModelLabel,
        isTitleManuallyEdited: session.isTitleManuallyEdited,
        autoTitleAcquired:
            session.autoTitleAcquired || stored.autoTitleAcquired,
        autoTitleRetryCount: math.max(
          session.autoTitleRetryCount,
          stored.autoTitleRetryCount,
        ),
        autoTitleFirstUserContent:
            session.autoTitleFirstUserContent ??
            stored.autoTitleFirstUserContent,
        autoTitleGeneratedAt:
            session.autoTitleGeneratedAt ?? stored.autoTitleGeneratedAt,
        autoTitleSourceMessageId:
            session.autoTitleSourceMessageId ?? stored.autoTitleSourceMessageId,
        latestCompressionCheckpointMessageId:
            session.latestCompressionCheckpointMessageId ??
            stored.latestCompressionCheckpointMessageId,
        latestCompressionAt:
            session.latestCompressionAt ?? stored.latestCompressionAt,
        lastPromptMetadata: session.lastPromptMetadata.isEmpty
            ? stored.lastPromptMetadata
            : session.lastPromptMetadata,
        todoItems: session.todoItems.isEmpty
            ? stored.todoItems
            : session.todoItems,
        mode: session.mode,
        awaitingPlanApproval: session.awaitingPlanApproval,
        pendingPlan: session.pendingPlan ?? stored.pendingPlan,
        pendingPlanAllowedPrompts: session.pendingPlanAllowedPrompts.isEmpty
            ? stored.pendingPlanAllowedPrompts
            : session.pendingPlanAllowedPrompts,
        planHistory: session.planHistory.isEmpty
            ? stored.planHistory
            : session.planHistory,
        fullAccessPermission: session.fullAccessPermission,
        metadata: <String, Object?>{...stored.metadata, ...session.metadata},
        messageLoadState: AiSessionMessageLoadState.complete,
        messageWindowStartIndex: 0,
        messageTotalCount: messages.length,
      );
    } catch (error, stack) {
      silentLog('web_message_platform_service', '加载导出会话快照', error, stack);
      return session;
    }
  }

  /// 导出整会话为 JSONL 附件下载。复用 APP 端同一编码语义，确保下载后缀、
  /// MIME 与实际载荷格式一致。
  Future<shelf.Response> _exportSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final exportSession = await _loadExportSessionSnapshot(session);
    final filename = buildJsonlExportFilename(
      title: exportSession.title,
      sessionId: exportSession.id,
    );
    return shelf.Response.ok(
      _observeOutboundByteStream(
        encodeAiSessionToJsonlByteStream(session: exportSession),
      ),
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: kApplicationNdjsonUtf8ContentType,
        'content-disposition': _attachmentContentDisposition(filename),
        HttpHeaders.cacheControlHeader: kCacheControlNoStore,
      },
    );
  }

  Future<({String? reminder, Map<String, Object?>? metadata, String? error})>
  _resolveWebSelectedSkill(Object? raw) async {
    if (raw == null) {
      return (reminder: null, metadata: null, error: null);
    }
    if (raw is! Map) {
      return (reminder: null, metadata: null, error: 'skill_selection_invalid');
    }
    if (webGatewayIsDenyAllSelection(_config.allowedSkillNames)) {
      return (reminder: null, metadata: null, error: 'skill_not_allowed');
    }
    final name = _string(raw['name'], '').trim();
    final relativePath = _string(raw['relative_directory_path'], '').trim();
    if (name.isEmpty && relativePath.isEmpty) {
      return (reminder: null, metadata: null, error: 'skill_selection_empty');
    }
    final candidates = _config.allowedSkillNames.isEmpty
        ? _skillsController.skills
        : _skillsController.skills
              .where((skill) => _config.allowedSkillNames.contains(skill.name))
              .toList(growable: false);
    LocalSkill? selected;
    for (final skill in candidates) {
      if (relativePath.isNotEmpty &&
          skill.relativeDirectoryPath == relativePath) {
        selected = skill;
        break;
      }
      if (name.isNotEmpty && skill.name == name) {
        selected = skill;
        break;
      }
    }
    if (selected == null) {
      return (reminder: null, metadata: null, error: 'skill_not_found');
    }
    String? manifestContent;
    try {
      manifestContent = await _skillsController.readSkillManifest(selected);
    } catch (error, stack) {
      silentLog('web_message_platform_service', '读取所选技能清单', error, stack);
    }
    return (
      reminder: buildLocalSkillSystemReminder(
        selected,
        manifestContent: manifestContent,
      ),
      metadata: <String, Object?>{
        'name': selected.name,
        'path': selected.manifestPath,
        'resource_id': selected.relativeDirectoryPath,
        if (selected.hasEmojiIcon) 'emoji': selected.emojiIcon,
        if (selected.hasIcon) 'icon_path': selected.iconPath,
        if (selected.hasIcon && selected.iconKind != null)
          'icon_kind': switch (selected.iconKind!) {
            LocalSkillIconKind.svg => 'svg',
            LocalSkillIconKind.raster => 'raster',
          },
      },
      error: null,
    );
  }

  Future<shelf.Response> _sendMessage(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final recentMessageWindow = await _loadStoredMessageWindow(
      session,
      limit: _settingsController.aiInputCacheEnabled
          ? _maxMessageWindowLimit
          : 1,
      tail: true,
    );
    final existingMessageCount = math.max(
      recentMessageWindow.total,
      session.displayMessages.length,
    );
    if (existingMessageCount >= _config.maxMessagesPerSession) {
      return _errorJson(HttpStatus.forbidden, 'session_message_limit_reached');
    }
    final body = await _readJsonBody(
      request,
      maxBytes: kWebGatewayMessageRequestMaxBytes,
    );
    final content = _string(body['content'], '').trim();
    final estimatedTokens = (content.length / 4).ceil();
    if (estimatedTokens > _config.singleMessageTokenLimit) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'message_too_large',
        'estimated_tokens': estimatedTokens,
        'limit': _config.singleMessageTokenLimit,
      });
    }
    final rawMode = _string(body['mode'], 'normal');
    final conversationMode =
        WebGatewayConversationMode.fromStorage(rawMode) ??
        WebGatewayConversationMode.normal;
    if (!_config.allowedConversationModes.contains(conversationMode)) {
      return _errorJson(HttpStatus.forbidden, 'conversation_mode_not_allowed');
    }
    final rawAttachments = body['attachments'];
    if (rawAttachments is List &&
        rawAttachments.length > aiMessageAttachmentLimit) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'too_many_attachments',
        'limit': aiMessageAttachmentLimit,
      });
    }
    final attachments = await _materializeAttachments(
      session.id,
      rawAttachments,
    );
    if (attachments.isNotEmpty &&
        !_config.allowedMessageTypes.contains(
          WebGatewayMessageType.attachment,
        )) {
      await _deleteMaterializedAttachments(attachments);
      return _errorJson(HttpStatus.forbidden, 'attachments_not_allowed');
    }
    if (content.isNotEmpty &&
        !_config.allowedMessageTypes.contains(WebGatewayMessageType.text)) {
      await _deleteMaterializedAttachments(attachments);
      return _errorJson(HttpStatus.forbidden, 'text_not_allowed');
    }
    final requestedModelKey = _string(body['model_key'], '').trim();
    final model = _resolveModel(requestedModelKey);
    if (model == null) {
      await _deleteMaterializedAttachments(attachments);
      return _errorJson(HttpStatus.badRequest, 'model_not_configured');
    }
    if (_isSessionInputCacheModelSelectionLocked(
      session,
      candidateMessages: recentMessageWindow.messages,
    )) {
      final lockedModelKey = _lastModelKeyForSession(
        session,
        candidateMessages: recentMessageWindow.messages,
      );
      if (lockedModelKey != null &&
          lockedModelKey != _modelKey(model.id, model.modelId)) {
        await _deleteMaterializedAttachments(attachments);
        return _json(HttpStatus.conflict, <String, Object?>{
          'error': 'input_cache_model_selection_locked',
          'message': _modelSelectionLockedMessage,
          'model_key': lockedModelKey,
        });
      }
    }
    final attachmentCapabilities = resolveAiAttachmentInputCapabilities(model);
    final unsupportedAttachmentCount = attachments
        .where((path) => !attachmentCapabilities.supportsPath(path))
        .length;
    if (unsupportedAttachmentCount > 0) {
      await _deleteMaterializedAttachments(attachments);
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'attachment_type_not_supported',
        'unsupported_count': unsupportedAttachmentCount,
        'message': '当前模型不支持所选附件类型，请移除附件或切换模型。',
      });
    }
    final selectedSkill = await _resolveWebSelectedSkill(
      body['selected_skill'],
    );
    if (selectedSkill.error != null) {
      await _deleteMaterializedAttachments(attachments);
      return _errorJson(HttpStatus.badRequest, selectedSkill.error!);
    }
    // 本轮临时跳过的用户指令（与 App 端 _ComposerInstructionsStrip 一致），
    // 仅作用于本次 send，不持久化。
    final skippedInstructionIds = <String>{};
    final skippedRaw = body['skipped_instruction_ids'];
    if (skippedRaw is List) {
      for (final item in skippedRaw) {
        final id = '$item'.trim();
        if (id.isNotEmpty) skippedInstructionIds.add(id);
      }
    }
    final creationRequest = _creationRequestFor(
      conversationMode,
      body['creation_options'] is Map
          ? stringKeyedMapFromValue(body['creation_options'])
          : null,
    );
    if (!_modelSupportsConversationMode(model, conversationMode)) {
      await _deleteMaterializedAttachments(attachments);
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'model_mode_not_supported',
        'mode': conversationMode.storageValue,
        'model_id': model.modelId,
        'message':
            '当前模型 ${model.modelId} 不支持 ${conversationMode.storageValue} 模式，请切换到具备对应生成能力的模型。',
      });
    }
    final responseModalities = switch (conversationMode) {
      WebGatewayConversationMode.image => const <String>['image'],
      WebGatewayConversationMode.video => const <String>['video'],
      WebGatewayConversationMode.audio => const <String>['audio'],
      _ => const <String>[],
    };
    final goalOptionsRaw = body['goal_options'] ?? body['goalOptions'];
    final goalStartOptions = goalOptionsRaw == null
        ? null
        : AiSessionGoalStartOptions.fromJson(goalOptionsRaw);
    if (goalOptionsRaw != null && goalStartOptions == null) {
      await _deleteMaterializedAttachments(attachments);
      return _errorJson(HttpStatus.badRequest, 'goal_options_invalid');
    }
    if (goalStartOptions != null &&
        !aiSessionGoalModeAllowedForTemplate(session.templateId)) {
      await _deleteMaterializedAttachments(attachments);
      return _errorJson(HttpStatus.forbidden, 'goal_mode_not_available');
    }
    final allowQueuedGoalInterruption =
        boolFromValue(body['allow_queued_goal_interruption']) ||
        boolFromValue(body['allowQueuedGoalInterruption']);
    if (session.hasActiveGoal && !allowQueuedGoalInterruption) {
      await _deleteMaterializedAttachments(attachments);
      return _json(HttpStatus.conflict, <String, Object?>{
        'error': 'goal_active',
        'goal_state': session.goalState.toJson(),
      });
    }
    if (session.mode == AiSessionMode.goal &&
        goalStartOptions == null &&
        !allowQueuedGoalInterruption) {
      await _deleteMaterializedAttachments(attachments);
      return _errorJson(HttpStatus.badRequest, 'goal_options_required');
    }
    // 单一发送通道 + 互斥：同一会话若已在 sending/responding/streaming/finalizing
    // 等任一非 idle 阶段，立刻拒绝新的 web 端发送，避免并发触发同一控制器。
    // 这与 AiSessionController._enqueueSessionOperation 内部排队一起构成两层防护：
    // 第一层让前端立即得到 409 反馈以禁用按钮，第二层兜底防止异常路径并发。
    final currentPhase = _sessionController.sendPhaseForSession(session.id);
    if (currentPhase != AiSendPhase.idle) {
      await _deleteMaterializedAttachments(attachments);
      return _json(HttpStatus.conflict, <String, Object?>{
        'error': 'session_busy',
        'send_phase': currentPhase.name,
      });
    }
    final userMessageMetadata =
        _metadataForRequest(auth, request, <String, Object?>{
          'sent_via': 'web_api',
          'conversation_mode': conversationMode.storageValue,
          'model_key': _modelKey(model.id, model.modelId),
          'attachment_count': attachments.length,
        });
    final runtimeContext = await _buildRuntimeContext(
      templateId: session.templateId,
      skippedInstructionIds: skippedInstructionIds,
    );
    final phaseBeforeSend = _sessionController.sendPhaseForSession(session.id);
    if (phaseBeforeSend != AiSendPhase.idle) {
      await _deleteMaterializedAttachments(attachments);
      return _json(HttpStatus.conflict, <String, Object?>{
        'error': 'session_busy',
        'send_phase': phaseBeforeSend.name,
      });
    }
    // 关键：不能 await 整轮助手对话完成。原实现 `await sendMessage(...)` 会
    // 卡住 HTTP 响应直到 30s 后整轮回复结束，导致 web 端长时间「发送中」+
    // 一次性 dump 所有消息（无法看到流式）。改为 fire-and-forget：
    //   1. 立即返回 202，让前端解锁 UI；
    //   2. SSE 通道 (/api/sessions/:id/events) 推送 user 消息落库 + 后续
    //      流式增量；
    //   3. 错误经 _sessionController.lastErrorMessageForSession 暴露并通过
    //      SSE phase/last_error 字段同步。
    unawaited(
      _sessionController
          .sendMessage(
            sessionId: session.id,
            content: content,
            model: model,
            runtimeContext: runtimeContext,
            attachmentFilePaths: attachments,
            responseModalities: responseModalities,
            creationRequest: creationRequest,
            denyCommandRules: _settingsController.aiDenyCommandRules,
            requireWriteCommandConfirmation:
                AiPromptTemplatePolicies.requiresWriteCommandConfirmation(
                  templateId: session.templateId,
                  fullAccessPermission: session.fullAccessPermission,
                  globalConfirmationEnabled:
                      _settingsController.aiWriteCommandConfirmationEnabled,
                ),
            confirmWriteCommand: (request) =>
                _confirmWebWriteCommand(session.id, request),
            additionalSystemReminders: selectedSkill.reminder == null
                ? const <String>[]
                : <String>[selectedSkill.reminder!],
            selectedSkillMetadata: selectedSkill.metadata,
            goalStartOptions: goalStartOptions,
            allowQueuedGoalInterruption: allowQueuedGoalInterruption,
            userMessageMetadata: userMessageMetadata,
            revealUserMessageBeforePreflight: true,
          )
          .catchError((Object error, StackTrace stack) {
            silentLog('web_message_platform_service', '异步发送消息', error, stack);
            return false;
          }),
    );
    _log(
      WebGatewayLogLevel.success,
      'MESSAGE',
      'Web 消息已送入会话 ${session.id}',
      <String, Object?>{
        'chars': content.length,
        'attachments': attachments.length,
        'mode': conversationMode.storageValue,
      },
    );
    return _json(HttpStatus.accepted, <String, Object?>{
      'ok': true,
      'send_phase': AiSendPhase.sendingMessage.name,
    });
  }

  Future<shelf.Response> _updateMessageFeedback(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
    String messageId,
  ) async {
    if (!_config.feedbackEnabled) {
      return _errorJson(HttpStatus.forbidden, 'message_feedback_disabled');
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final body = await _readJsonBody(request, maxBytes: 4096);
    if (!body.containsKey('feedback')) {
      return _errorJson(HttpStatus.badRequest, 'feedback_required');
    }
    final rawFeedback = body['feedback'];
    final feedback = AiSessionMessageFeedback.fromStorage(rawFeedback);
    if (rawFeedback != null &&
        '$rawFeedback'.trim().isNotEmpty &&
        feedback == null) {
      return _errorJson(HttpStatus.badRequest, 'invalid_feedback');
    }
    final message = await _loadMessageForWebOperation(session, messageId);
    if (message == null) {
      return _errorJson(HttpStatus.notFound, 'message_not_found');
    }
    if (!_messageSupportsWebFeedback(message)) {
      return _errorJson(
        HttpStatus.badRequest,
        'message_feedback_not_supported',
      );
    }
    final ok = await _sessionController.updateMessageFeedback(
      sessionId: session.id,
      messageId: message.id,
      feedback: feedback,
    );
    if (!ok) {
      return _json(HttpStatus.conflict, <String, Object?>{
        'ok': false,
        'error': 'message_feedback_save_failed',
      });
    }
    final updatedSession = _findAuthorizedSession(auth, sessionId) ?? session;
    final updatedMessage =
        await _loadMessageForWebOperation(updatedSession, message.id) ??
        message;
    _log(
      WebGatewayLogLevel.info,
      'MESSAGE',
      'Web 更新消息反馈 ${session.id}/${message.id}',
      <String, Object?>{
        'feedback': feedback?.storageValue,
        'device_id': auth.deviceId,
      },
    );
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'feedback': feedback?.storageValue,
      'message': _messageJson(updatedMessage),
    });
  }

  Future<shelf.Response> _translateMessage(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
    String messageId,
  ) async {
    if (!_config.translationEnabled) {
      return _errorJson(HttpStatus.forbidden, 'message_translation_disabled');
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final message = await _loadMessageForWebOperation(session, messageId);
    if (message == null) {
      return _errorJson(HttpStatus.notFound, 'message_not_found');
    }
    if (!_messageSupportsWebTextAction(message)) {
      return _errorJson(
        HttpStatus.badRequest,
        'message_translation_not_supported',
      );
    }
    final settings = _settingsController.aiTranslationSettings;
    if (!settings.enabled) {
      return _errorJson(HttpStatus.forbidden, 'translation_settings_disabled');
    }
    final text = _webTranslationMessageText(message, settings);
    if (text == null) {
      return _errorJson(
        HttpStatus.badRequest,
        'message_translation_not_supported',
      );
    }
    try {
      final fallbackModel =
          _resolveModel(_lastModelKeyForSession(session) ?? '') ??
          _settingsController.selectedAiModel;
      final result = await _translationService.translate(
        text: text,
        settings: settings,
        availableModels: _settingsController.aiModels,
        fallbackModel: fallbackModel,
      );
      _log(
        WebGatewayLogLevel.info,
        'MESSAGE',
        'Web 翻译消息 ${session.id}/${message.id}',
        <String, Object?>{
          'provider': result.provider.storageKey,
          'device_id': auth.deviceId,
        },
      );
      return _json(HttpStatus.ok, <String, Object?>{
        'ok': true,
        'text': result.text,
        'provider': result.provider.storageKey,
        'model_config_id': result.modelConfigId,
        'model_id': result.modelId,
        'settings_fingerprint': settings.cacheFingerprint,
      });
    } on AiTranslationException catch (error) {
      return _json(HttpStatus.badGateway, <String, Object?>{
        'ok': false,
        'error': 'message_translation_failed',
        'message': error.message,
        'provider': error.provider?.storageKey,
      });
    } catch (error, stack) {
      silentLog('web_message_platform_service', '翻译消息', error, stack);
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'ok': false,
        'error': 'message_translation_failed',
        'message': messageGatewayFailureMessage(error, fallback: '消息翻译失败。'),
      });
    }
  }

  Future<shelf.Response> _getTtsPlaybackState(
    shelf.Request request,
    _WebGatewayAuthSession auth,
  ) async {
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'playback': _ttsPlaybackPayload(),
    });
  }

  Future<shelf.Response> _stopTtsPlayback(
    shelf.Request request,
    _WebGatewayAuthSession auth,
  ) async {
    await _ttsPlaybackService.stop();
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'playback': _ttsPlaybackPayload(),
    });
  }

  Future<shelf.Response> _toggleMessageTts(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
    String messageId,
  ) async {
    final runtimeGeneration = _runtimeGeneration;
    if (!_isRuntimeRequestCurrent(runtimeGeneration)) {
      return _runtimeUnavailableResponse();
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final message = await _loadMessageForWebOperation(session, messageId);
    if (!_isRuntimeRequestCurrent(runtimeGeneration)) {
      return _runtimeUnavailableResponse();
    }
    if (message == null) {
      return _errorJson(HttpStatus.notFound, 'message_not_found');
    }
    if (_ttsPlaybackService.isPlayingMessage(message.id)) {
      await _ttsPlaybackService.stop();
      if (!_isRuntimeRequestCurrent(runtimeGeneration)) {
        return _runtimeUnavailableResponse();
      }
      return _json(HttpStatus.ok, <String, Object?>{
        'ok': true,
        'playback': _ttsPlaybackPayload(),
      });
    }
    if (!_config.readAloudEnabled) {
      return _errorJson(HttpStatus.forbidden, 'message_tts_disabled');
    }
    if (!_messageSupportsWebTextAction(message)) {
      return _errorJson(HttpStatus.badRequest, 'message_tts_not_supported');
    }
    final settings = _settingsController.aiTtsSettings;
    if (!settings.enabled) {
      return _errorJson(HttpStatus.forbidden, 'tts_settings_disabled');
    }
    final text = _webTtsMessageText(message);
    if (text == null) {
      return _errorJson(HttpStatus.badRequest, 'message_tts_not_supported');
    }
    final fallbackModel =
        _resolveModel(_lastModelKeyForSession(session) ?? '') ??
        _settingsController.selectedAiModel;
    unawaited(() async {
      if (!_isRuntimeRequestCurrent(runtimeGeneration)) return;
      try {
        await _ttsPlaybackService.speak(
          messageId: message.id,
          text: text,
          settings: settings,
          availableModels: _settingsController.aiModels,
          fallbackModel: fallbackModel,
        );
      } catch (error, stack) {
        silentLog('web_message_platform_service', '切换消息朗读', error, stack);
      }
    }());
    await Future<void>.delayed(kOpenHandFramePeriodicTimerInterval);
    if (!_isRuntimeRequestCurrent(runtimeGeneration)) {
      return _runtimeUnavailableResponse();
    }
    _log(
      WebGatewayLogLevel.info,
      'MESSAGE',
      'Web 朗读消息 ${session.id}/${message.id}',
      <String, Object?>{'device_id': auth.deviceId},
    );
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'playback': _ttsPlaybackPayload(),
    });
  }

  bool _isRuntimeRequestCurrent(int generation) {
    return !_disposed && generation == _runtimeGeneration && isRunning;
  }

  shelf.Response _runtimeUnavailableResponse() {
    return _json(HttpStatus.serviceUnavailable, const <String, Object?>{
      'error': 'service_stopping',
    });
  }

  Future<shelf.Response> _regenerateMessage(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
    String messageId,
  ) async {
    if (!_config.regenerationEnabled) {
      return _errorJson(HttpStatus.forbidden, 'message_regeneration_disabled');
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final message = await _loadMessageForWebOperation(session, messageId);
    if (message == null) {
      return _errorJson(HttpStatus.notFound, 'message_not_found');
    }
    if (!_messageSupportsWebRegeneration(message)) {
      return _errorJson(
        HttpStatus.badRequest,
        'message_regeneration_not_supported',
      );
    }
    final currentPhase = _sessionController.sendPhaseForSession(session.id);
    if (currentPhase != AiSendPhase.idle) {
      return _json(HttpStatus.conflict, <String, Object?>{
        'error': 'session_busy',
        'send_phase': currentPhase.name,
      });
    }
    final body = await _readJsonBody(request, maxBytes: 4096);
    final requestedModelKey = _string(body['model_key'], '').trim();
    final requestedModel = requestedModelKey.isEmpty
        ? null
        : _resolveModel(requestedModelKey);
    if (requestedModelKey.isNotEmpty && requestedModel == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'model_not_configured',
        'model_key': requestedModelKey,
      });
    }
    final model =
        requestedModel ??
        _resolveModel(_lastModelKeyForSession(session) ?? '') ??
        _resolveModel('');
    if (model == null) {
      return _errorJson(HttpStatus.badRequest, 'model_not_configured');
    }
    final modelLockRejection = await _rejectIfModelSelectionLocked(
      session,
      model,
    );
    if (modelLockRejection != null) return modelLockRejection;
    final runtimeContext = await _buildRuntimeContext(
      templateId: session.templateId,
    );
    final phaseBeforeRegeneration = _sessionController.sendPhaseForSession(
      session.id,
    );
    if (phaseBeforeRegeneration != AiSendPhase.idle) {
      return _json(HttpStatus.conflict, <String, Object?>{
        'error': 'session_busy',
        'send_phase': phaseBeforeRegeneration.name,
      });
    }
    unawaited(
      _sessionController
          .regenerateAssistantMessageVariant(
            sessionId: session.id,
            messageId: message.id,
            model: model,
            runtimeContext: runtimeContext,
            denyCommandRules: _settingsController.aiDenyCommandRules,
            requireWriteCommandConfirmation:
                AiPromptTemplatePolicies.requiresWriteCommandConfirmation(
                  templateId: session.templateId,
                  fullAccessPermission: session.fullAccessPermission,
                  globalConfirmationEnabled:
                      _settingsController.aiWriteCommandConfirmationEnabled,
                ),
            confirmWriteCommand: (request) =>
                _confirmWebWriteCommand(session.id, request),
          )
          .catchError((Object error, StackTrace stack) {
            silentLog('web_message_platform_service', '异步重新生成消息', error, stack);
            return false;
          }),
    );
    _log(
      WebGatewayLogLevel.info,
      'MESSAGE',
      'Web 重新生成消息 ${session.id}/${message.id}',
      <String, Object?>{
        'model_key': _modelKey(model.id, model.modelId),
        'device_id': auth.deviceId,
      },
    );
    return _json(HttpStatus.accepted, <String, Object?>{
      'ok': true,
      'send_phase': AiSendPhase.sendingMessage.name,
    });
  }

  /// 主动中断当前会话的助手回复（对应桌面端「停止响应」按钮）。
  ///
  /// 返回值：
  /// - 200 {ok:true, send_phase:'idle'} 中断成功，下一轮 listMessages 会拿到 finalize 后的内容；
  /// - 200 {ok:false, send_phase:<当前>} 当前会话无可中断的回复（idle 等）；
  /// - 404 会话不存在或当前 token 无权访问。
  Future<shelf.Response> _stopSendMessage(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    if (!_sessionController.canStopResponding(session.id)) {
      return _json(HttpStatus.ok, <String, Object?>{
        'ok': false,
        'send_phase': _sessionController.sendPhaseForSession(session.id).name,
        'reason': 'not_running',
      });
    }
    _resolvePendingWriteApprovals(
      sessionId: session.id,
      decision: BashCommandApprovalDecision.cancelled,
      source: 'session_stop',
    );
    await _sessionController.stopResponding(session.id);
    _log(
      WebGatewayLogLevel.warn,
      'MESSAGE',
      'Web 主动中断会话 ${session.id} 的助手回复',
      <String, Object?>{'device_id': auth.deviceId},
    );
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'send_phase': _sessionController.sendPhaseForSession(session.id).name,
    });
  }

  Future<shelf.Response> _pauseGoal(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final ok = await _sessionController.pauseGoal(session.id);
    final latest = _findAuthorizedSession(auth, session.id) ?? session;
    return _json(
      ok ? HttpStatus.ok : HttpStatus.internalServerError,
      <String, Object?>{
        'ok': ok,
        'session': await _sessionSummaryWithStoredMessages(latest),
      },
    );
  }

  Future<shelf.Response> _terminateGoal(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final ok = await _sessionController.terminateGoal(session.id);
    final latest = _findAuthorizedSession(auth, session.id) ?? session;
    return _json(
      ok ? HttpStatus.ok : HttpStatus.internalServerError,
      <String, Object?>{
        'ok': ok,
        'session': await _sessionSummaryWithStoredMessages(latest),
      },
    );
  }

  Future<shelf.Response> _syncQueuedGoalYield(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final body = await _readJsonBody(request);
    final rawHasPending =
        body['has_pending'] ?? body['hasPending'] ?? body['pending'];
    final hasPendingQueue = boolFromValue(rawHasPending);
    _setQueuedGoalInterruption(
      auth: auth,
      sessionId: session.id,
      hasPendingQueue: hasPendingQueue,
    );
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'has_pending': _hasQueuedGoalInterruption(session.id),
    });
  }

  Future<shelf.Response> _resumeGoal(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final body = await _readJsonBody(request);
    final requestedModelKey = _string(body['model_key'], '').trim();
    final model = requestedModelKey.isNotEmpty
        ? _resolveModel(requestedModelKey)
        : _resolveModel(_lastModelKeyForSession(session) ?? '') ??
              _resolveModel('');
    if (model == null) {
      return _errorJson(HttpStatus.badRequest, 'model_not_configured');
    }
    final modelLockRejection = await _rejectIfModelSelectionLocked(
      session,
      model,
    );
    if (modelLockRejection != null) return modelLockRejection;
    final currentPhase = _sessionController.sendPhaseForSession(session.id);
    if (currentPhase != AiSendPhase.idle) {
      return _json(HttpStatus.conflict, <String, Object?>{
        'error': 'session_busy',
        'send_phase': currentPhase.name,
      });
    }
    final runtimeContext = await _buildRuntimeContext(
      templateId: session.templateId,
    );
    final phaseBeforeResume = _sessionController.sendPhaseForSession(
      session.id,
    );
    if (phaseBeforeResume != AiSendPhase.idle) {
      return _json(HttpStatus.conflict, <String, Object?>{
        'error': 'session_busy',
        'send_phase': phaseBeforeResume.name,
      });
    }
    unawaited(
      _sessionController
          .resumeGoal(
            sessionId: session.id,
            model: model,
            runtimeContext: runtimeContext,
            denyCommandRules: _settingsController.aiDenyCommandRules,
            requireWriteCommandConfirmation:
                AiPromptTemplatePolicies.requiresWriteCommandConfirmation(
                  templateId: session.templateId,
                  fullAccessPermission: session.fullAccessPermission,
                  globalConfirmationEnabled:
                      _settingsController.aiWriteCommandConfirmationEnabled,
                ),
            confirmWriteCommand: (request) =>
                _confirmWebWriteCommand(session.id, request),
          )
          .catchError((Object error, StackTrace stack) {
            silentLog('web_message_platform_service', '异步恢复目标', error, stack);
            return false;
          }),
    );
    return _json(HttpStatus.accepted, <String, Object?>{
      'ok': true,
      'send_phase': AiSendPhase.sendingMessage.name,
    });
  }

  /// 手动触发标题生成：接收用户选择的消息内容，调用 AI 生成摘要标题。
  Future<shelf.Response> _generateTitle(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final body = await _readJsonBody(request);
    if (body.isEmpty) {
      return _errorJson(HttpStatus.badRequest, 'invalid_body');
    }
    final content = _string(body['content'], '').trim();
    if (content.isEmpty) {
      return _errorJson(HttpStatus.badRequest, 'content_required');
    }
    final requestedModelKey = _string(body['model_key'], '').trim();
    final requestedModel = requestedModelKey.isEmpty
        ? null
        : _resolveModel(requestedModelKey);
    if (requestedModelKey.isNotEmpty && requestedModel == null) {
      return _errorJson(HttpStatus.badRequest, 'model_not_configured');
    }
    final model =
        requestedModel ?? _resolveTitleGenerationModelForSession(session);
    try {
      final title = await _sessionController.generateTitleManually(
        sessionId: sessionId,
        content: content,
        model: model,
        maxTitleCharacters: _settingsController.aiGeneratedTitleMaxCharacters,
      );
      if (title == null || title.isEmpty) {
        return _json(HttpStatus.ok, <String, Object?>{'title': session.title});
      }
      return _json(HttpStatus.ok, <String, Object?>{'title': title});
    } catch (error, stack) {
      silentLog('web_message_platform_service', '生成会话标题', error, stack);
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'error': 'title_generation_failed',
        'detail': messageGatewayFailureMessage(error, fallback: '会话标题生成失败。'),
      });
    }
  }

  /// 用户主动触发的历史压缩入口（POST `/api/sessions/{id}/compact`）。
  ///
  /// Body 可选 `{model_key?: string}`：未传时回退 `_resolveModel('')`，
  /// 与桌面端「使用当前选中模型」保持一致。返回结构：
  /// ```
  /// 200 OK
  /// {
  ///   "ok": true | false,
  ///   "status": "success" | "cooldown" | "not_needed" | "inflight" |
  ///             "session_busy" | "circuit_breaker" | "failed" | "no_session",
  ///   "rejection_reason": string?,
  ///   "retry_after_ms": int?,
  ///   "session": { ... 同 _getSession 的 session 字段 }?
  /// }
  /// ```
  Future<shelf.Response> _compactSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    Map<String, Object?> body = const <String, Object?>{};
    try {
      body = await _readJsonBody(request);
    } catch (error, stack) {
      silentLog('web_message_platform_service', '读取压缩请求体', error, stack);
    }
    final model = _resolveModel(_string(body['model_key'], ''));
    if (model == null) {
      return _errorJson(HttpStatus.badRequest, 'model_not_configured');
    }
    final result = await _sessionController.requestManualCompaction(
      sessionId: session.id,
      model: model,
      runtimeContext: await _buildRuntimeContext(
        templateId: session.templateId,
      ),
    );
    final updated = _findAuthorizedSession(auth, sessionId) ?? session;
    final statusName = switch (result.status) {
      AiManualCompactionStatus.success => 'success',
      AiManualCompactionStatus.notNeeded => 'not_needed',
      AiManualCompactionStatus.cooldown => 'cooldown',
      AiManualCompactionStatus.inflight => 'inflight',
      AiManualCompactionStatus.circuitBreaker => 'circuit_breaker',
      AiManualCompactionStatus.sessionBusy => 'session_busy',
      AiManualCompactionStatus.failed => 'failed',
      AiManualCompactionStatus.noSession => 'no_session',
    };
    _log(
      result.ok ? WebGatewayLogLevel.info : WebGatewayLogLevel.debug,
      'MESSAGE',
      'Web 主动压缩会话 ${session.id}: $statusName',
      <String, Object?>{
        'device_id': auth.deviceId,
        'rejection_reason': result.message,
        if (result.retryAfter != null)
          'retry_after_ms': result.retryAfter!.inMilliseconds,
      },
    );
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': result.ok,
      'status': statusName,
      'rejection_reason': result.message,
      if (result.retryAfter != null)
        'retry_after_ms': result.retryAfter!.inMilliseconds,
      'session': await _sessionSummaryWithStoredMessages(
        updated,
        includeDetails: true,
      ),
    });
  }

  Future<shelf.Response> _respondWriteApproval(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
    String approvalId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final approval = _pendingWriteApprovals[approvalId];
    if (approval == null || approval.sessionId != session.id) {
      return _errorJson(HttpStatus.notFound, 'write_approval_not_found');
    }
    final body = await _readJsonBody(request);
    // 兼容历史 web 客户端：仅传 approved=true/false → 转为 approved/rejected。
    // 新客户端可显式传 decision: approved | rejected | dismissed。
    final rawDecision = body['decision'];
    final BashCommandApprovalDecision decision;
    if (rawDecision is String) {
      decision = enumByNameOr(
        BashCommandApprovalDecision.values,
        rawDecision,
        fallback: body['approved'] == true
            ? BashCommandApprovalDecision.approved
            : BashCommandApprovalDecision.rejected,
      );
    } else {
      decision = body['approved'] == true
          ? BashCommandApprovalDecision.approved
          : BashCommandApprovalDecision.rejected;
    }
    if (!_completePendingWriteApproval(
      approval,
      decision: decision,
      source: 'web',
      deviceId: auth.deviceId,
    )) {
      return _errorJson(HttpStatus.notFound, 'write_approval_not_found');
    }
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'decision': decision.name,
      'approved': decision == BashCommandApprovalDecision.approved,
    });
  }

  /// 设置或更新会话级节流覆盖。
  ///
  /// Body 形如 `{chars_per_second?: int, cards_per_second?: int}`，字段
  /// 缺失或 null = 清除该字段；两字段都缺失则等价于 DELETE。
  Future<shelf.Response> _setSessionThrottle(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final body = await _readJsonBody(request);
    final hasChars = body.containsKey('chars_per_second');
    final hasCards = body.containsKey('cards_per_second');
    final hasEnabled = body.containsKey('enabled');
    if (hasChars) {
      _sessionController.setSessionStreamCharsOverride(
        session.id,
        _nullableThrottleRate(body['chars_per_second']),
      );
    }
    if (hasCards) {
      _sessionController.setSessionStreamCardsOverride(
        session.id,
        _nullableThrottleRate(body['cards_per_second']),
      );
    }
    if (hasEnabled) {
      // 会话级启用开关：null 清除覆盖；true/false 立即生效。
      final raw = body['enabled'];
      _sessionController.setSessionStreamEnabledOverride(
        session.id,
        raw is bool ? raw : null,
      );
    }
    final override = _sessionController.sessionStreamThrottleOverride(
      session.id,
    );
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'chars_per_second': override?.charsPerSecond,
      'cards_per_second': override?.cardsPerSecond,
      'enabled': override?.enabled,
    });
  }

  int? _nullableThrottleRate(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return optionalRoundedIntFromValue(raw);
    if (raw is String) return optionalIntFromValue(raw);
    return null;
  }

  /// 清除会话级节流覆盖，恢复到全局设置。
  Future<shelf.Response> _clearSessionThrottle(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    _sessionController.clearSessionStreamThrottleOverride(session.id);
    return _json(HttpStatus.ok, <String, Object?>{'ok': true});
  }

  /// 删除单条消息（对齐 APP 端长按消息 → 删除）。返回最新一页消息便于前端立即刷新。
  Future<shelf.Response> _deleteMessage(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
    String messageId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final ok = await _sessionController.deleteMessages(<String>[
      messageId,
    ], sessionId: session.id);
    _log(
      WebGatewayLogLevel.info,
      'MESSAGE',
      ok
          ? 'Web 删除会话 ${session.id} 消息 $messageId'
          : 'Web 删除会话 ${session.id} 消息 $messageId 未命中',
      <String, Object?>{'device_id': auth.deviceId},
    );
    return _json(HttpStatus.ok, <String, Object?>{'ok': ok});
  }

  /// 从指定消息派生出新的会话（对齐 Codex 的 Fork/派生语义）。
  Future<shelf.Response> _forkSessionFromMessage(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
    String messageId,
  ) async {
    if (!_config.sessionManagementEnabled) {
      return _errorJson(HttpStatus.forbidden, 'session_management_disabled');
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final metadata = _metadataForRequest(auth, request, <String, Object?>{
      'created_via': 'web_api',
      'derived_via': 'web_api',
      'source_session_id': session.id,
      'source_message_id': messageId,
    });
    final forked = await _sessionController.forkSessionFromMessage(
      messageId,
      sessionId: session.id,
      extraMetadata: metadata,
    );
    if (forked == null) {
      return _errorJson(
        HttpStatus.notFound,
        'message_not_found_or_fork_failed',
      );
    }
    _log(
      WebGatewayLogLevel.success,
      'SESSION',
      'Web 派生会话 ${session.id}@$messageId → ${forked.id}',
      <String, Object?>{
        'device_id': auth.deviceId,
        'source_session_id': session.id,
        'source_message_id': messageId,
        'forked_session_id': forked.id,
      },
    );
    return _json(HttpStatus.created, <String, Object?>{
      'ok': true,
      'session': await _sessionSummaryWithStoredMessages(
        forked,
        includeDetails: true,
      ),
    });
  }

  /// 删除该消息及之后所有消息（对齐 APP 端「删除此条及后续」）。
  Future<shelf.Response> _deleteMessageCascade(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
    String messageId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final ok = await _sessionController.deleteMessagesFrom(
      messageId,
      sessionId: session.id,
    );
    _log(
      WebGatewayLogLevel.info,
      'MESSAGE',
      ok
          ? 'Web 级联删除会话 ${session.id} 自 $messageId 起的消息'
          : 'Web 级联删除会话 ${session.id} 消息 $messageId 未命中',
      <String, Object?>{'device_id': auth.deviceId},
    );
    return _json(HttpStatus.ok, <String, Object?>{'ok': ok});
  }

  /// SSE 实时事件流（与 polling 互为冗余，前端优先用 SSE）。
  ///
  /// 协议：
  ///   - text/event-stream（无 Content-Length，连接保持）；
  ///   - 每次 _sessionController.notifyListeners 触发后节流 80ms 推送一次
  ///     full snapshot：`event: snapshot\ndata: {...}\n\n`；
  ///   - 每 25s 发送 `:keepalive\n\n` 兜底防止反向代理掐断；
  ///   - 客户端断开（onCancel）即解订阅，控制器保持单一 listener 注册纪律。
  ///
  /// 鉴权：浏览器 EventSource 不允许自定义 header；这里复用 _authorize 但
  /// 退化到 query 参数（token / device_id / source）。
  Future<shelf.Response> _sessionEventsHandler(
    shelf.Request request,
    String sessionId,
  ) async {
    final auth = _authorizeFromRequestOrQuery(request);
    if (auth == null) {
      return _errorJson(HttpStatus.unauthorized, 'unauthorized');
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final clientKey = _config.authEnabled
        ? auth.token
        : _requestRemoteAddress(request);
    if (_activeSseSubscriptions >= _maxActiveSseSubscriptions ||
        (_activeSseSubscriptionsByClient[clientKey] ?? 0) >=
            _maxSseSubscriptionsPerClient ||
        (_activeSseSubscriptionsBySession[session.id] ?? 0) >=
            _maxSseSubscriptionsPerSession) {
      return _json(
        HttpStatus.tooManyRequests,
        const <String, Object?>{'error': 'sse_subscription_limit_reached'},
        headers: const <String, String>{'retry-after': '5'},
      );
    }

    String? lastSnapshotHash;
    final snapshotStopwatch = Stopwatch()..start();
    int? lastSnapshotStartedAtMs;
    Timer? throttleTimer;
    Timer? keepaliveTimer;
    var disposed = false;
    var snapshotInFlight = false;
    var snapshotQueued = false;
    var paused = false;

    Future<Map<String, Object?>> buildSnapshot(AiSession live) async {
      final _WebSessionMessageWindow messageWindow;
      final liveMessageCount = live.messages.length;
      final liveKnownTotal = math.max(
        live.messageTotalCount,
        live.statistics.totalMessageCount,
      );
      final liveLooksComplete =
          liveMessageCount > 0 && liveMessageCount >= liveKnownTotal;
      if (liveLooksComplete &&
          liveMessageCount <= _inMemoryMessageWindowDirectLimit) {
        messageWindow = _messageWindowFromDisplayMessages(
          live.displayMessages,
          limit: _sseMessageWindowSize,
          tail: true,
        );
      } else {
        messageWindow = await _loadStoredMessageWindow(
          live,
          limit: _sseMessageWindowSize,
          tail: true,
        );
      }
      final lastMessage = messageWindow.messages.isEmpty
          ? null
          : messageWindow.messages.last;
      // 把当前会话生效的字符 / 卡片节流速率推给前端，让 Web
      // 端的 TopBar 节流指示器可以无需额外接口直接展示绿/灰状态。
      final throttleOverride = _sessionController.sessionStreamThrottleOverride(
        live.id,
      );
      final effChars =
          throttleOverride?.charsPerSecond ??
          _settingsController.effectiveStreamMaxCharsPerSecond();
      final effCards =
          throttleOverride?.cardsPerSecond ??
          _settingsController.effectiveStreamMaxMessageCardsPerSecond();
      return <String, Object?>{
        'session': _sessionSummary(
          live,
          messageCountOverride: messageWindow.total,
          lastMessageOverride: lastMessage,
          lastModelKeyCandidates: messageWindow.messages,
        ),
        'messages': messageWindow.messages
            .map(_messageJson)
            .toList(growable: false),
        'message_window': <String, Object?>{
          'offset': messageWindow.offset,
          'limit': messageWindow.limit,
          'total': messageWindow.total,
          'has_older': messageWindow.hasOlder,
          'has_newer': messageWindow.hasNewer,
        },
        'send_phase': _sessionController.sendPhaseForSession(sessionId).name,
        'last_error': _sessionController.lastErrorMessageForSession(sessionId),
        'can_stop': _sessionController.canStopResponding(sessionId),
        'pending_write_approval': _pendingWriteApprovalJson(sessionId),
        'effective_stream_throttle': <String, Object?>{
          'chars_per_second': effChars,
          'cards_per_second': effCards,
          'has_session_override': throttleOverride != null,
          // 启用态：会话级 > 全局。前端据此渲染 Switch 与
          // 灰色胶囊。
          'enabled':
              throttleOverride?.enabled ??
              _settingsController.aiStreamThrottleEnabled,
          // 会话历史上是否曾节流。胶囊可见性所需。
          'was_initially_throttled': _sessionController
              .sessionWasInitiallyThrottled(live.id),
          'duration_expired': _sessionController
              .sessionStreamThrottleDurationExpired(live.id),
          // 字符吞吐 30s 桶（桶 0 = 当前秒），让 Web 端节流弹
          // 窗渲染和 App 端一致的柱状图。非流式 / 从未流式时也会回填全 0。
          'throughput_buckets': _sessionController
              .sessionStreamCharThroughputSnapshot(live.id),
        },
        'served_at': DateTime.now().toUtc().toIso8601String(),
      };
    }

    final controller = StreamController<List<int>>();

    void emit(String event, Object payload) {
      if (disposed || paused || controller.isClosed) return;
      try {
        final body = jsonEncode(payload);
        final frame = 'event: $event\ndata: $body\n\n';
        final bytes = utf8.encode(frame);
        controller.add(bytes);
        _recordStreamingOutboundBytes(bytes.length);
      } catch (error, stack) {
        silentLog('web_message_platform_service', '发送 SSE 事件', error, stack);
      }
    }

    late void Function() dispose;

    bool authStillValid() {
      if (!_config.authEnabled) return auth.token == 'anonymous';
      return identical(_authSessionForToken(auth.token), auth);
    }

    void closeUnauthorizedStream() {
      emit('unauthorized', const <String, Object?>{'error': 'unauthorized'});
      Future<void>.microtask(dispose);
    }

    late void Function() scheduleSnapshot;

    Future<void> runSnapshot() async {
      if (disposed) return;
      if (snapshotInFlight) {
        snapshotQueued = true;
        return;
      }
      snapshotInFlight = true;
      lastSnapshotStartedAtMs = snapshotStopwatch.elapsedMilliseconds;
      try {
        if (!authStillValid()) {
          closeUnauthorizedStream();
          return;
        }
        final live = _findAuthorizedSession(auth, sessionId);
        if (live == null) {
          emit('session_deleted', <String, Object?>{
            'error': _kWebGatewayErrorSessionMissing,
            'session_id': sessionId,
            'served_at': DateTime.now().toUtc().toIso8601String(),
          });
          Future<void>.microtask(dispose);
          return;
        }
        final snapshot = await buildSnapshot(live);
        if (disposed) return;
        if (!authStillValid()) {
          closeUnauthorizedStream();
          return;
        }
        final sessionPayload = snapshot['session'] as Map<String, Object?>;
        final throttlePayload =
            snapshot['effective_stream_throttle'] as Map<String, Object?>?;
        final buckets = throttlePayload?['throughput_buckets'];
        final bucketsSig = buckets is List<int>
            ? '${buckets.isNotEmpty ? buckets.first : 0}/${buckets.fold<int>(0, (a, b) => b > a ? b : a)}'
            : '0/0';
        final stats = sessionPayload['statistics'] as Map<String, Object?>?;
        final tokenStatsSig = stats == null
            ? '0:0:0:0:0:0:0'
            : '${stats['total_prompt_tokens'] ?? 0}:${stats['total_completion_tokens'] ?? 0}:${stats['cache_read_tokens'] ?? 0}:${stats['cache_creation_tokens'] ?? 0}:${stats['cache_hit_ratio'] ?? 'n'}:${stats['cache_hit_trend_points'] is List ? (stats['cache_hit_trend_points'] as List).length : 0}:${stats['cache_hit_trend_excluded_count'] ?? 0}';
        final promptMetadata =
            sessionPayload['last_prompt_metadata'] as Map<String, Object?>?;
        final contextUsageSig = promptMetadata == null
            ? '0:0:0'
            : '${promptMetadata['context_budget_estimated_prompt_tokens'] ?? 0}:${promptMetadata['context_budget_effective_window_tokens'] ?? 0}:${promptMetadata['context_budget_usage_percent'] ?? 0}';
        final goalStateSig = jsonEncode(sessionPayload['goal_state']);
        final modelSelectionLocked =
            sessionPayload['input_cache_model_selection_locked'] == true;
        final messagesPayload = snapshot['messages'] as List;
        final hash =
            '${sessionPayload['title']}|${sessionPayload['updated_at']}|${sessionPayload['message_count']}|${sessionPayload['last_model_key']}|${sessionPayload['full_access_permission']}|${snapshot['send_phase']}|${snapshot['last_error']}|${(snapshot['pending_write_approval'] as Map?)?['id'] ?? ''}|goal=$goalStateSig|model_lock=$modelSelectionLocked|throttle=${throttlePayload?['chars_per_second'] ?? 0}:${throttlePayload?['cards_per_second'] ?? 0}:${throttlePayload?['has_session_override'] ?? false}:${throttlePayload?['duration_expired'] ?? false}:$bucketsSig|tokens=$tokenStatsSig|context=$contextUsageSig|messages=${_messagePayloadWindowSignature(messagesPayload)}';
        if (hash == lastSnapshotHash) return;
        lastSnapshotHash = hash;
        emit('snapshot', snapshot);
      } catch (error, stack) {
        silentLog('web_message_platform_service', '生成 SSE 快照', error, stack);
      } finally {
        snapshotInFlight = false;
        if (!disposed && snapshotQueued) {
          snapshotQueued = false;
          scheduleSnapshot();
        }
      }
    }

    scheduleSnapshot = () {
      if (disposed) return;
      if (paused) {
        snapshotQueued = true;
        return;
      }
      // 已经排好下一次触发就直接合并进去——不要 cancel 后重排，那是防抖语义，
      // 会在高频通知（流式追加）下把下发无限推迟。
      if (throttleTimer != null) return;
      final startedAtMs = lastSnapshotStartedAtMs;
      final elapsed = startedAtMs == null
          ? null
          : Duration(
              milliseconds: snapshotStopwatch.elapsedMilliseconds - startedAtMs,
            );
      if (elapsed == null || elapsed >= _sseSnapshotMinInterval) {
        unawaited(runSnapshot());
        return;
      }
      throttleTimer = startSafeTimer(
        _sseSnapshotMinInterval - elapsed,
        () {
          throttleTimer = null;
          return runSnapshot();
        },
        onError: (error, stack) {
          silentLog('web_message_platform_service', '调度 SSE 快照', error, stack);
        },
      );
    };

    void controllerListener() => scheduleSnapshot();

    void decrementSubscriptionCount(Map<String, int> counts, String key) {
      final next = (counts[key] ?? 1) - 1;
      if (next <= 0) {
        counts.remove(key);
      } else {
        counts[key] = next;
      }
    }

    dispose = () {
      if (disposed) return;
      disposed = true;
      throttleTimer?.cancel();
      keepaliveTimer?.cancel();
      snapshotStopwatch.stop();
      _sessionController.removeListener(controllerListener);
      _sessionController.streamThrottleOverrideSignal.removeListener(
        controllerListener,
      );
      _settingsController.removeListener(controllerListener);
      if (!controller.isClosed) {
        controller.close();
      }
      _activeSseDisposers.remove(dispose);
      _activeSseSubscriptions = math.max(0, _activeSseSubscriptions - 1);
      decrementSubscriptionCount(_activeSseSubscriptionsByClient, clientKey);
      decrementSubscriptionCount(_activeSseSubscriptionsBySession, session.id);
    };

    _sessionController.addListener(controllerListener);
    _sessionController.streamThrottleOverrideSignal.addListener(
      controllerListener,
    );
    _settingsController.addListener(controllerListener);
    keepaliveTimer = startSafePeriodicTimer(
      const Duration(seconds: 25),
      (_) {
        if (disposed || controller.isClosed) return;
        if (!authStillValid()) {
          closeUnauthorizedStream();
          return;
        }
        if (paused) return;
        try {
          final bytes = utf8.encode(':keepalive\n\n');
          controller.add(bytes);
          _recordStreamingOutboundBytes(bytes.length);
        } catch (error, stack) {
          silentLog(
            'web_message_platform_service',
            '发送 SSE 保活消息',
            error,
            stack,
          );
        }
      },
      onError: (error, stack) {
        silentLog('web_message_platform_service', '调度 SSE 保活消息', error, stack);
      },
    );

    controller.onCancel = dispose;
    controller.onPause = () {
      if (disposed) return;
      paused = true;
      throttleTimer?.cancel();
      throttleTimer = null;
      snapshotQueued = true;
    };
    controller.onResume = () {
      if (disposed) return;
      paused = false;
      snapshotQueued = false;
      lastSnapshotHash = null;
      scheduleSnapshot();
    };
    _activeSseSubscriptions += 1;
    _activeSseSubscriptionsByClient.update(
      clientKey,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    _activeSseSubscriptionsBySession.update(
      session.id,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    _activeSseDisposers.add(dispose);

    // 立即推送首帧，避免前端等待第一次 notifyListeners。
    Future<void>.microtask(() {
      lastSnapshotHash = null;
      scheduleSnapshot();
    });

    return shelf.Response.ok(
      controller.stream,
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: kTextEventStreamUtf8ContentType,
        HttpHeaders.cacheControlHeader: 'no-store, no-transform',
        HttpHeaders.connectionHeader: kConnectionKeepAlive,
        'x-accel-buffering': 'no',
      },
      context: const <String, Object>{'shelf.io.buffer_output': false},
    );
  }

  /// 媒体资产: 仅放行该会话消息 metadata 中显式引用过的本地文件路径,
  /// 防止任意路径读取与跨会话越权。
  Future<shelf.Response> _sessionAssetHandler(
    shelf.Request request,
    String sessionId,
  ) async {
    final auth = _authorizeFromRequestOrQuery(request);
    if (auth == null) {
      return _errorJson(HttpStatus.unauthorized, 'unauthorized');
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return _sessionMissingResponse();
    final requested = request.requestedUri.queryParameters['path'] ?? '';
    if (requested.isEmpty) {
      return _errorJson(HttpStatus.badRequest, 'missing_path');
    }
    final whitelist = _collectSessionAssetPaths(session);
    if (!whitelist.contains(requested)) {
      return _errorJson(HttpStatus.forbidden, 'asset_not_in_whitelist');
    }
    final file = File(requested);
    final FileStat stat;
    try {
      if (!await regularFileExistsBounded(file)) {
        return _errorJson(HttpStatus.notFound, 'asset_missing');
      }
      stat = await file.stat().timeout(defaultBoundedFileReadIdleTimeout);
    } on TimeoutException {
      return _errorJson(
        HttpStatus.requestTimeout,
        'asset_file_operation_timeout',
      );
    } on FileSystemException {
      return _errorJson(HttpStatus.notFound, 'asset_missing');
    }
    if (!isRegularFileStat(stat)) {
      return _errorJson(HttpStatus.notFound, 'asset_missing');
    }
    // 简单上限: 单文件 ≤ 512 MiB, 覆盖常见生成视频同时防止误暴露超大文件。
    const maxBytes = 512 * kBytesPerMiB;
    if (stat.size > maxBytes) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'asset_too_large',
        'limit_bytes': maxBytes,
      });
    }
    final totalBytes = stat.size;
    final contentType = _guessContentType(requested);
    final rangeHeader = request.headers[HttpHeaders.rangeHeader];
    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final range = _parseHttpByteRange(rangeHeader, totalBytes);
      if (range == null) {
        return shelf.Response(
          HttpStatus.requestedRangeNotSatisfiable,
          headers: <String, String>{
            HttpHeaders.contentRangeHeader: 'bytes */$totalBytes',
            HttpHeaders.acceptRangesHeader: 'bytes',
          },
        );
      }
      final length = range.endInclusive - range.start + 1;
      return shelf.Response(
        HttpStatus.partialContent,
        body: file.openRead(range.start, range.endInclusive + 1),
        headers: <String, String>{
          HttpHeaders.contentTypeHeader: contentType,
          HttpHeaders.cacheControlHeader: 'private, max-age=300',
          HttpHeaders.contentLengthHeader: length.toString(),
          HttpHeaders.acceptRangesHeader: 'bytes',
          HttpHeaders.contentRangeHeader:
              'bytes ${range.start}-${range.endInclusive}/$totalBytes',
        },
      );
    }
    return shelf.Response.ok(
      file.openRead(),
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: contentType,
        HttpHeaders.cacheControlHeader: 'private, max-age=300',
        HttpHeaders.contentLengthHeader: totalBytes.toString(),
        HttpHeaders.acceptRangesHeader: 'bytes',
      },
    );
  }

  _HttpByteRange? _parseHttpByteRange(String value, int totalBytes) {
    if (totalBytes <= 0) {
      return null;
    }
    final rawRange = value.substring('bytes='.length).split(',').first.trim();
    final separator = rawRange.indexOf('-');
    if (separator <= -1) {
      return null;
    }
    final rawStart = rawRange.substring(0, separator).trim();
    final rawEnd = rawRange.substring(separator + 1).trim();
    int start;
    int end;
    if (rawStart.isEmpty) {
      final suffixLength = optionalPositiveIntFromValue(rawEnd);
      if (suffixLength == null) {
        return null;
      }
      start = math.max(0, totalBytes - suffixLength);
      end = totalBytes - 1;
    } else {
      start = optionalNonNegativeIntFromValue(rawStart) ?? -1;
      end = rawEnd.isEmpty
          ? totalBytes - 1
          : optionalNonNegativeIntFromValue(rawEnd) ?? -1;
    }
    if (start < 0 || end < start || start >= totalBytes) {
      return null;
    }
    return _HttpByteRange(
      start: start,
      endInclusive: math.min(end, totalBytes - 1),
    );
  }

  /// 收集 session 内所有消息的 metadata 中可能指向本地媒体文件的字段,
  /// 形成白名单 (绝对路径集合)。
  Set<String> _collectSessionAssetPaths(AiSession session) {
    final out = <String>{};
    void addCandidate(Object? raw) {
      if (raw is String) {
        final s = raw.trim();
        if (s.isNotEmpty &&
            !s.startsWith('http://') &&
            !s.startsWith('https://') &&
            !s.startsWith('data:') &&
            !s.startsWith('blob:')) {
          out.add(s);
        }
      }
    }

    for (final msg in session.displayMessages) {
      final meta = msg.metadata;
      // 用户附件: [{kind, path}] / [{file_path}] / [{storage_path}]
      final atts = meta['attachments'];
      if (atts is List) {
        for (final entry in atts) {
          if (entry is Map) {
            addCandidate(entry['path']);
            addCandidate(entry['file_path']);
            addCandidate(entry['storage_path']);
            addCandidate(entry['original_source_path']);
          } else if (entry is String) {
            addCandidate(entry);
          }
        }
      }
      // 助手生成媒体: 兼容多种命名
      for (final key in const [
        'image_path',
        'image_paths',
        'video_path',
        'video_paths',
        'audio_path',
        'audio_paths',
        'generated_image_path',
        'generated_image_paths',
        'generated_video_path',
        'generated_video_paths',
        'generated_audio_path',
        'generated_audio_paths',
        'media_path',
        'media_paths',
      ]) {
        final v = meta[key];
        if (v is String) {
          addCandidate(v);
        } else if (v is List) {
          for (final e in v) {
            addCandidate(e);
          }
        }
      }
      for (final path in _collectMessageContentAssetPaths(msg.content)) {
        addCandidate(path);
      }
    }
    return out;
  }

  Iterable<String> _collectMessageContentAssetPaths(String content) sync* {
    if (content.isEmpty || !content.contains('openhand_media')) {
      return;
    }
    for (final match in _markdownMediaReferencePattern.allMatches(content)) {
      final raw = match.group(1);
      if (raw == null) continue;
      final path = _normalizeMarkdownDestination(raw);
      if (_isGeneratedInlineMediaPath(path)) yield path;
    }
    for (final match in _htmlMediaSrcPattern.allMatches(content)) {
      final raw = match.group(1);
      if (raw == null) continue;
      final path = raw.trim();
      if (_isGeneratedInlineMediaPath(path)) yield path;
    }
  }

  String _normalizeMarkdownDestination(String raw) {
    var value = raw.trim();
    if (value.startsWith('<')) {
      final close = value.indexOf('>');
      if (close > 0) {
        return value.substring(1, close).trim();
      }
    }
    final title = RegExp(
      r'''\s+(?:"[^"]*"|'[^']*'|\([^)]*\))\s*$''',
    ).firstMatch(value);
    if (title != null) {
      value = value.substring(0, title.start).trim();
    }
    return value;
  }

  bool _isGeneratedInlineMediaPath(String rawPath) {
    var value = rawPath.trim();
    if (value.isEmpty ||
        value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('data:') ||
        value.startsWith('blob:')) {
      return false;
    }
    if (value.startsWith('file://')) {
      final uri = Uri.tryParse(value);
      if (uri == null || !uri.isScheme('file')) return false;
      try {
        value = uri.toFilePath();
      } on UnsupportedError {
        return false;
      }
    }
    final inlineDir = p.normalize(
      p.join(Directory.systemTemp.path, 'openhand_media'),
    );
    final normalized = p.normalize(value);
    return normalized == inlineDir || p.isWithin(inlineDir, normalized);
  }

  static final RegExp _markdownMediaReferencePattern = RegExp(
    r'''!?\[[^\]\r\n]{0,240}\]\(([^)\r\n]+)\)''',
  );
  static final RegExp _htmlMediaSrcPattern = RegExp(
    r'''<(?:img|video|audio|source)\b[^>]*\bsrc\s*=\s*["']([^"']+)["'][^>]*>''',
    caseSensitive: false,
  );
  static final RegExp _heAgentAnnotationPattern = RegExp(
    r'\[HE_AGENT:(\w+)\|([^\]]+)\]',
  );
  static final RegExp _hePhaseAnnotationPattern = RegExp(r'\[HE_PHASE:(\w+)\]');
  static const Set<String> _webVideoMediaExtensions = <String>{
    '.mp4',
    '.webm',
    '.mov',
    '.m4v',
  };
  static const Set<String> _webAudioMediaExtensions = <String>{
    '.mp3',
    '.wav',
    '.ogg',
    '.m4a',
    '.flac',
    '.aac',
  };

  /// 复用 _authorize，但允许从 query string 读取 token / device 信息，
  /// 兼容浏览器 EventSource 这种不能自定义 header 的场景。
  _WebGatewayAuthSession? _authorizeFromRequestOrQuery(shelf.Request request) {
    if (!_config.authEnabled) {
      // 匿名模式下 EventSource 无法带自定义 header，因此 query string 是
      // `/events` 的首选身份来源；手写 HTTP 调用仍可回落到 header。
      final qp = request.requestedUri.queryParameters;
      String pick(
        String queryKey,
        String headerKey,
        String fallback, {
        int maxCharacters = _maxAuthMetadataCharacters,
      }) {
        final queryValue = qp[queryKey]?.trim();
        if (queryValue != null && queryValue.isNotEmpty) {
          return _boundedAuthText(queryValue, maxCharacters);
        }
        final headerValue = request.headers[headerKey]?.trim();
        if (headerValue != null && headerValue.isNotEmpty) {
          return _boundedAuthText(headerValue, maxCharacters);
        }
        return _boundedAuthText(fallback, maxCharacters);
      }

      final deviceId = pick(
        'device_id',
        'x-openhand-device-id',
        'anonymous-web',
        maxCharacters: _maxAuthDeviceIdCharacters,
      );
      return _WebGatewayAuthSession(
        token: 'anonymous',
        source: WebGatewayLoginSource.fromStorage(
          pick('source', 'x-openhand-source', 'WEB_PC'),
        ),
        deviceId: deviceId,
        deviceMacAddress: pick(
          'device_mac_address',
          'x-openhand-device-mac',
          '',
        ),
        deviceName: pick(
          'device_name',
          'x-openhand-device-name',
          'OpenHand Web',
        ),
        devicePlatform: pick(
          'device_platform',
          'x-openhand-device-platform',
          'web',
        ),
        osName: pick('os_name', 'x-openhand-os-name', ''),
        osVersion: pick('os_version', 'x-openhand-os-version', ''),
        browserName: pick('browser_name', 'x-openhand-browser-name', ''),
        browserVersion: pick(
          'browser_version',
          'x-openhand-browser-version',
          '',
        ),
        webClientVersion: pick(
          'web_client_version',
          'x-openhand-web-client-version',
          '',
        ),
        locale: pick('locale', 'x-openhand-locale', ''),
        timezone: pick('timezone', 'x-openhand-timezone', ''),
        screenClass: pick('screen_class', 'x-openhand-screen-class', ''),
        loginAt: DateTime.now().toUtc(),
        issuedAt: _monotonicStopwatch.elapsed,
        remoteAddress: _requestRemoteAddress(request),
        userAgent: _boundedAuthText(
          request.headers[HttpHeaders.userAgentHeader],
          _maxAuthUserAgentCharacters,
        ),
      );
    }
    final fromHeader = _authorize(request);
    if (fromHeader != null) return fromHeader;
    final token = request.requestedUri.queryParameters['token']?.trim() ?? '';
    if (token.isEmpty || token.length > _maxAuthTokenCharacters) return null;
    return _authSessionForToken(token);
  }

  Future<shelf.Response> _listLogs(shelf.Request request) async {
    final offset = _queryInt(request, 'offset', fallback: 0, min: 0);
    final limit = _queryInt(
      request,
      'limit',
      fallback: _config.logConfig.lazyReadPageSize,
      min: 1,
      max: 2000,
    );
    final slice = _memoryLogs.skip(offset).take(limit).toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{
      'items': slice.map((entry) => entry.toJson()).toList(growable: false),
      'offset': offset,
      'limit': limit,
      'total': _memoryLogs.length,
      'has_more': offset + slice.length < _memoryLogs.length,
    });
  }

  Future<shelf.Response> _cleanupOps(shelf.Request request) async {
    if (!_config.opsEnabled) {
      return _json(HttpStatus.forbidden, const <String, Object?>{
        'error': 'ops_disabled',
      });
    }
    final body = await _readJsonBody(request);
    final target = _string(body['target'], 'all').trim().toLowerCase();
    final expiredOnly = body['expired_only'] as bool? ?? false;
    final logs = target == 'logs' || target == 'all';
    final uploads = target == 'uploads' || target == 'all';
    if (!logs && !uploads) {
      return _errorJson(HttpStatus.badRequest, 'invalid_cleanup_target');
    }
    final result = await cleanupArtifacts(
      logs: logs,
      uploads: uploads,
      expiredOnly: expiredOnly,
    );
    return _json(HttpStatus.ok, result.toJson());
  }

  Future<shelf.Response> _cleanupHistoryPayload() async {
    if (!_config.opsEnabled) {
      return _json(HttpStatus.forbidden, const <String, Object?>{
        'error': 'ops_disabled',
      });
    }
    return _json(HttpStatus.ok, <String, Object?>{
      'items': _cleanupHistory.reversed
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'total': _cleanupHistory.length,
      'max_items': webGatewayOpsMaxCleanupHistory,
    });
  }

  Future<shelf.Response> _exportLogs() async {
    final body = await exportLogBundleJson();
    return shelf.Response.ok(
      body,
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: kApplicationJsonUtf8ContentType,
        HttpHeaders.cacheControlHeader: kCacheControlNoStore,
        'content-disposition':
            'attachment; filename="openhand-web-gateway-logs.json"',
      },
    );
  }

  Future<Map<String, Object?>> _logBundlePayload() async {
    return <String, Object?>{
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'service': webMessagePlatformBuiltinName,
      'memory_logs': _memoryLogs.map((entry) => entry.toJson()).toList(),
      'disk_logs': await _fileLogger.readBundle(),
    };
  }

  Future<shelf.Response> _listWorkspaceFiles(shelf.Request request) async {
    final relative = request.requestedUri.queryParameters['path'] ?? '';
    final query = (request.requestedUri.queryParameters['q'] ?? '')
        .trim()
        .toLowerCase();
    final typeFilter = (request.requestedUri.queryParameters['type'] ?? 'all')
        .trim()
        .toLowerCase();
    final extensionFilter = _workspaceExtensionsForQuery(
      request.requestedUri.queryParameters['extensions'],
    );
    final dir = await _resolveWorkspacePath(relative);
    if (dir == null ||
        await _awaitWorkspaceFileOperation(FileSystemEntity.type(dir)) !=
            FileSystemEntityType.directory) {
      return _errorJson(HttpStatus.notFound, 'directory_not_found');
    }
    final root = _workspaceDirectoryPath;
    final listing = await listDirectoryBounded(
      Directory(dir),
      maxEntries: _maxWorkspaceDirectoryScanEntries,
    );
    final entries = listing.entries.toList(growable: false)
      ..sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });
    final items = <Map<String, Object?>>[];
    var metadataTruncated = listing.truncated;
    final metadataStopwatch = Stopwatch()..start();
    for (final entry in entries) {
      final isDirectory = entry is Directory;
      final entryType = isDirectory ? 'directory' : 'file';
      if (typeFilter == 'file' && isDirectory) continue;
      if (typeFilter == 'directory' && !isDirectory) continue;
      if (!isDirectory &&
          !_workspaceExtensionAllowed(entry.path, extensionFilter)) {
        continue;
      }
      final relativePath = _relativeWorkspacePath(entry.path);
      final name = p.basename(entry.path);
      if (query.isNotEmpty &&
          !name.toLowerCase().contains(query) &&
          !relativePath.toLowerCase().contains(query)) {
        continue;
      }
      final remaining =
          _workspaceMetadataTotalTimeout - metadataStopwatch.elapsed;
      if (remaining <= Duration.zero) {
        metadataTruncated = true;
        break;
      }
      final statTimeout = remaining < _workspaceMetadataTimeout
          ? remaining
          : _workspaceMetadataTimeout;
      FileStat stat;
      try {
        stat = await entry.stat().timeout(statTimeout);
      } on TimeoutException {
        metadataTruncated = true;
        break;
      } on FileSystemException {
        continue;
      }
      items.add(<String, Object?>{
        'name': name,
        'path': relativePath,
        'type': entryType,
        'size': stat.size,
        'modified_at': stat.modified.toUtc().toIso8601String(),
        if (!isDirectory) 'extension': p.extension(entry.path).toLowerCase(),
        if (!isDirectory)
          'editable': stat.size <= _config.workspaceFileMaxBytes,
      });
      if (items.length >= 300) break;
    }
    metadataStopwatch.stop();
    return _json(HttpStatus.ok, <String, Object?>{
      'root': root,
      'path': _relativeWorkspacePath(dir),
      'items': items,
      'truncated': metadataTruncated || items.length >= 300,
      'query': query,
      'type': typeFilter,
      'operations_enabled': _config.workspaceFileWriteEnabled,
      'write_enabled': _config.workspaceFileWriteEnabled,
      'max_file_bytes': _config.workspaceFileMaxBytes,
      'allowed_extensions': _config.workspaceFileAllowedExtensions,
    });
  }

  Future<shelf.Response> _readWorkspaceFile(shelf.Request request) async {
    final relative = request.requestedUri.queryParameters['path'] ?? '';
    final filePath = await _resolveWorkspacePath(relative);
    if (filePath == null ||
        await _awaitWorkspaceFileOperation(FileSystemEntity.type(filePath)) !=
            FileSystemEntityType.file) {
      return _errorJson(HttpStatus.notFound, 'file_not_found');
    }
    if (!_workspaceExtensionAllowed(filePath, _workspaceAllowedExtensions())) {
      return _errorJson(HttpStatus.forbidden, 'file_extension_not_allowed');
    }
    final file = File(filePath);
    final Uint8List bytes;
    final FileStat stat;
    try {
      bytes = await readBoundedFileBytes(
        file,
        maxBytes: _config.workspaceFileMaxBytes,
        idleTimeout: defaultBoundedFileReadIdleTimeout,
        totalTimeout: defaultBoundedFileReadTotalTimeout,
      );
      stat = await _awaitWorkspaceFileOperation(file.stat());
    } on BoundedFileReadException catch (error) {
      if (error.failure != BoundedFileReadFailure.tooLarge) rethrow;
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'file_too_large',
        'limit_bytes': _config.workspaceFileMaxBytes,
      });
    } on FileSystemException {
      return _errorJson(HttpStatus.notFound, 'file_not_found');
    }
    if (_looksBinary(bytes)) {
      return _errorJson(HttpStatus.badRequest, 'binary_file_not_supported');
    }
    return _json(HttpStatus.ok, <String, Object?>{
      'path': _relativeWorkspacePath(filePath),
      'content': utf8.decode(bytes, allowMalformed: true),
      'size': stat.size,
      'modified_at': stat.modified.toUtc().toIso8601String(),
    });
  }

  Future<shelf.Response> _writeWorkspaceFile(shelf.Request request) async {
    if (!_config.workspaceFileWriteEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'workspace_file_operations_disabled',
        'message': 'App 端未开启“是否支持操作文件”，Web 端只能浏览和读取项目文件。',
      });
    }
    final body = await _readJsonBody(
      request,
      maxBytes: _config.workspaceFileMaxBytes + 1024,
    );
    final relative = _string(body['path'], '');
    final content = _string(body['content'], '');
    if (utf8.encode(content).length > _config.workspaceFileMaxBytes) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'content_too_large',
        'limit_bytes': _config.workspaceFileMaxBytes,
      });
    }
    final filePath = await _resolveWorkspacePath(relative);
    if (filePath == null) {
      return _errorJson(HttpStatus.badRequest, 'path_outside_workspace');
    }
    if (!_workspaceExtensionAllowed(filePath, _workspaceAllowedExtensions())) {
      return _errorJson(HttpStatus.forbidden, 'file_extension_not_allowed');
    }
    final file = File(filePath);
    await writeFileAtomically(file, content);
    _fileMutationCount++;
    final stat = await _awaitWorkspaceFileOperation(file.stat());
    _log(WebGatewayLogLevel.warn, 'FILES', 'Web 写入项目文件', <String, Object?>{
      'path': _relativeWorkspacePath(filePath),
      'size': stat.size,
    });
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'path': _relativeWorkspacePath(filePath),
      'size': stat.size,
      'modified_at': stat.modified.toUtc().toIso8601String(),
    });
  }

  Future<shelf.Response> _createWorkspaceDirectory(
    shelf.Request request,
  ) async {
    if (!_config.workspaceFileWriteEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'workspace_file_operations_disabled',
        'message': 'App 端未开启“是否支持操作文件”，Web 端只能浏览和读取项目文件。',
      });
    }
    final body = await _readJsonBody(request, maxBytes: 16 * kBytesPerKiB);
    final relative = _string(body['path'], '');
    if (relative.trim().isEmpty || relative == '.' || relative == '/') {
      return _errorJson(HttpStatus.badRequest, 'path_required');
    }
    final dirPath = await _resolveWorkspacePath(relative);
    if (dirPath == null) {
      return _errorJson(HttpStatus.badRequest, 'path_outside_workspace');
    }
    final type = await _awaitWorkspaceFileOperation(
      FileSystemEntity.type(dirPath, followLinks: false),
    );
    if (type == FileSystemEntityType.file) {
      return _errorJson(HttpStatus.conflict, 'file_already_exists');
    }
    await _awaitWorkspaceFileOperation(
      Directory(dirPath).create(recursive: true),
    );
    if (type == FileSystemEntityType.notFound) _fileMutationCount++;
    final stat = await _awaitWorkspaceFileOperation(Directory(dirPath).stat());
    _log(WebGatewayLogLevel.warn, 'FILES', 'Web 创建项目目录', <String, Object?>{
      'path': _relativeWorkspacePath(dirPath),
    });
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'path': _relativeWorkspacePath(dirPath),
      'modified_at': stat.modified.toUtc().toIso8601String(),
    });
  }

  /// 删除 workspace 内的单个文件或空目录。受 `workspaceFileWriteEnabled` 闸门保护，
  /// 必须 query `?path=...`，路径校验复用 `_resolveWorkspacePath` 防穿越。
  /// 目录非空时返回 `directory_not_empty`；不递归删，避免误删大批数据。
  Future<shelf.Response> _deleteWorkspaceFile(shelf.Request request) async {
    if (!_config.workspaceFileWriteEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'workspace_file_operations_disabled',
        'message': 'App 端未开启“是否支持操作文件”，Web 端只能浏览和读取项目文件。',
      });
    }
    final relative = request.requestedUri.queryParameters['path'] ?? '';
    if (relative.trim().isEmpty || relative == '.' || relative == '/') {
      return _errorJson(HttpStatus.badRequest, 'path_required');
    }
    final resolved = await _resolveWorkspacePath(relative);
    if (resolved == null) {
      return _errorJson(HttpStatus.badRequest, 'path_outside_workspace');
    }
    final type = await _awaitWorkspaceFileOperation(
      FileSystemEntity.type(resolved, followLinks: false),
    );
    if (type == FileSystemEntityType.notFound) {
      return _errorJson(HttpStatus.notFound, 'not_found');
    }
    if (type == FileSystemEntityType.directory) {
      // 不递归：让用户明确清空再删（避免一次误调清掉整棵子树）。
      if (!await isDirectoryEmpty(Directory(resolved))) {
        return _errorJson(HttpStatus.conflict, 'directory_not_empty');
      }
      await _awaitWorkspaceFileOperation(Directory(resolved).delete());
    } else {
      if (!_workspaceExtensionAllowed(
        resolved,
        _workspaceAllowedExtensions(),
      )) {
        return _errorJson(HttpStatus.forbidden, 'file_extension_not_allowed');
      }
      await _awaitWorkspaceFileOperation(File(resolved).delete());
    }
    _fileMutationCount++;
    _log(WebGatewayLogLevel.warn, 'FILES', 'Web 删除项目文件', <String, Object?>{
      'path': _relativeWorkspacePath(resolved),
      'kind': type.toString(),
    });
    return _json(HttpStatus.ok, <String, Object?>{
      'ok': true,
      'path': _relativeWorkspacePath(resolved),
    });
  }

  _WebGatewayAuthSession? _authorize(shelf.Request request) {
    if (!_config.authEnabled) {
      String header(
        String name, {
        String fallback = '',
        int maxCharacters = _maxAuthMetadataCharacters,
      }) {
        return _boundedAuthText(
          request.headers[name] ?? fallback,
          maxCharacters,
        );
      }

      final deviceId = header(
        'x-openhand-device-id',
        fallback: 'anonymous-web',
        maxCharacters: _maxAuthDeviceIdCharacters,
      );
      return _WebGatewayAuthSession(
        token: 'anonymous',
        source: WebGatewayLoginSource.fromStorage(
          header('x-openhand-source', fallback: 'WEB_PC'),
        ),
        deviceId: deviceId,
        deviceMacAddress: header('x-openhand-device-mac'),
        deviceName: header('x-openhand-device-name'),
        devicePlatform: header('x-openhand-device-platform'),
        osName: header('x-openhand-os-name'),
        osVersion: header('x-openhand-os-version'),
        browserName: header('x-openhand-browser-name'),
        browserVersion: header('x-openhand-browser-version'),
        webClientVersion: header('x-openhand-web-client-version'),
        locale: header('x-openhand-locale'),
        timezone: header('x-openhand-timezone'),
        screenClass: header('x-openhand-screen-class'),
        loginAt: DateTime.now().toUtc(),
        issuedAt: _monotonicStopwatch.elapsed,
        remoteAddress: _requestRemoteAddress(request),
        userAgent: header(
          HttpHeaders.userAgentHeader,
          maxCharacters: _maxAuthUserAgentCharacters,
        ),
      );
    }
    final authHeader = request.headers[HttpHeaders.authorizationHeader] ?? '';
    if (!authHeader.startsWith('Bearer ')) return null;
    final token = authHeader.substring('Bearer '.length).trim();
    if (token.isEmpty || token.length > _maxAuthTokenCharacters) return null;
    return _authSessionForToken(token);
  }

  AiSession? _findAuthorizedSession(
    _WebGatewayAuthSession auth,
    String sessionId,
  ) {
    for (final session in _sessionController.sessions) {
      if (session.id != sessionId) continue;
      if (_authCanAccessAllSessions(auth)) return session;
      final context = _webContext(session.metadata);
      if (_string(context['device_id'], '') != auth.deviceId) return null;
      if (_string(context['login_source'], '') != auth.source.storageValue) {
        return null;
      }
      return session;
    }
    return null;
  }

  AiSession? _findAuthorizedMachineTerminalSession(
    _WebGatewayAuthSession auth,
    String sessionId,
  ) {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) return null;
    if (session.templateId != kMachineExpertTemplateId) return null;
    return session;
  }

  void _rememberMachineTerminalSessionMetadata(AiSession session) {
    _machineTerminalService.rememberSessionMetadata(
      sessionId: session.id,
      metadata: session.metadata[kMachineTerminalMetadataKey],
    );
  }

  String _machineTerminalWorkingDirectory(AiSession session) {
    return MachineTerminalSessionMetadata.defaultWorkingDirectoryFrom(
          session.metadata[kMachineTerminalMetadataKey],
        ) ??
        _workspaceDirectoryPath;
  }

  shelf.Response _machineTerminalUnavailable(
    _WebGatewayAuthSession auth,
    String sessionId,
  ) {
    final exists = _findAuthorizedSession(auth, sessionId) != null;
    return _json(
      exists ? HttpStatus.forbidden : HttpStatus.notFound,
      <String, Object?>{
        'error': exists
            ? 'machine_terminal_not_available'
            : _kWebGatewayErrorSessionMissing,
      },
    );
  }

  int _terminalTimeoutMs(Map<String, Object?> body) {
    final raw =
        optionalIntFromValue(body['timeout_ms']) ??
        optionalIntFromValue(body['timeout']) ??
        kMachineTerminalDefaultCommandTimeout.inMilliseconds;
    return clampMachineTerminalCommandTimeoutMs(raw);
  }

  int _clampMilliseconds(int value, {required int min, required int max}) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  Future<AiSessionMessage?> _loadMessageForWebOperation(
    AiSession session,
    String messageId,
  ) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) return null;
    for (final message in session.displayMessages) {
      if (message.id == normalizedMessageId) return message;
    }
    final hydrated =
        await _sessionController.ensureSessionMessagesHydrated(session.id) ??
        session;
    for (final message in hydrated.displayMessages) {
      if (message.id == normalizedMessageId) return message;
    }
    try {
      return await _sessionController.store.loadMessage(
        session.id,
        normalizedMessageId,
      );
    } catch (error, stack) {
      silentLog('web_message_platform_service', '加载 Web 操作消息', error, stack);
      return null;
    }
  }

  bool _messageSupportsWebFeedback(AiSessionMessage message) {
    return message.kind == AiSessionMessageKind.user ||
        message.kind == AiSessionMessageKind.assistant;
  }

  bool _messageSupportsWebRegeneration(AiSessionMessage message) {
    return message.kind == AiSessionMessageKind.assistant &&
        !_boolishWebValue(
          message.metadata[aiSessionMessageMetadataStreamingKey],
        );
  }

  bool _messageSupportsWebTextAction(AiSessionMessage message) {
    if (message.content.trim().isEmpty) return false;
    if (_boolishWebValue(
      message.metadata[aiSessionMessageMetadataStreamingKey],
    )) {
      return false;
    }
    final kindSupported =
        message.kind == AiSessionMessageKind.user ||
        message.kind == AiSessionMessageKind.assistant ||
        message.kind == AiSessionMessageKind.reasoning;
    if (!kindSupported) return false;
    final contentFormat = _webMessageContentFormat(message);
    if (contentFormat == AiMessageContentFormat.html) return false;
    return !_messageHasWebMultimediaPayload(message);
  }

  AiMessageContentFormat _webMessageContentFormat(AiSessionMessage message) {
    final storedKey = message.metadata[aiSessionMessageContentFormatKey];
    if (storedKey is String && storedKey.trim().isNotEmpty) {
      return AiMessageContentFormat.fromStorageKey(storedKey);
    }
    return _settingsController.aiMessageContentFormat;
  }

  String? _webTtsMessageText(AiSessionMessage message) {
    final content = message.content.trim();
    return content.isEmpty ? null : content;
  }

  String? _webTranslationMessageText(
    AiSessionMessage message,
    AiTranslationSettings settings,
  ) {
    if (!settings.enabled) return null;
    final content = switch (message.kind) {
      AiSessionMessageKind.assistant => _stripHeAnnotations(message.content),
      AiSessionMessageKind.user ||
      AiSessionMessageKind.reasoning => message.content,
      _ => '',
    }.trim();
    return content.isEmpty ? null : content;
  }

  Map<String, Object?> _ttsPlaybackPayload() {
    final snapshot = _ttsPlaybackService.state.value;
    return <String, Object?>{
      'playing': snapshot.playing,
      'message_id': snapshot.messageId,
      'provider': snapshot.provider?.storageKey,
      'error': snapshot.error,
      'failure_id': snapshot.failureId?.toString(),
    };
  }

  bool _messageHasWebMultimediaPayload(AiSessionMessage message) {
    final metadata = message.metadata;
    if (_nonEmptyList(metadata['attachments'])) return true;
    if ((optionalRoundedIntFromValue(metadata['attachment_count']) ?? 0) > 0) {
      return true;
    }
    if (_nonEmptyList(metadata['generated_image_paths']) ||
        _nonEmptyList(metadata['generated_video_paths']) ||
        _nonEmptyList(metadata['generated_audio_paths'])) {
      return true;
    }
    final directMode = _string(metadata['conversation_mode'], '').trim();
    if (_isMultimediaConversationMode(directMode)) return true;
    final creationRequest = metadata['creation_request'];
    if (creationRequest is Map) {
      final mode = _string(creationRequest['mode'], '').trim();
      if (_isMultimediaConversationMode(mode)) return true;
    }
    return _messageContentHasWebMultimediaLink(message.content);
  }

  bool _messageContentHasWebMultimediaLink(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    final lower = trimmed.toLowerCase();
    if ((lower.contains('<img') ||
            lower.contains('<video') ||
            lower.contains('<audio')) &&
        _htmlMediaSrcPattern.hasMatch(trimmed)) {
      return true;
    }
    if (!trimmed.contains('](') && !trimmed.contains('![')) {
      return false;
    }
    for (final match in _markdownMediaReferencePattern.allMatches(trimmed)) {
      final raw = match.group(1);
      if (raw == null) continue;
      final destination = _normalizeMarkdownDestination(raw);
      final extension = p
          .extension(Uri.tryParse(destination)?.path ?? destination)
          .toLowerCase();
      if (match.group(0)?.startsWith('![') == true ||
          _webVideoMediaExtensions.contains(extension) ||
          _webAudioMediaExtensions.contains(extension) ||
          aiAttachmentKindForPath(destination) == AiAttachmentKind.image) {
        return true;
      }
    }
    return false;
  }

  bool _nonEmptyList(Object? value) => value is List && value.isNotEmpty;

  bool _boolishWebValue(Object? value) {
    final parsed = optionalBoolFromValue(value);
    if (parsed != null) return parsed;
    if (value is num) return value != 0;
    return false;
  }

  bool _isMultimediaConversationMode(String mode) {
    return mode == 'image' || mode == 'video' || mode == 'audio';
  }

  String _stripHeAnnotations(String content) {
    return content
        .replaceAll(_heAgentAnnotationPattern, '')
        .replaceAll(_hePhaseAnnotationPattern, '')
        .replaceAll(RegExp(r'^\s+'), '')
        .trim();
  }

  Map<String, Object?>? _pendingWriteApprovalJson(String sessionId) {
    for (final approval in _pendingWriteApprovals.values) {
      if (approval.sessionId == sessionId && !approval.completer.isCompleted) {
        return approval.toJson();
      }
    }
    return null;
  }

  List<WebWriteApprovalRequest> _pendingWriteApprovalSnapshot() {
    return _pendingWriteApprovals.values
        .where((approval) => !approval.completer.isCompleted)
        .map(WebWriteApprovalRequest._fromInternal)
        .toList(growable: false);
  }

  void _notifyPendingWriteApprovals() {
    if (_pendingWriteApprovalStreamController.isClosed) {
      return;
    }
    _pendingWriteApprovalStreamController.add(_pendingWriteApprovalSnapshot());
  }

  Future<BashCommandApprovalDecision> requestWriteApproval({
    required String sessionId,
    required BashCommandApprovalRequest request,
    String source = 'app',
  }) {
    return _registerPendingWriteApproval(sessionId, request, source: source);
  }

  bool respondWriteApproval(
    String approvalId, {
    required BashCommandApprovalDecision decision,
    String source = 'app',
  }) {
    final approval = _pendingWriteApprovals[approvalId];
    if (approval == null) {
      return false;
    }
    return _completePendingWriteApproval(
      approval,
      decision: decision,
      source: source,
    );
  }

  Future<BashCommandApprovalDecision> _confirmWebWriteCommand(
    String sessionId,
    BashCommandApprovalRequest request,
  ) async {
    return _registerPendingWriteApproval(sessionId, request, source: 'web');
  }

  Future<BashCommandApprovalDecision> _registerPendingWriteApproval(
    String sessionId,
    BashCommandApprovalRequest request, {
    required String source,
  }) async {
    if (_pendingWriteApprovals.length >= _maxPendingWriteApprovals) {
      _log(
        WebGatewayLogLevel.warn,
        'APPROVAL',
        '待确认写操作已达上限，取消新请求',
        <String, Object?>{
          'session_id': sessionId,
          'source': source,
          'limit': _maxPendingWriteApprovals,
        },
      );
      return BashCommandApprovalDecision.cancelled;
    }
    final createdAt = DateTime.now().toUtc();
    final timeoutMs = _settingsController.aiWriteConfirmationTimeoutMs;
    final timeout = Duration(milliseconds: timeoutMs);
    final completer = Completer<BashCommandApprovalDecision>();
    final approval = _WebWriteApprovalRequest(
      id: '${createdAt.microsecondsSinceEpoch}-${_nextWriteApprovalId++}',
      sessionId: sessionId,
      command: request.command,
      workingDirectory: request.workingDirectory,
      isWriteCommand: request.isWriteCommand,
      createdAt: createdAt,
      expiresAt: createdAt.add(timeout),
      completer: completer,
      source: source,
    );
    _pendingWriteApprovals[approval.id] = approval;
    _sessionController.setSessionAwaitingApproval(sessionId);
    _notifyPendingWriteApprovals();
    _log(WebGatewayLogLevel.warn, 'APPROVAL', '等待写操作确认', <String, Object?>{
      'session_id': sessionId,
      'approval_id': approval.id,
      'source': source,
      'working_directory': request.workingDirectory,
    });
    final timer = startSafeTimer(timeout, () {
      _completePendingWriteApproval(
        approval,
        decision: BashCommandApprovalDecision.timedOut,
        source: 'timeout',
      );
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      _pendingWriteApprovals.remove(approval.id);
      final hasRemainingApproval = _pendingWriteApprovals.values.any(
        (item) => item.sessionId == sessionId && !item.completer.isCompleted,
      );
      if (!hasRemainingApproval) {
        _sessionController.clearSessionAwaitingApproval(sessionId);
      }
      _notifyPendingWriteApprovals();
    }
  }

  bool _completePendingWriteApproval(
    _WebWriteApprovalRequest approval, {
    required BashCommandApprovalDecision decision,
    required String source,
    String? deviceId,
  }) {
    if (approval.completer.isCompleted) {
      return false;
    }
    approval.completer.complete(decision);
    _notifyPendingWriteApprovals();
    _sessionController.notifyListeners();
    final level = decision == BashCommandApprovalDecision.approved
        ? WebGatewayLogLevel.success
        : WebGatewayLogLevel.warn;
    final humanLabel = switch (decision) {
      BashCommandApprovalDecision.approved => '批准写操作',
      BashCommandApprovalDecision.rejected => '拒绝写操作',
      BashCommandApprovalDecision.dismissed => '弹窗被关闭（用户未明确表态）',
      BashCommandApprovalDecision.timedOut => '写操作确认超时',
      BashCommandApprovalDecision.cancelled => '写操作确认已取消',
    };
    _log(level, 'APPROVAL', humanLabel, <String, Object?>{
      'session_id': approval.sessionId,
      'approval_id': approval.id,
      'source': source,
      'decision': decision.name,
      if (deviceId != null) 'device_id': deviceId,
    });
    return true;
  }

  void _resolvePendingWriteApprovals({
    String? sessionId,
    required BashCommandApprovalDecision decision,
    required String source,
  }) {
    for (final approval in _pendingWriteApprovals.values.toList()) {
      if (sessionId == null || approval.sessionId == sessionId) {
        _completePendingWriteApproval(
          approval,
          decision: decision,
          source: source,
        );
      }
    }
  }

  bool _authCanAccessAllSessions(_WebGatewayAuthSession auth) {
    return _config.authEnabled && auth.token != 'anonymous';
  }

  Map<String, Object?> _metadataForRequest(
    _WebGatewayAuthSession auth,
    shelf.Request request,
    Map<String, Object?> extra,
  ) {
    return buildWebGatewayRequestMetadata(
      authMetadata: auth.toMetadata(),
      requestMethod: request.method,
      requestPath: request.requestedUri.path,
      requestId: _nextLogId,
      extras: extra,
    );
  }

  Map<String, Object?> _webContext(Map<String, Object?> metadata) {
    final raw = metadata[webGatewayMetadataKey];
    if (raw is Map) return stringKeyedMapFromValue(raw);
    return const <String, Object?>{};
  }

  String? _allowedModelKeyFromValue(Object? value) {
    if (value is! String) return null;
    final key = value.trim();
    if (key.isEmpty) return null;
    for (final model in _allowedModels()) {
      if (model.key == key) return key;
    }
    return null;
  }

  String? _lastModelProtocolForSession(AiSession session) {
    final providerId = session.lastUsedModelId;
    if (providerId == null || providerId.isEmpty) return null;
    return _settingsController.aiModels
        .where((model) => model.id == providerId)
        .map((model) => model.protocolType.storageValue)
        .firstOrNull;
  }

  bool _isSessionInputCacheModelSelectionLocked(
    AiSession session, {
    Iterable<AiSessionMessage> candidateMessages = const <AiSessionMessage>[],
  }) {
    return isInputCacheModelSelectionLockedForSession(
      inputCacheEnabled: _settingsController.aiInputCacheEnabled,
      session: session,
      candidateMessages: candidateMessages,
    );
  }

  Future<bool> _resolveSessionInputCacheModelSelectionLocked(
    AiSession session,
  ) async {
    if (_isSessionInputCacheModelSelectionLocked(session)) return true;
    if (!_settingsController.aiInputCacheEnabled ||
        session.hasCompleteMessages) {
      return false;
    }
    final window = await _loadStoredMessageWindow(
      session,
      limit: _maxMessageWindowLimit,
      tail: true,
    );
    return _isSessionInputCacheModelSelectionLocked(
      session,
      candidateMessages: window.messages,
    );
  }

  String? _lastModelKeyForSession(
    AiSession session, {
    List<AiSessionMessage>? candidateMessages,
  }) {
    final fromCandidates =
        candidateMessages == null || candidateMessages.isEmpty
        ? null
        : _lastModelKeyFromMessages(candidateMessages);
    if (fromCandidates != null) return fromCandidates;

    if (session.messages.length <= _inMemoryMessageWindowDirectLimit) {
      final fromDisplay = _lastModelKeyFromMessages(session.displayMessages);
      if (fromDisplay != null) return fromDisplay;
    } else if (session.messages.isNotEmpty) {
      final start = math.max(
        0,
        session.messages.length - _sessionSummaryModelKeyScanLimit,
      );
      final fromTail = _lastModelKeyFromMessages(
        session.messages.sublist(start),
      );
      if (fromTail != null) return fromTail;
    }

    final context = _webContext(session.metadata);
    final requested = _allowedModelKeyFromValue(context['requested_model_key']);
    if (requested != null) return requested;
    final providerId = session.lastUsedModelId;
    final label = session.lastUsedModelLabel;
    if (providerId == null || label == null) return null;
    for (final model in _allowedModels()) {
      if (model.providerId != providerId) continue;
      if (model.modelId == label ||
          model.label == label ||
          model.key == label) {
        return model.key;
      }
    }
    return null;
  }

  String? _lastModelKeyFromMessages(List<AiSessionMessage> messages) {
    for (var index = messages.length - 1; index >= 0; index -= 1) {
      final message = messages[index];
      if (message.isDeleted) continue;
      final direct = _allowedModelKeyFromValue(message.metadata['model_key']);
      if (direct != null) return direct;
      final context = _webContext(message.metadata);
      final nested = _allowedModelKeyFromValue(context['model_key']);
      if (nested != null) return nested;
    }
    return null;
  }

  Map<String, Object?> _cacheHitStats(
    AiSession session, {
    required bool includeTrend,
  }) {
    final statistics = session.statistics;
    final stats = Map<String, Object?>.from(
      statistics.toJson(includeCacheHitTrendPoints: includeTrend),
    );
    if (statistics.cacheHitRatio != null) return stats;
    final cacheRead = statistics.cacheReadTokens ?? 0;
    final cacheWrite = statistics.cacheCreationTokens ?? 0;
    final prompt = statistics.totalPromptTokens ?? 0;
    final claudeStyle =
        _lastModelProtocolForSession(session)?.trim().toLowerCase() == 'claude';
    final denominator = claudeStyle
        ? prompt + cacheRead + cacheWrite
        : math.max(prompt, cacheRead + cacheWrite);
    if (cacheRead > 0 && denominator > 0) {
      stats['cache_hit_ratio'] = cacheRead / denominator;
    }
    return stats;
  }

  _WebSessionMessageWindow _messageWindowFromDisplayMessages(
    List<AiSessionMessage> displayMessages, {
    required int limit,
    int offset = 0,
    bool tail = false,
  }) {
    final safeLimit = math.min(_maxMessageWindowLimit, math.max(1, limit));
    final total = displayMessages.length;
    final resolvedOffset = tail
        ? math.max(0, total - safeLimit)
        : math.min(math.max(0, offset), total);
    final endOffset = math.min(total, resolvedOffset + safeLimit);
    final messages = displayMessages.sublist(resolvedOffset, endOffset);
    return (
      messages: messages,
      offset: resolvedOffset,
      limit: safeLimit,
      total: total,
      hasMore: tail
          ? resolvedOffset > 0
          : resolvedOffset + messages.length < total,
      hasOlder: resolvedOffset > 0,
      hasNewer: resolvedOffset + messages.length < total,
      window: tail ? 'tail' : 'offset',
    );
  }

  _WebSessionMessageWindow _emptyMessageWindow({
    required int total,
    required int limit,
    int offset = 0,
    bool tail = false,
  }) {
    final safeLimit = math.min(_maxMessageWindowLimit, math.max(1, limit));
    final safeTotal = math.max(0, total);
    final resolvedOffset = tail
        ? math.max(0, safeTotal - safeLimit)
        : math.min(math.max(0, offset), safeTotal);
    return (
      messages: const <AiSessionMessage>[],
      offset: resolvedOffset,
      limit: safeLimit,
      total: safeTotal,
      hasMore: tail ? resolvedOffset > 0 : resolvedOffset < safeTotal,
      hasOlder: resolvedOffset > 0,
      hasNewer: !tail && resolvedOffset < safeTotal,
      window: tail ? 'tail' : 'offset',
    );
  }

  List<AiSessionMessage> _mergeStoredAndLiveMessages(
    List<AiSessionMessage> storedMessages,
    List<AiSessionMessage> liveMessages,
  ) {
    if (storedMessages.isEmpty) return liveMessages;
    if (liveMessages.isEmpty) return storedMessages;
    final merged = storedMessages.toList(growable: true);
    final indexById = <String, int>{};
    for (var index = 0; index < merged.length; index += 1) {
      final id = merged[index].id.trim();
      if (id.isNotEmpty) indexById[id] = index;
    }
    for (final message in liveMessages) {
      final id = message.id.trim();
      final existingIndex = id.isEmpty ? null : indexById[id];
      if (existingIndex == null) {
        if (id.isNotEmpty) indexById[id] = merged.length;
        merged.add(message);
      } else {
        merged[existingIndex] = message;
      }
    }
    return merged;
  }

  Future<_WebSessionMessageWindow> _loadStoredMessageWindow(
    AiSession session, {
    required int limit,
    int offset = 0,
    bool tail = false,
  }) async {
    final safeLimit = math.min(_maxMessageWindowLimit, math.max(1, limit));
    try {
      final rawTotal = await _sessionController.store.countMessages(session.id);
      final inMemoryComplete =
          session.messages.isNotEmpty && session.messages.length >= rawTotal;
      if (inMemoryComplete &&
          session.messages.length <= _inMemoryMessageWindowDirectLimit) {
        return _messageWindowFromDisplayMessages(
          session.displayMessages,
          limit: safeLimit,
          offset: offset,
          tail: tail,
        );
      }

      final requestedOffset = math.min(math.max(0, offset), rawTotal);
      int scanLimitFor({
        required int multiplier,
        required int context,
        int? cap,
      }) {
        final desired = math.max(safeLimit, safeLimit * multiplier + context);
        return math.min(
          rawTotal,
          cap == null ? desired : math.min(cap, desired),
        );
      }

      int rawOffsetFor(int scanLimit, int context) {
        return tail
            ? math.max(0, rawTotal - scanLimit)
            : math.max(0, math.min(requestedOffset, rawTotal) - context);
      }

      Future<_WebSessionMessageWindow> loadBoundedWindow({
        required int scanLimit,
        required int context,
      }) async {
        final rawOffset = rawOffsetFor(scanLimit, context);
        final liveMessages = _liveMessagesForStoredWindowMerge(
          session: session,
          inMemoryComplete: inMemoryComplete,
          rawOffset: rawOffset,
          scanLimit: scanLimit,
          rawTotal: rawTotal,
        );
        final page = await _sessionController.store.loadMessages(
          session.id,
          limit: scanLimit,
          offset: rawOffset,
          deferTelemetryMetadata: true,
        );
        return _boundedStoredMessageWindow(
          session: session,
          storedMessages: page.messages,
          liveMessages: liveMessages,
          rawOffset: page.offset,
          rawTotal: rawTotal,
          safeLimit: safeLimit,
          requestedOffset: requestedOffset,
          tail: tail,
        );
      }

      final scanLimit = scanLimitFor(
        multiplier: _storedMessageWindowScanMultiplier,
        context: _storedMessageWindowScanContext,
      );
      var window = await loadBoundedWindow(
        scanLimit: scanLimit,
        context: _storedMessageWindowScanContext,
      );
      final expandedScanLimit = scanLimitFor(
        multiplier: _storedMessageWindowExpandedScanMultiplier,
        context: _storedMessageWindowExpandedScanContext,
        cap: _storedMessageWindowExpandedScanLimit,
      );
      if (window.messages.length < safeLimit && expandedScanLimit > scanLimit) {
        window = await loadBoundedWindow(
          scanLimit: expandedScanLimit,
          context: _storedMessageWindowExpandedScanContext,
        );
      }
      return window;
    } catch (error, stack) {
      silentLog('web_message_platform_service', '加载已存消息窗口', error, stack);
      final cheapDisplayMessages = _displayMessagesIfCheap(session);
      if (cheapDisplayMessages.isNotEmpty) {
        return _messageWindowFromDisplayMessages(
          cheapDisplayMessages,
          limit: safeLimit,
          offset: offset,
          tail: tail,
        );
      }
      return _emptyMessageWindow(
        total: math.max(
          session.messageTotalCount,
          math.max(
            session.statistics.totalMessageCount,
            session.messages.length,
          ),
        ),
        limit: safeLimit,
        offset: offset,
        tail: tail,
      );
    }
  }

  Future<_WebSessionMessageWindow> _loadTranscriptRevealWindow(
    AiSession session, {
    required ({String messageId, int offset}) anchor,
    required int limit,
  }) async {
    if (session.hasCompleteMessages &&
        session.messages.length <= _inMemoryMessageWindowDirectLimit) {
      final displayOffset = session.displayMessages.indexWhere(
        (message) => message.id == anchor.messageId,
      );
      if (displayOffset >= 0) {
        return _messageWindowFromDisplayMessages(
          session.displayMessages,
          limit: limit,
          offset: math.max(0, displayOffset - 8),
        );
      }
    }
    return _loadStoredMessageWindow(
      session,
      limit: limit,
      offset: math.max(0, anchor.offset - 8),
    );
  }

  Future<({String messageId, int offset})?> _resolveTranscriptRevealAnchor(
    AiSession session,
    String messageId,
  ) async {
    final storedOffset = await _sessionController.store.messageOffset(
      session.id,
      messageId,
    );
    if (storedOffset != null) {
      final contextOffset = math.max(
        0,
        storedOffset - _maxMessageWindowLimit ~/ 2,
      );
      final page = await _sessionController.store.loadMessages(
        session.id,
        limit: _maxMessageWindowLimit,
        offset: contextOffset,
        deferTelemetryMetadata: true,
      );
      final scopedSession = session.copyWith(
        messages: page.messages,
        messageLoadState: page.offset == 0 && !page.hasMore
            ? AiSessionMessageLoadState.complete
            : AiSessionMessageLoadState.windowed,
        messageWindowStartIndex: page.offset,
        messageTotalCount: page.totalCount,
      );
      final anchor = scopedSession.transcriptAnchorForRoundStarter(messageId);
      if (anchor == null) return null;
      final localOffset = page.messages.indexWhere(
        (candidate) => candidate.id == anchor.id,
      );
      if (localOffset < 0) return null;
      return (messageId: anchor.id, offset: page.offset + localOffset);
    }

    final anchor = session.transcriptAnchorForRoundStarter(messageId);
    if (anchor == null) return null;
    final localOffset = session.messages.indexWhere(
      (candidate) => candidate.id == anchor.id,
    );
    if (localOffset < 0) return null;
    final offset =
        session.messageLoadState == AiSessionMessageLoadState.windowed
        ? session.messageWindowStartIndex + localOffset
        : localOffset;
    return (messageId: anchor.id, offset: offset);
  }

  _WebSessionMessageWindow _boundedStoredMessageWindow({
    required AiSession session,
    required List<AiSessionMessage> storedMessages,
    required List<AiSessionMessage> liveMessages,
    required int rawOffset,
    required int rawTotal,
    required int safeLimit,
    required int requestedOffset,
    required bool tail,
  }) {
    final rawIndexByMessageId = <String, int>{};
    for (var index = 0; index < storedMessages.length; index += 1) {
      final id = storedMessages[index].id.trim();
      if (id.isNotEmpty) {
        rawIndexByMessageId[id] = rawOffset + index;
      }
    }
    final mergedMessages = _mergeStoredAndLiveMessages(
      storedMessages,
      liveMessages,
    );
    var syntheticRawIndex = math.max(
      rawTotal,
      rawOffset + storedMessages.length,
    );
    for (final message in mergedMessages) {
      final id = message.id.trim();
      if (id.isNotEmpty && !rawIndexByMessageId.containsKey(id)) {
        rawIndexByMessageId[id] = syntheticRawIndex;
        syntheticRawIndex += 1;
      }
    }

    final scannedAllStoredMessages =
        rawOffset == 0 && storedMessages.length >= rawTotal;
    final displayMessages = session
        .copyWith(
          messages: mergedMessages,
          messageLoadState: scannedAllStoredMessages
              ? AiSessionMessageLoadState.complete
              : AiSessionMessageLoadState.windowed,
          messageWindowStartIndex: scannedAllStoredMessages ? 0 : rawOffset,
          messageTotalCount: rawTotal,
        )
        .displayMessages;
    final List<AiSessionMessage> selectedMessages;
    if (displayMessages.isEmpty) {
      selectedMessages = const <AiSessionMessage>[];
    } else if (tail) {
      final startIndex = math.max(0, displayMessages.length - safeLimit);
      selectedMessages = displayMessages.sublist(startIndex);
    } else {
      var startIndex = displayMessages.indexWhere((message) {
        return (rawIndexByMessageId[message.id.trim()] ?? rawTotal) >=
            requestedOffset;
      });
      if (startIndex < 0) {
        startIndex = displayMessages.length;
      }
      final endIndex = math.min(displayMessages.length, startIndex + safeLimit);
      selectedMessages = displayMessages.sublist(startIndex, endIndex);
    }

    final total = math.max(
      rawTotal,
      math.max(session.statistics.totalMessageCount, syntheticRawIndex),
    );
    final fallbackOffset = tail
        ? math.max(0, rawTotal - safeLimit)
        : math.min(math.max(0, requestedOffset), total);
    final firstRawIndex = selectedMessages.isEmpty
        ? fallbackOffset
        : rawIndexByMessageId[selectedMessages.first.id.trim()] ??
              fallbackOffset;
    final lastRawIndex = selectedMessages.isEmpty
        ? firstRawIndex - 1
        : rawIndexByMessageId[selectedMessages.last.id.trim()] ??
              firstRawIndex + selectedMessages.length - 1;
    final hasNewer = selectedMessages.isNotEmpty && lastRawIndex + 1 < total;
    return (
      messages: selectedMessages,
      offset: math.max(0, math.min(firstRawIndex, total)),
      limit: safeLimit,
      total: total,
      hasMore: tail ? firstRawIndex > 0 : hasNewer,
      hasOlder: firstRawIndex > 0,
      hasNewer: hasNewer,
      window: tail ? 'tail' : 'offset',
    );
  }

  List<AiSessionMessage> _liveMessagesForStoredWindowMerge({
    required AiSession session,
    required bool inMemoryComplete,
    required int rawOffset,
    required int scanLimit,
    required int rawTotal,
  }) {
    final liveMessages = session.messages;
    if (liveMessages.isEmpty) return const <AiSessionMessage>[];
    if (!inMemoryComplete ||
        liveMessages.length <= _inMemoryMessageWindowDirectLimit) {
      return liveMessages;
    }

    final storedStart = math.max(0, math.min(rawOffset, liveMessages.length));
    final storedEnd = math.max(
      storedStart,
      math.min(rawOffset + scanLimit, math.min(rawTotal, liveMessages.length)),
    );
    final unsavedStart = math.max(0, math.min(rawTotal, liveMessages.length));
    final hasStoredOverlap = storedEnd > storedStart;
    final hasUnsavedTail = unsavedStart < liveMessages.length;
    final boundedUnsavedStart = hasUnsavedTail
        ? math.max(
            unsavedStart,
            liveMessages.length - _inMemoryMessageWindowDirectLimit,
          )
        : unsavedStart;
    if (!hasStoredOverlap && !hasUnsavedTail) {
      return const <AiSessionMessage>[];
    }
    if (!hasUnsavedTail) {
      return liveMessages.sublist(storedStart, storedEnd);
    }
    if (!hasStoredOverlap) {
      return liveMessages.sublist(boundedUnsavedStart);
    }
    return <AiSessionMessage>[
      ...liveMessages.sublist(storedStart, storedEnd),
      ...liveMessages.sublist(boundedUnsavedStart),
    ];
  }

  Future<Map<String, Object?>> _sessionSummaryWithStoredMessages(
    AiSession session, {
    bool includeDetails = false,
  }) async {
    final window = await _loadStoredMessageWindow(
      session,
      limit: _sessionSummaryMessageWindowSize,
      tail: true,
    );
    final liveDisplayMessages = _displayMessagesIfCheap(session);
    final lastMessage = liveDisplayMessages.isNotEmpty
        ? liveDisplayMessages.last
        : (window.messages.isEmpty ? null : window.messages.last);
    return _sessionSummary(
      session,
      includeDetails: includeDetails,
      messageCountOverride: math.max(window.total, liveDisplayMessages.length),
      lastMessageOverride: lastMessage,
      lastModelKeyCandidates: window.messages.isNotEmpty
          ? window.messages
          : liveDisplayMessages,
    );
  }

  Future<Map<String, Object?>> _sessionSummaryWithStoredMessageCount(
    AiSession session, {
    bool includeDetails = false,
    bool includeCacheHitTrend = false,
  }) async {
    var total = session.statistics.totalMessageCount;
    try {
      total = math.max(
        total,
        await _sessionController.store.countMessages(session.id),
      );
    } catch (error, stack) {
      silentLog('web_message_platform_service', '统计已存消息', error, stack);
    }
    final liveDisplayMessages = _displayMessagesIfCheap(session);
    return _sessionSummary(
      session,
      includeDetails: includeDetails,
      includeCacheHitTrend: includeCacheHitTrend,
      messageCountOverride: math.max(total, liveDisplayMessages.length),
      lastMessageOverride: liveDisplayMessages.isEmpty
          ? null
          : liveDisplayMessages.last,
      lastModelKeyCandidates: liveDisplayMessages,
    );
  }

  List<AiSessionMessage> _displayMessagesIfCheap(AiSession session) {
    if (session.messages.isEmpty ||
        session.messages.length > _inMemoryMessageWindowDirectLimit) {
      return const <AiSessionMessage>[];
    }
    return session.displayMessages;
  }

  Map<String, Object?> _sessionSummary(
    AiSession session, {
    bool includeDetails = false,
    bool includeCacheHitTrend = false,
    int? messageCountOverride,
    AiSessionMessage? lastMessageOverride,
    List<AiSessionMessage>? lastModelKeyCandidates,
  }) {
    final context = _webContext(session.metadata);
    final canDeriveDisplayMessages =
        session.messages.length <= _inMemoryMessageWindowDirectLimit;
    final needsDisplayMessages =
        canDeriveDisplayMessages &&
        (messageCountOverride == null || lastMessageOverride == null);
    final displayMessages = needsDisplayMessages
        ? session.displayMessages
        : const <AiSessionMessage>[];
    final last =
        lastMessageOverride ??
        (displayMessages.isEmpty ? null : displayMessages.last);
    final messageCount =
        messageCountOverride ??
        (needsDisplayMessages
            ? displayMessages.length
            : session.statistics.totalMessageCount);
    final lastModelKey = _lastModelKeyForSession(
      session,
      candidateMessages: lastModelKeyCandidates,
    );
    final latestCompressionPointForDetails = includeDetails
        ? _latestCompressionPointIfCheap(session)
        : null;
    final summary = <String, Object?>{
      'id': session.id,
      'title': session.title,
      'template_id': session.templateId,
      'template_name': session.templateName,
      'template_internal_version': session.templateInternalVersion,
      'created_at': session.createdAt.toUtc().toIso8601String(),
      'updated_at': session.updatedAt.toUtc().toIso8601String(),
      'mode': session.mode.storageValue,
      'full_access_permission': session.fullAccessPermission,
      'last_used_model_id': session.lastUsedModelId,
      'last_used_model_label': session.lastUsedModelLabel,
      'last_used_model_protocol': _lastModelProtocolForSession(session),
      'is_title_manually_edited': session.isTitleManuallyEdited,
      'auto_title_acquired': session.autoTitleAcquired,
      'auto_title_retry_count': session.autoTitleRetryCount,
      'auto_title_generated_at': session.autoTitleGeneratedAt
          ?.toUtc()
          .toIso8601String(),
      'auto_title_source_message_id': session.autoTitleSourceMessageId,
      'latest_compression_checkpoint_message_id':
          session.latestCompressionCheckpointMessageId,
      'latest_compression_at': session.latestCompressionAt
          ?.toUtc()
          .toIso8601String(),
      'last_model_key': lastModelKey,
      'input_cache_model_selection_locked':
          _isSessionInputCacheModelSelectionLocked(
            session,
            candidateMessages:
                lastModelKeyCandidates ?? const <AiSessionMessage>[],
          ),
      'message_count': messageCount,
      'statistics': _cacheHitStats(session, includeTrend: includeCacheHitTrend),
      'total_tokens': session.statistics.totalTokens,
      'total_prompt_tokens': session.statistics.totalPromptTokens,
      'total_completion_tokens': session.statistics.totalCompletionTokens,
      'tool_message_count': session.statistics.toolMessageCount,
      'compression_point_count': session.statistics.compressionPointCount,
      'last_message_preview': last == null
          ? ''
          : clipText(last.content.replaceAll('\n', ' '), 160),
      'last_message_kind': last?.kind.storageValue,
      'send_phase': _sessionController.sendPhaseForSession(session.id).name,
      'goal_state': session.goalState.toJson(),
      'source': context['login_source'],
      'device_id': context['device_id'],
      'metadata': includeDetails ? session.metadata : context,
      if (includeDetails) 'web_context': context,
      // Plan-mode 字段：Web 端 PlanTimeline 直接消费这些字段渲染时间线
      // + 「批准计划」按钮。todo_items 走 [{id,content,status}] 三元组，
      // status 取值与 App 端一致：completed / in_progress / failed /
      // blocked / cancelled / pending。
      'awaiting_plan_approval': session.awaitingPlanApproval,
      'pending_plan': session.pendingPlan,
      'pending_plan_allowed_prompts': session.pendingPlanAllowedPrompts
          .map((item) => item.toJson())
          .toList(growable: false),
      'todo_items': session.todoItems
          .map((item) => item.toJson())
          .toList(growable: false),
    };
    if (!includeDetails) return summary;
    summary.addAll(<String, Object?>{
      'environment': session.environment.toJson(),
      'last_prompt_metadata': session.lastPromptMetadata,
      'plan_history': session.planHistory
          .map((item) => item.toJson())
          .toList(growable: false),
      'recent_errors': session.recentErrors
          .where((error) => error.stage != 'title_generation')
          .map((item) => item.toJson())
          .toList(growable: false),
      'latest_compression_point': latestCompressionPointForDetails == null
          ? null
          : _messageJson(latestCompressionPointForDetails),
    });
    return summary;
  }

  AiSessionMessage? _latestCompressionPointIfCheap(AiSession session) {
    if (session.messages.isEmpty ||
        session.messages.length > _inMemoryMessageWindowDirectLimit) {
      return null;
    }
    return session.latestCompressionPoint;
  }

  Map<String, Object?> _messageJson(
    AiSessionMessage message, {
    bool includeTelemetryMetadata = false,
  }) {
    final usage = message.usage;
    final metadata = includeTelemetryMetadata
        ? aiSessionMessageMetadataWithoutDeferredTelemetryMarker(
            message.metadata,
          )
        : aiSessionMessageTranscriptMetadata(message.metadata);
    return <String, Object?>{
      'id': message.id,
      'kind': message.kind.storageValue,
      'role': message.role.storageValue,
      'content': message.content,
      'created_at': message.createdAt.toUtc().toIso8601String(),
      'character_count': message.characterCount,
      'model_id': message.modelId,
      'model_label': message.modelLabel,
      'feedback': message.feedback?.storageValue,
      if (usage != null) 'usage': usage.toJson(),
      ...message.derivedConversationJson(),
      'metadata': metadata,
    };
  }

  String _messagePayloadWindowSignature(List<Object?> messages) {
    if (messages.isEmpty) {
      return '0';
    }

    String itemSignature(Object? value) {
      final Map<String, Object?>? message = switch (value) {
        final Map<String, Object?> typed => typed,
        final Map raw => stringKeyedMapFromValue(raw),
        _ => null,
      };
      if (message == null) {
        return '?';
      }
      final content = message['content'];
      final contentText = content is String ? content : '';
      final contentSignature = compactTextSignature(
        contentText,
        emptySignature: '0::',
      );
      return '${message['id']}:${message['role']}:${message['kind']}:$contentSignature:${message['character_count'] ?? 0}';
    }

    final first = itemSignature(messages.first);
    final previousTail = messages.length > 1
        ? itemSignature(messages[messages.length - 2])
        : '';
    final tail = itemSignature(messages.last);
    return '${messages.length}|$first|$previousTail|$tail';
  }

  String _resolveEffectiveBrightness() {
    final themeMode = _settingsController.themeMode;
    if (themeMode == ThemeMode.light) return 'light';
    if (themeMode == ThemeMode.dark) return 'dark';
    // Web 平台无法可靠读取系统亮度偏好，默认回落 dark。
    return 'dark';
  }

  Future<AiSessionRuntimeContext> _buildRuntimeContext({
    required String templateId,
    Set<String> skippedInstructionIds = const <String>{},
  }) async {
    await _mcpController.ensureRuntimeToolCatalogs();
    final memoryEnabled = _settingsController.memoryEnabled;
    final memoryEntries = memoryEnabled
        ? await _memoryController.trustedEntriesSnapshot() ??
              const <UserMemoryEntry>[]
        : const <UserMemoryEntry>[];
    final mcpToolCatalogsByServerName = <String, McpToolCatalog>{
      for (final server in _mcpController.runtimeServers)
        server.name: _mcpController.toolCatalogFor(server.name),
    };
    // 走与桌面端同一份设置映射：此前这里自己列了 40 项、漏掉 45 项，同一个
    // 会话从手机端发起时超时、工具轮次上限、允许命令规则、沙箱设置、附件上限
    // 全都退回默认值。技能 / MCP / 指令三项仍按网关的放行清单过滤后传入。
    return buildAiSessionRuntimeContext(
      settingsController: _settingsController,
      appInfo: _appInfo,
      appThemeBrightness: _resolveEffectiveBrightness(),
      localNow: DateTime.now().toLocal(),
      workingDirectory: OpenHandPaths.applicationDirectoryPath(),
      memoryEntries: memoryEntries,
      allowCommandRules: _settingsController.aiAllowCommandRules,
      availableSkills: webGatewayIsDenyAllSelection(_config.allowedSkillNames)
          ? const []
          : _config.allowedSkillNames.isEmpty
          ? _skillsController.skills
          : _skillsController.skills
                .where(
                  (skill) => _config.allowedSkillNames.contains(skill.name),
                )
                .toList(growable: false),
      availableMcpServers:
          webGatewayIsDenyAllSelection(_config.allowedMcpServerNames)
          ? const []
          : _config.allowedMcpServerNames.isEmpty
          ? _mcpController.runtimeServers
          : _mcpController.runtimeServers
                .where(
                  (server) =>
                      _config.allowedMcpServerNames.contains(server.name),
                )
                .toList(growable: false),
      mcpToolCatalogsByServerName: mcpToolCatalogsByServerName,
      builtinToolConfigs: _effectiveBuiltinToolConfigsForWeb(),
      userInstructions:
          webGatewayIsDenyAllSelection(_config.allowedInstructionIds)
          ? const []
          : _config.allowedInstructionIds.isEmpty
          ? _instructionsController.entries
          : _instructionsController.entries
                .where(
                  (entry) => _config.allowedInstructionIds.contains(entry.id),
                )
                .toList(growable: false),
      skippedInstructionIds: skippedInstructionIds,
      templateId: templateId,
      toolExecutionMetadata: _webAgentToolExecutionMetadata(),
    );
  }

  List<AiBuiltinToolConfig> _effectiveBuiltinToolConfigsForWeb() {
    final configured = _settingsController.builtinToolConfigs;
    final source = configured.isEmpty
        ? AiBuiltinToolConfig.defaults()
        : configured;
    if (webGatewayIsDenyAllSelection(_config.allowedBuiltinToolNames)) {
      return _disabledBuiltinToolConfigs(source);
    }

    final allowedNames = _config.allowedBuiltinToolNames;
    final selected = allowedNames.isEmpty
        ? source
        : source
              .where((tool) => allowedNames.contains(tool.effectiveName))
              .toList(growable: false);
    var effective = selected.toList(growable: false);
    if (!_config.knowledgeBaseEnabled) {
      effective = _withBuiltinToolKindsDisabled(
        effective,
        _knowledgeBaseBuiltinToolKinds,
      );
    }
    if (!_config.agentsEnabled) {
      effective = _withBuiltinToolKindsDisabled(
        effective,
        _agentBuiltinToolKinds,
      );
    }
    return effective;
  }

  Map<String, Object?> _webAgentToolExecutionMetadata() {
    final exposed = _exposedWebAgents();
    return <String, Object?>{
      aiAgentToolAccessEnabledMetadataKey: _config.agentsEnabled,
      aiAgentToolAllowedAgentIdsMetadataKey: exposed
          .map((agent) => agent.id)
          .toList(growable: false),
      aiAgentToolAccessSourceMetadataKey: 'web_gateway',
    };
  }

  List<AgentProfile> _availableWebAgents() {
    return _agentsController.enabledAgents;
  }

  List<AgentProfile> _exposedWebAgents() {
    if (!_config.agentsEnabled ||
        webGatewayIsDenyAllSelection(_config.allowedAgentIds)) {
      return const <AgentProfile>[];
    }
    final available = _availableWebAgents();
    if (_config.allowedAgentIds.isEmpty) return available;
    final allowed = _config.allowedAgentIds.toSet();
    return available
        .where((agent) => allowed.contains(agent.id))
        .toList(growable: false);
  }

  Map<String, Object?> _webAgentSummaryJson() {
    final available = _availableWebAgents();
    final exposed = _exposedWebAgents();
    return <String, Object?>{
      'enabled': _config.agentsEnabled,
      'available_count': available.length,
      'exposed_count': exposed.length,
      'allowed_agent_ids': _config.allowedAgentIds,
      'exposed_agent_ids': exposed
          .map((agent) => agent.id)
          .toList(growable: false),
      'items': exposed
          .map(
            (agent) => <String, Object?>{
              'id': agent.id,
              'name': agent.name,
              'position': agent.position,
              'department': agent.department,
            },
          )
          .toList(growable: false),
    };
  }

  List<AiBuiltinToolConfig> _disabledBuiltinToolConfigs(
    Iterable<AiBuiltinToolConfig> configs,
  ) {
    return configs
        .map((config) => config.copyWith(enabled: false))
        .toList(growable: false);
  }

  List<AiBuiltinToolConfig> _withBuiltinToolKindsDisabled(
    Iterable<AiBuiltinToolConfig> configs,
    Set<AiBuiltinToolKind> disabledKinds,
  ) {
    final result = <AiBuiltinToolConfig>[];
    final patchedKinds = <AiBuiltinToolKind>{};
    for (final config in configs) {
      if (disabledKinds.contains(config.kind)) {
        result.add(config.copyWith(enabled: false));
        patchedKinds.add(config.kind);
      } else {
        result.add(config);
      }
    }
    for (final kind in disabledKinds) {
      if (patchedKinds.contains(kind)) continue;
      result.add(_defaultDisabledBuiltinToolConfig(kind));
    }
    return result;
  }

  AiBuiltinToolConfig _defaultDisabledBuiltinToolConfig(
    AiBuiltinToolKind kind,
  ) {
    return AiBuiltinToolConfig.defaults()
        .firstWhere((config) => config.kind == kind)
        .copyWith(enabled: false);
  }

  List<AiThreadTemplate> _allowedTemplates() {
    if (webGatewayIsDenyAllSelection(_config.allowedTemplateIds)) {
      return const [];
    }
    final platformTemplates = _sessionController.availableTemplates;
    if (_config.allowedTemplateIds.isEmpty) return platformTemplates;
    return platformTemplates
        .where((template) => _config.allowedTemplateIds.contains(template.id))
        .toList(growable: false);
  }

  bool _templateAllowed(String templateId) {
    if (webGatewayIsDenyAllSelection(_config.allowedTemplateIds)) return false;
    final supported = _sessionController.availableTemplates.any(
      (template) => template.id == templateId,
    );
    if (!supported) return false;
    return _config.allowedTemplateIds.isEmpty ||
        _config.allowedTemplateIds.contains(templateId);
  }

  String? _activeModelKey() {
    if (webGatewayIsDenyAllSelection(_config.allowedModelKeys)) return null;
    final selected = _settingsController.selectedAiModel;
    if (selected == null) return null;
    final key = _modelKey(selected.id, selected.modelId);
    if (_config.allowedModelKeys.isNotEmpty &&
        !_config.allowedModelKeys.contains(key)) {
      return null;
    }
    return key;
  }

  String _translationModelSettingsFingerprint() {
    final allowedKeys = _allowedModels()
        .map((model) => model.key)
        .toList(growable: false);
    return stableJsonSha256(<String, Object?>{
      'active_model_key': _activeModelKey(),
      'allowed_model_keys': allowedKeys,
      'model_configs': _settingsController.aiModels
          .map((model) => model.toJson())
          .toList(growable: false),
    });
  }

  List<_AllowedWebModel> _allowedModels() {
    if (webGatewayIsDenyAllSelection(_config.allowedModelKeys)) {
      return const [];
    }
    final result = <_AllowedWebModel>[];
    for (final provider in _settingsController.aiModels) {
      final providerDefaultTitleModelId = provider.defaultTitleModelId.trim();
      final providerDefaultTitleModelKey =
          providerDefaultTitleModelId.isNotEmpty &&
              provider.allModelIds.contains(providerDefaultTitleModelId)
          ? _modelKey(provider.id, providerDefaultTitleModelId)
          : null;
      final legacyGlobalDefaultTitleModelId = provider.isGlobalDefaultTitleModel
          ? (providerDefaultTitleModelId.isNotEmpty
                ? providerDefaultTitleModelId
                : provider.modelId.trim())
          : '';
      for (final modelId in provider.allModelIds) {
        final key = _modelKey(provider.id, modelId);
        if (_config.allowedModelKeys.isNotEmpty &&
            !_config.allowedModelKeys.contains(key)) {
          continue;
        }
        final resolved = provider.copyWith(modelId: modelId);
        final profile = provider.profileFor(modelId);
        final attachmentCapabilities = resolveAiAttachmentInputCapabilities(
          resolved,
        );
        result.add(
          _AllowedWebModel(
            key: key,
            providerId: provider.id,
            providerLabel: provider.providerLabel,
            protocolLabel: provider.protocolType.storageValue,
            modelId: modelId,
            label: '${provider.providerLabel} / $modelId',
            supportsAttachments: attachmentCapabilities.supportsAny,
            supportsImageInput: attachmentCapabilities.supportsImageInput,
            supportsVideoInput: attachmentCapabilities.supportsVideoInput,
            supportsAudioInput: attachmentCapabilities.supportsAudioInput,
            supportsFileInput: attachmentCapabilities.supportsFileInput,
            attachmentExtensions: aiAttachmentPickerExtensionsForCapabilities(
              attachmentCapabilities,
            ),
            supportsImageGeneration:
                AiImageGenerationService.supportsImageGenerationForModel(
                  resolved,
                ),
            supportsVideoGeneration:
                AiImageGenerationService.supportsVideoGenerationForModel(
                  resolved,
                ),
            supportsAudioGeneration:
                AiImageGenerationService.supportsAudioGenerationForModel(
                  resolved,
                ),
            supportsTextTitleGeneration:
                AiTitleModelResolver.supportsTextTitleGeneration(resolved),
            supportsEmbeddings: profile.supportsEmbeddings,
            supportsRerank: profile.supportsRerank,
            providerDefaultTitleModelKey: providerDefaultTitleModelKey,
            isGlobalDefaultTitleModel:
                profile.isGlobalDefaultTitleModel ||
                (legacyGlobalDefaultTitleModelId.isNotEmpty &&
                    modelId == legacyGlobalDefaultTitleModelId),
            reasoningEffortControlEnabled:
                resolved.resolvedReasoningEffortControlEnabled,
            reasoningEffort: resolved.resolvedReasoningEffort,
            reasoningEffortOptions: resolved.resolvedReasoningEffortOptions,
          ),
        );
      }
    }
    return result;
  }

  AiModelConfig? _resolveModel(String key) {
    if (webGatewayIsDenyAllSelection(_config.allowedModelKeys)) return null;
    final requested = key.trim();
    if (requested.isNotEmpty &&
        (_config.allowedModelKeys.isEmpty ||
            _config.allowedModelKeys.contains(requested))) {
      final parsed = _parseModelKey(requested);
      if (parsed != null) {
        for (final provider in _settingsController.aiModels) {
          if (provider.id == parsed.providerId &&
              provider.allModelIds.contains(parsed.modelId)) {
            return provider.copyWith(modelId: parsed.modelId);
          }
        }
      }
    }
    final selected = _settingsController.selectedAiModel;
    if (selected != null) {
      final selectedKey = _modelKey(selected.id, selected.modelId);
      if (_config.allowedModelKeys.isEmpty ||
          _config.allowedModelKeys.contains(selectedKey)) {
        return selected;
      }
    }
    for (final model in _allowedModels()) {
      final parsed = _parseModelKey(model.key);
      if (parsed == null) continue;
      for (final provider in _settingsController.aiModels) {
        if (provider.id == parsed.providerId) {
          return provider.copyWith(modelId: parsed.modelId);
        }
      }
    }
    return null;
  }

  AiModelConfig? _resolveTitleGenerationModelForSession(AiSession session) {
    AiModelConfig? currentModel;
    final lastModelKey = _lastModelKeyForSession(session);
    if (lastModelKey != null && lastModelKey.trim().isNotEmpty) {
      currentModel = _resolveModel(lastModelKey);
    }
    currentModel ??= _settingsController.selectedAiModel;
    return AiTitleModelResolver.resolveDefault(
      models: _settingsController.aiModels,
      currentModel: currentModel,
    );
  }

  AiCreationRequest _creationRequestFor(
    WebGatewayConversationMode mode, [
    Map<String, Object?>? rawOptions,
  ]) {
    final options = rawOptions != null
        ? AiCreationOptions.fromMetadata(rawOptions)
        : AiCreationOptions.empty;
    return switch (mode) {
      WebGatewayConversationMode.image => AiCreationRequest(
        mode: AiCreationMode.image,
        options: options.aspectRatio != null || options.count > 1
            ? options
            : const AiCreationOptions(size: '1024x1024', aspectRatio: '1:1'),
      ),
      WebGatewayConversationMode.video => AiCreationRequest(
        mode: AiCreationMode.video,
        options: options,
      ),
      WebGatewayConversationMode.audio => AiCreationRequest(
        mode: AiCreationMode.audio,
        options: options,
      ),
      WebGatewayConversationMode.deepResearch => const AiCreationRequest(
        mode: AiCreationMode.deepResearch,
      ),
      WebGatewayConversationMode.normal => AiCreationRequest.none,
    };
  }

  bool _modelSupportsConversationMode(
    AiModelConfig model,
    WebGatewayConversationMode mode,
  ) {
    return switch (mode) {
      WebGatewayConversationMode.normal ||
      WebGatewayConversationMode.deepResearch => true,
      WebGatewayConversationMode.image =>
        AiImageGenerationService.supportsImageGenerationForModel(model),
      WebGatewayConversationMode.video =>
        AiImageGenerationService.supportsVideoGenerationForModel(model),
      WebGatewayConversationMode.audio =>
        AiImageGenerationService.supportsAudioGenerationForModel(model),
    };
  }

  Future<List<String>> _materializeAttachments(
    String sessionId,
    Object? raw,
  ) async {
    if (raw == null) return const <String>[];
    if (raw is! List) {
      throw const _WebGatewayRequestException(
        HttpStatus.badRequest,
        'invalid_attachments',
      );
    }
    if (raw.isEmpty) return const <String>[];
    if (raw.length > aiMessageAttachmentLimit) {
      throw const _WebGatewayRequestException(
        HttpStatus.badRequest,
        'too_many_attachments',
      );
    }
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty ||
        p.basename(normalizedSessionId) != normalizedSessionId ||
        normalizedSessionId == '.' ||
        normalizedSessionId == '..') {
      throw const _WebGatewayRequestException(
        HttpStatus.badRequest,
        'invalid_session_id',
      );
    }
    final output = <String>[];
    final dir = Directory(
      p.join(_uploadCacheDirectoryPath, normalizedSessionId),
    );
    var totalBytes = 0;
    try {
      for (var index = 0; index < raw.length; index++) {
        final item = raw[index];
        if (item is! Map) {
          throw const _WebGatewayRequestException(
            HttpStatus.badRequest,
            'invalid_attachment_payload',
          );
        }
        final map = stringKeyedMapFromValue(item);
        final name = _safeFileName(_string(map['name'], 'attachment.bin'));
        final data = _string(map['data_base64'], '').trim();
        if (data.isEmpty) {
          throw const _WebGatewayRequestException(
            HttpStatus.badRequest,
            'invalid_attachment_payload',
          );
        }
        late final Uint8List bytes;
        try {
          bytes = decodeBase64Bounded(
            data,
            maxDecodedBytes: kWebGatewayAttachmentMaxFileBytes,
          );
        } on BoundedBase64SizeException {
          throw const _WebGatewayRequestException(
            HttpStatus.requestEntityTooLarge,
            'attachment_too_large',
          );
        } on BoundedBase64FormatException {
          throw const _WebGatewayRequestException(
            HttpStatus.badRequest,
            'invalid_attachment_payload',
          );
        }
        totalBytes += bytes.length;
        if (totalBytes > kWebGatewayAttachmentMaxTotalBytes) {
          throw const _WebGatewayRequestException(
            HttpStatus.requestEntityTooLarge,
            'attachments_too_large',
          );
        }
        if (output.isEmpty) {
          await dir
              .create(recursive: true)
              .timeout(_uploadCacheOperationTimeout);
        }
        final file = File(
          p.join(
            dir.path,
            '${DateTime.now().microsecondsSinceEpoch}-$index-$name',
          ),
        );
        await writeBytesFileAtomically(file, bytes);
        output.add(file.path);
      }
      return output;
    } catch (_) {
      await _deleteMaterializedAttachments(output);
      rethrow;
    }
  }

  Future<void> _deleteMaterializedAttachments(List<String> paths) async {
    for (final path in paths) {
      try {
        final trimmed = path.trim();
        if (trimmed.isEmpty) continue;
        final file = File(trimmed);
        if (await file.exists().timeout(_uploadCacheOperationTimeout)) {
          await file.delete().timeout(_uploadCacheOperationTimeout);
        }
      } catch (error, stack) {
        silentLog('web_message_platform_service', '删除已落盘附件', error, stack);
      }
    }
  }

  String get _uploadCacheDirectoryPath =>
      p.join(_cacheDirectoryPath, 'message_gateway', 'uploads');

  Future<_CleanupStats> _cleanupUploadCache({required bool expiredOnly}) async {
    final root = Directory(_uploadCacheDirectoryPath);
    if (!await root.exists().timeout(_uploadCacheOperationTimeout)) {
      return const _CleanupStats();
    }
    if (!expiredOnly) {
      final usage = await measureDirectoryBounded(
        root,
        maxEntries: _maxUploadCacheScanEntries,
        totalTimeout: _uploadCacheScanTotalTimeout,
      );
      final stats = _CleanupStats(
        deletedFiles: usage.fileCount,
        deletedDirectories: usage.directoryCount,
        bytesFreed: usage.totalBytes,
      );
      if (usage.truncated) {
        _logUploadCacheScanLimit('全量清理前统计');
      }
      await deletePathBounded(
        p.absolute(root.path),
        policy: _uploadCacheDeletePolicy,
        allowedRoot: p.absolute(_cacheDirectoryPath),
      );
      return stats.copyWith(deletedDirectories: stats.deletedDirectories + 1);
    }
    final cutoff = DateTime.now().subtract(
      Duration(days: _config.uploadCacheRetentionDays),
    );
    var stats = const _CleanupStats();
    final parentDirectories = <String>{};
    final scan = await _visitUploadCacheFiles(root, (entity) async {
      try {
        final stat = await entity.stat().timeout(_uploadCacheOperationTimeout);
        if (stat.modified.isAfter(cutoff)) return;
        await entity.delete().timeout(_uploadCacheOperationTimeout);
        stats += _CleanupStats(deletedFiles: 1, bytesFreed: stat.size);
        _rememberUploadParent(parentDirectories, entity.parent.path);
      } catch (error, stack) {
        silentLog('web_message_platform_service', '清理上传缓存', error, stack);
      }
    });
    if (!scan.complete) {
      _logUploadCacheScanLimit('删除过期上传文件', scannedEntries: scan.scannedEntries);
    }
    stats += await _deleteEmptyUploadDirectories(root, parentDirectories);
    return stats + await _enforceUploadCacheMaxBytes();
  }

  Future<_CleanupStats> _enforceUploadCacheMaxBytes() async {
    final root = Directory(_uploadCacheDirectoryPath);
    if (!await root.exists().timeout(_uploadCacheOperationTimeout)) {
      return const _CleanupStats();
    }
    var candidates = <({File file, int size, DateTime modified})>[];
    var stats = const _CleanupStats();
    final parentDirectories = <String>{};

    Future<void> pruneCandidates({required bool enforceByteLimit}) async {
      candidates.sort((a, b) {
        final modifiedOrder = b.modified.compareTo(a.modified);
        return modifiedOrder != 0
            ? modifiedOrder
            : b.file.path.compareTo(a.file.path);
      });
      final retained = <({File file, int size, DateTime modified})>[];
      var nextRetainedBytes = 0;
      var overflowed = false;
      for (final candidate in candidates) {
        if (!overflowed &&
            retained.length < _maxRetainedUploadCacheFiles &&
            (!enforceByteLimit ||
                nextRetainedBytes + candidate.size <=
                    _config.uploadCacheMaxBytes)) {
          retained.add(candidate);
          nextRetainedBytes += candidate.size;
          continue;
        }
        overflowed = true;
        try {
          await candidate.file.delete().timeout(_uploadCacheOperationTimeout);
          stats += _CleanupStats(deletedFiles: 1, bytesFreed: candidate.size);
          _rememberUploadParent(parentDirectories, candidate.file.parent.path);
        } catch (error, stack) {
          silentLog('web_message_platform_service', '限制上传缓存容量', error, stack);
        }
      }
      candidates = retained;
    }

    final scan = await _visitUploadCacheFiles(root, (entity) async {
      try {
        final stat = await entity.stat().timeout(_uploadCacheOperationTimeout);
        candidates.add((
          file: entity,
          size: stat.size,
          modified: stat.modified,
        ));
        if (candidates.length >= _uploadCacheCandidatePruneThreshold) {
          await pruneCandidates(enforceByteLimit: false);
        }
      } catch (error, stack) {
        silentLog(
          'web_message_platform_service',
          '读取上传缓存状态 ${entity.path}',
          error,
          stack,
        );
      }
    });
    if (!scan.complete) {
      _logUploadCacheScanLimit('限制上传缓存容量', scannedEntries: scan.scannedEntries);
    }
    await pruneCandidates(enforceByteLimit: true);
    return stats + await _deleteEmptyUploadDirectories(root, parentDirectories);
  }

  Future<({bool complete, int scannedEntries})> _visitUploadCacheFiles(
    Directory root,
    Future<void> Function(File file) visitor,
  ) async {
    var scannedEntries = 0;
    var complete = true;
    final stopwatch = Stopwatch()..start();
    try {
      await for (final entity
          in root
              .list(recursive: true, followLinks: false)
              .timeout(_uploadCacheScanIdleTimeout)) {
        if (scannedEntries >= _maxUploadCacheScanEntries ||
            stopwatch.elapsed >= _uploadCacheScanTotalTimeout) {
          complete = false;
          break;
        }
        scannedEntries += 1;
        if (entity is File) {
          await visitor(entity);
        }
      }
    } on TimeoutException {
      complete = false;
    } on FileSystemException catch (error, stack) {
      complete = false;
      silentLog(
        'web_message_platform_service',
        '扫描上传缓存 ${root.path}',
        error,
        stack,
      );
    } finally {
      stopwatch.stop();
    }
    return (complete: complete, scannedEntries: scannedEntries);
  }

  void _logUploadCacheScanLimit(String operation, {int? scannedEntries}) {
    _log(
      WebGatewayLogLevel.warn,
      'CLEANUP',
      '上传缓存扫描达到安全上限，剩余内容将在后续清理中继续处理',
      <String, Object?>{
        'operation': operation,
        'scanned_entries': scannedEntries,
        'max_entries': _maxUploadCacheScanEntries,
        'timeout_seconds': _uploadCacheScanTotalTimeout.inSeconds,
      },
    );
  }

  void _rememberUploadParent(Set<String> paths, String path) {
    if (paths.length < _maxUploadDirectoryCleanupCandidates) {
      paths.add(p.normalize(path));
    }
  }

  Future<_CleanupStats> _deleteEmptyUploadDirectories(
    Directory root,
    Set<String> paths,
  ) async {
    final normalizedRoot = p.normalize(p.absolute(root.path));
    final orderedPaths = paths.toList(growable: false)
      ..sort((a, b) => b.length.compareTo(a.length));
    var deletedDirectories = 0;
    for (final path in orderedPaths) {
      final normalizedPath = p.normalize(p.absolute(path));
      if (!p.isWithin(normalizedRoot, normalizedPath)) continue;
      final directory = Directory(normalizedPath);
      try {
        if (await isDirectoryEmpty(directory)) {
          await directory.delete().timeout(_uploadCacheOperationTimeout);
          deletedDirectories += 1;
        }
      } catch (error, stack) {
        silentLog('web_message_platform_service', '删除空上传缓存目录', error, stack);
      }
    }
    return _CleanupStats(deletedDirectories: deletedDirectories);
  }

  /// 读取并解析 JSON 请求体；非法、超时和超限输入由中间件映射为
  /// 400、408 和 413。空 body 返回 `{}`。
  Future<Map<String, Object?>> _readJsonBody(
    shelf.Request request, {
    int maxBytes = kBytesPerMiB,
  }) async {
    if (maxBytes < 1) {
      throw const _WebGatewayRequestException(
        HttpStatus.internalServerError,
        'invalid_request_body_limit',
      );
    }
    final declaredLength = request.contentLength;
    if (declaredLength != null && declaredLength > maxBytes) {
      throw const _WebGatewayRequestException(
        HttpStatus.requestEntityTooLarge,
        'request_body_too_large',
      );
    }
    final chunks = BytesBuilder(copy: false);
    var receivedBytes = 0;
    final deadline = MonotonicDeadline(_requestBodyTotalTimeout);
    try {
      await for (final chunk in request.read().timeout(
        _requestBodyIdleTimeout,
      )) {
        if (deadline.isExpired) {
          throw const _WebGatewayRequestException(
            HttpStatus.requestTimeout,
            'request_body_timeout',
          );
        }
        receivedBytes += chunk.length;
        if (receivedBytes > maxBytes) {
          throw const _WebGatewayRequestException(
            HttpStatus.requestEntityTooLarge,
            'request_body_too_large',
          );
        }
        chunks.add(chunk);
      }
    } on TimeoutException {
      throw const _WebGatewayRequestException(
        HttpStatus.requestTimeout,
        'request_body_timeout',
      );
    } finally {
      deadline.stop();
    }
    if (receivedBytes == 0) return <String, Object?>{};
    try {
      final decoded = jsonDecode(utf8.decode(chunks.takeBytes()));
      if (decoded is Map) return stringKeyedMapFromValue(decoded);
    } on FormatException {
      // 统一映射为下方的客户端错误。
    }
    throw const _WebGatewayRequestException(
      HttpStatus.badRequest,
      'invalid_json_body',
    );
  }

  /// 构造 JSON 响应。`Cache-Control: no-store` 避免浏览器/CDN 缓存敏感数据。
  /// 仅带错误码的 JSON 响应——网关绝大多数失败分支都是这一形态。
  shelf.Response _errorJson(int statusCode, String code) {
    return _json(statusCode, <String, Object?>{'error': code});
  }

  /// 会话不存在或已被删除的统一 404 响应。
  ///
  /// 错误码必须是 [_kWebGatewayErrorSessionMissing]：Web 端据此弹出「会话已被
  /// 删除」提示，换成别的码只会退化成一句通用错误。
  shelf.Response _sessionMissingResponse() {
    return _errorJson(HttpStatus.notFound, _kWebGatewayErrorSessionMissing);
  }

  shelf.Response _json(
    int statusCode,
    Map<String, Object?> payload, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final body = jsonEncode(payload);
    return shelf.Response(
      statusCode,
      body: body,
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: kApplicationJsonUtf8ContentType,
        HttpHeaders.cacheControlHeader: kCacheControlNoStore,
        ...headers,
      },
    );
  }

  /// 构造 HTML 响应。默认 200；bundle 缺失时会传 503。
  shelf.Response _html(String html, {int status = HttpStatus.ok}) {
    return shelf.Response(
      status,
      body: html,
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8',
        HttpHeaders.cacheControlHeader: 'no-cache, max-age=0, must-revalidate',
      },
    );
  }

  /// Web shell 入口。仅从 bundle `assets/web/index.html`（由 clients/web
  /// 的 Vite 构建产出）加载。缺失时返回 503 + 人可读提示。
  Future<shelf.Response> _serveWebShell() async {
    try {
      final html = await _webShellCache.load();
      return _html(html);
    } catch (e, stack) {
      silentLog('web_message_platform_service', '加载 Web 页面构建产物', e, stack);
      return _html(_missingBundleHtml(), status: HttpStatus.serviceUnavailable);
    }
  }

  String _missingBundleHtml() {
    return '<!doctype html><meta charset="utf-8"><title>OpenHand Web</title>'
        '<style>body{font-family:system-ui,sans-serif;max-width:640px;margin:64px auto;padding:0 24px;line-height:1.6;color:#1d1b20;}'
        'code{background:#f3edf7;padding:2px 6px;border-radius:4px;font-family:ui-monospace,monospace;}</style>'
        '<h1>Web client bundle is missing</h1>'
        '<p>The Web shell could not load <code>assets/web/index.html</code>.</p>'
        '<p>Run the following inside the OpenHand repository to produce the bundle:</p>'
        '<pre><code>env CI=true scripts/build_web.sh</code></pre>'
        '<p>Then restart the Web service.</p>';
  }

  /// 静态资源（app.js / app.css / chunks/* / assets/*）从 rootBundle 取，
  /// 缺失或读取失败 → 404。入口固定文件名资源要求重新校验；内容哈希资源允许
  /// immutable 强缓存，兼顾升级正确性与加载性能。
  Future<shelf.Response> _serveBundleAsset(
    String key,
    String contentType,
  ) async {
    if (!key.startsWith('$_kWebAssetRoot/') ||
        safeRelativePathError(key) != null) {
      return shelf.Response.notFound('asset_not_found');
    }
    try {
      final data = await rootBundle.load(key);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      return shelf.Response.ok(
        bytes,
        headers: <String, String>{
          HttpHeaders.contentTypeHeader: contentType,
          HttpHeaders.cacheControlHeader: _bundleCacheControlFor(key),
          HttpHeaders.contentLengthHeader: bytes.length.toString(),
        },
      );
    } catch (e, stack) {
      silentLog('web_message_platform_service', '加载 Web 构建资源：$key', e, stack);
      return shelf.Response.notFound('asset_not_found: $key');
    }
  }

  String _bundleCacheControlFor(String key) {
    final normalized = key.replaceAll('\\', '/');
    if (_isContentHashedBundleAsset(normalized)) {
      return 'public, max-age=31536000, immutable';
    }
    return 'no-cache, max-age=0, must-revalidate';
  }

  bool _isContentHashedBundleAsset(String key) {
    if (!key.startsWith('$_kWebAssetRoot/chunks/') &&
        !key.startsWith('$_kWebAssetRoot/assets/')) {
      return false;
    }
    return RegExp(r'-[A-Za-z0-9_-]{8,}\.[^.]+$').hasMatch(p.basename(key));
  }

  /// 极简 MIME 推断，只覆盖 Vite 构建会产生的扩展名。
  /// 文件扩展名 → Content-Type 映射表。
  static const Map<String, String> _contentTypeByExtension = <String, String>{
    '.js': _kJavaScriptContentType,
    '.mjs': _kJavaScriptContentType,
    '.css': _kCssContentType,
    '.json': kApplicationJsonUtf8ContentType,
    '.svg': kImageSvgXmlMimeType,
    '.png': kImagePngMimeType,
    '.jpg': kImageJpegMimeType,
    '.jpeg': kImageJpegMimeType,
    '.webp': kImageWebpMimeType,
    '.gif': kImageGifMimeType,
    '.bmp': 'image/bmp',
    '.heic': 'image/heic',
    '.mp4': kVideoMp4MimeType,
    '.webm': kVideoWebmMimeType,
    '.mov': kVideoQuickTimeMimeType,
    '.mp3': kAudioMpegMimeType,
    '.wav': kAudioWavMimeType,
    '.ogg': kAudioOggMimeType,
    '.m4a': kAudioMp4MimeType,
    '.flac': kAudioFlacMimeType,
    '.pdf': kApplicationPdfMimeType,
    '.woff2': 'font/woff2',
    '.woff': 'font/woff',
    '.ttf': 'font/ttf',
    '.map': kApplicationJsonUtf8ContentType,
  };

  String _guessContentType(String path) {
    final lower = path.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot < 0) return kApplicationOctetStreamMimeType;
    return _contentTypeByExtension[lower.substring(dot)] ??
        kApplicationOctetStreamMimeType;
  }

  String _attachmentContentDisposition(String filename) {
    final ascii = sanitizePortableFileNamePart(
      filename,
      fallback: '',
      collapseReplacement: true,
      trimBoundaryReplacement: true,
    );
    final fallback = normalizeJsonlExportFilename(
      ascii.isEmpty ? 'session.jsonl' : ascii,
    );
    final encoded = Uri.encodeComponent(filename);
    return 'attachment; filename="$fallback"; filename*=UTF-8\'\'$encoded';
  }

  void _log(
    WebGatewayLogLevel level,
    String tag,
    String message, [
    Map<String, Object?> data = const <String, Object?>{},
  ]) {
    final entry = WebGatewayLogEntry(
      id: _nextLogId++,
      timestamp: DateTime.now().toUtc(),
      level: level,
      tag: tag,
      message: message,
      data: data,
    );
    _memoryLogs.add(entry);
    if (_memoryLogs.length > webGatewayOpsMaxPersistedLogs) {
      _memoryLogs.removeRange(
        0,
        _memoryLogs.length - webGatewayOpsMaxPersistedLogs,
      );
    }
    if (!_logStreamController.isClosed) {
      _logStreamController.add(entry);
    }
    if (_config.loggingEnabled &&
        _config.logConfig.levels.contains(level.name)) {
      unawaited(_fileLogger.write(entry, _config.logConfig));
    }
    _scheduleOpsPersistence();
  }

  Future<_GatewayBindResult> _serveGateway({
    required shelf.Handler handler,
    required InternetAddress address,
    required WebMessagePlatformConfig config,
  }) async {
    try {
      final server = await shelf_io.serve(
        handler,
        address,
        config.listenPort,
        shared: true,
      );
      return _GatewayBindResult(
        server: server,
        requestedPort: config.listenPort,
      );
    } catch (error) {
      if (!_isAddressAlreadyInUse(error)) rethrow;
      final server = await shelf_io.serve(handler, address, 0, shared: true);
      return _GatewayBindResult(
        server: server,
        requestedPort: config.listenPort,
      );
    }
  }

  bool _isAddressAlreadyInUse(Object error) {
    if (error is! SocketException) return false;
    final code = error.osError?.errorCode;
    if (code == 48 || code == 98 || code == 10048) return true;
    final message = '${error.message} ${error.osError?.message ?? ''}'
        .toLowerCase();
    return message.contains('address already in use') ||
        message.contains('only one usage of each socket address') ||
        message.contains('binding multiple times') ||
        message.contains('same (address, port)');
  }

  String _startupFailureMessage(WebMessagePlatformConfig config, Object error) {
    if (_isAddressAlreadyInUse(error)) {
      return 'Web 服务启动失败：${config.listenHost}:${config.listenPort} 已被占用，请关闭占用进程或修改监听端口';
    }
    return messageGatewayFailureMessage(
      error,
      fallback: 'Web 服务启动失败，请检查监听地址与端口。',
    );
  }

  void _logPublicAccessWarningIfNeeded(
    WebMessagePlatformConfig config,
    List<String> urls,
  ) {
    if (config.authEnabled || !_isWildcardListenHost(config.listenHost)) return;
    _log(
      WebGatewayLogLevel.warn,
      'SECURITY',
      'Web 服务正在监听全部网卡且未开启鉴权，请仅在可信网络使用；如需长期跨设备访问，建议开启鉴权或改为 127.0.0.1',
      <String, Object?>{
        'listen_host': config.listenHost,
        'auth_enabled': config.authEnabled,
        'accessible_urls': urls,
      },
    );
  }

  bool _isWildcardListenHost(String host) {
    final normalized = host.trim();
    return normalized.isEmpty ||
        normalized == '0.0.0.0' ||
        normalized == '::' ||
        normalized == '::0';
  }

  InternetAddress _bindAddress(String host) {
    final normalized = host.trim();
    if (normalized.isEmpty || normalized == '0.0.0.0') {
      return InternetAddress.anyIPv4;
    }
    if (normalized == '::' || normalized == '::0') {
      return InternetAddress.anyIPv6;
    }
    return InternetAddress(normalized);
  }

  String _displayHost(String host) {
    final normalized = host.trim();
    if (normalized.isEmpty || normalized == '0.0.0.0' || normalized == '::') {
      return '127.0.0.1';
    }
    return normalized;
  }

  Future<String?> _resolveWorkspacePath(String rawPath) async {
    final root = _workspaceDirectoryPath;
    final normalizedInput = rawPath.trim().replaceAll('\\', '/');
    if (normalizedInput.startsWith('/')) return null;
    final resolved = p.normalize(p.join(root, normalizedInput));
    if (resolved != root && !p.isWithin(root, resolved)) return null;
    final isContained = await isPhysicalPathWithinOrEqual(
      root,
      resolved,
    ).timeout(_workspaceMetadataTimeout, onTimeout: () => false);
    return isContained ? resolved : null;
  }

  Future<T> _awaitWorkspaceFileOperation<T>(Future<T> operation) async {
    try {
      return await operation.timeout(_workspaceMetadataTimeout);
    } on TimeoutException {
      throw const _WebGatewayRequestException(
        HttpStatus.requestTimeout,
        'workspace_file_operation_timeout',
      );
    }
  }

  String _relativeWorkspacePath(String absolutePath) {
    final root = _workspaceDirectoryPath;
    if (absolutePath == root) return '';
    return p.relative(absolutePath, from: root).replaceAll('\\', '/');
  }

  Set<String> _workspaceAllowedExtensions() {
    return _config.workspaceFileAllowedExtensions
        .map(webGatewayNormalizeWorkspaceFileExtension)
        .where((extension) => extension.isNotEmpty)
        .toSet();
  }

  Set<String> _workspaceExtensionsForQuery(String? raw) {
    final configured = _workspaceAllowedExtensions();
    final requested = (raw ?? '')
        .split(',')
        .map(webGatewayNormalizeWorkspaceFileExtension)
        .where((extension) => extension.isNotEmpty)
        .toSet();
    if (requested.isEmpty) return configured;
    if (configured.isEmpty) return requested;
    return requested.where(configured.contains).toSet();
  }

  bool _workspaceExtensionAllowed(String path, Set<String> allowedExtensions) {
    if (allowedExtensions.isEmpty) return true;
    final extension = webGatewayNormalizeWorkspaceFileExtension(
      p.extension(path),
    );
    return allowedExtensions.contains(extension);
  }

  bool _looksBinary(List<int> bytes) {
    final sampleLength = math.min(bytes.length, 4096);
    for (var i = 0; i < sampleLength; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  Future<void> _refreshProcessDiagnosticsIfStale() {
    final pending = _processDiagnosticsRefreshFuture;
    if (pending != null) return pending;
    final now = _monotonicStopwatch.elapsed;
    final previous = _processDiagnosticsRefreshedAt;
    if (previous != null && now - previous < const Duration(seconds: 2)) {
      return Future<void>.value();
    }
    _processDiagnosticsRefreshedAt = now;
    late final Future<void> refresh;
    refresh =
        () async {
          try {
            if (Platform.isMacOS) {
              _processDiagnostics = await _sampleMacProcessDiagnostics();
            } else if (Platform.isLinux) {
              _processDiagnostics = await _sampleLinuxProcessDiagnostics();
            }
          } catch (error, stack) {
            silentLog('web_message_platform_service', '采集进程诊断信息', error, stack);
          }
        }().whenComplete(() {
          if (identical(_processDiagnosticsRefreshFuture, refresh)) {
            _processDiagnosticsRefreshFuture = null;
          }
        });
    _processDiagnosticsRefreshFuture = refresh;
    return refresh;
  }

  Future<_ProcessDiagnostics> _sampleMacProcessDiagnostics() async {
    double? cpuPercent;
    int? threadCount;
    final ps = await runProcessWithTimeout(
      'ps',
      <String>['-o', '%cpu=', '-o', 'nlwp=', '-p', '$pid'],
      timeout: const Duration(milliseconds: 900),
      tag: 'web_message_gateway_ops',
    );
    if (ps != null && ps.exitCode == 0) {
      final parts = '${ps.stdout}'.trim().split(kInlineWhitespacePattern);
      if (parts.isNotEmpty) cpuPercent = optionalDoubleFromValue(parts[0]);
      if (parts.length > 1) {
        threadCount = optionalNonNegativeIntFromValue(parts[1]);
      }
    }
    final lsof = await runProcessWithTimeout(
      'lsof',
      <String>['-n', '-p', '$pid'],
      timeout: const Duration(milliseconds: 1200),
      tag: 'web_message_gateway_ops',
    );
    final fileHandleCount = lsof == null || lsof.exitCode != 0
        ? null
        : math.max(0, '${lsof.stdout}'.trim().split('\n').length - 1);
    final swap = await runProcessWithTimeout(
      'sysctl',
      const <String>['vm.swapusage'],
      timeout: const Duration(milliseconds: 900),
      tag: 'web_message_gateway_ops',
    );
    return _ProcessDiagnostics(
      cpuPercent: cpuPercent,
      threadCount: threadCount,
      fileHandleCount: fileHandleCount,
      swapBytes: _parseMacSwapBytes('${swap?.stdout ?? ''}'),
    );
  }

  Future<_ProcessDiagnostics> _sampleLinuxProcessDiagnostics() async {
    final cpuPercent = await _sampleLinuxCpuPercent();
    int? threadCount;
    int? swapBytes;
    try {
      final status = await readBoundedFileString(
        File('/proc/self/status'),
        maxBytes: _maxProcDiagnosticsFileBytes,
      );
      for (final line in const LineSplitter().convert(status)) {
        if (line.startsWith('Threads:')) {
          threadCount = optionalNonNegativeIntFromValue(
            line.split(kInlineWhitespacePattern).last,
          );
        }
        if (line.startsWith('VmSwap:')) {
          final parts = line.split(kInlineWhitespacePattern);
          if (parts.length > 1) {
            swapBytes =
                (optionalNonNegativeIntFromValue(parts[1]) ?? 0) * kBytesPerKiB;
          }
        }
      }
    } catch (error, stack) {
      silentLog('web_message_platform_service', '读取进程状态', error, stack);
    }
    int? fileHandleCount;
    try {
      final listing = await listDirectoryBounded(
        Directory('/proc/self/fd'),
        maxEntries: _maxProcessFileHandleScanEntries,
        idleTimeout: const Duration(milliseconds: 250),
        totalTimeout: const Duration(seconds: 1),
      );
      fileHandleCount = listing.entries.length;
    } catch (error, stack) {
      silentLog('web_message_platform_service', '统计文件句柄', error, stack);
    }
    return _ProcessDiagnostics(
      cpuPercent: cpuPercent,
      threadCount: threadCount,
      fileHandleCount: fileHandleCount,
      swapBytes: swapBytes,
    );
  }

  Future<double?> _sampleLinuxCpuPercent() async {
    final sample = await _readLinuxCpuSample();
    if (sample == null) return _processDiagnostics.cpuPercent;
    final previous = _previousLinuxCpuSample;
    _previousLinuxCpuSample = sample;
    if (previous == null) return _processDiagnostics.cpuPercent;
    final processDelta = sample.processTicks - previous.processTicks;
    final totalDelta = sample.totalTicks - previous.totalTicks;
    if (processDelta < 0 || totalDelta <= 0) {
      return _processDiagnostics.cpuPercent;
    }
    final cpuCount = math.max(1, Platform.numberOfProcessors);
    return processDelta / totalDelta * cpuCount * 100;
  }

  Future<_LinuxCpuSample?> _readLinuxCpuSample() async {
    try {
      final processStat = await readBoundedFileString(
        File('/proc/self/stat'),
        maxBytes: _maxProcDiagnosticsFileBytes,
      );
      final processEnd = processStat.lastIndexOf(')');
      if (processEnd < 0) return null;
      final processFields = processStat
          .substring(processEnd + 1)
          .trim()
          .split(kInlineWhitespacePattern);
      if (processFields.length <= 12) return null;
      final userTicks = optionalNonNegativeIntFromValue(processFields[11]);
      final systemTicks = optionalNonNegativeIntFromValue(processFields[12]);
      if (userTicks == null || systemTicks == null) return null;

      final stat = await readBoundedFileString(
        File('/proc/stat'),
        maxBytes: _maxProcDiagnosticsFileBytes,
      );
      final cpuLine = const LineSplitter()
          .convert(stat)
          .firstWhere((line) => line.startsWith('cpu '), orElse: () => '');
      if (cpuLine.isEmpty) return null;
      var totalTicks = 0;
      for (final part
          in cpuLine.trim().split(kInlineWhitespacePattern).skip(1)) {
        totalTicks += optionalNonNegativeIntFromValue(part) ?? 0;
      }
      if (totalTicks <= 0) return null;
      return _LinuxCpuSample(
        processTicks: userTicks + systemTicks,
        totalTicks: totalTicks,
      );
    } catch (error, stack) {
      silentLog(
        'web_message_platform_service',
        '读取 Linux CPU 样本',
        error,
        stack,
      );
      return null;
    }
  }

  String _makeToken() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

bool _truthy(String? raw) {
  final parsed = optionalBoolFromValue(raw);
  if (parsed != null) return parsed;
  return raw?.trim().toLowerCase() == 'tail';
}

class _WebGatewayMinuteBucket {
  _WebGatewayMinuteBucket(this.minute);

  factory _WebGatewayMinuteBucket.fromSample(WebGatewayTrafficSample sample) {
    final bucket =
        _WebGatewayMinuteBucket(_webGatewayMinuteStart(sample.minute))
          ..success = sample.success
          ..blocked = sample.blocked
          ..failed = sample.failed
          ..inboundBytes = sample.inboundBytes
          ..outboundBytes = sample.outboundBytes;
    if (sample.avgLatencyMs > 0) bucket.latencies.add(sample.avgLatencyMs);
    if (sample.p95LatencyMs > 0 && sample.p95LatencyMs != sample.avgLatencyMs) {
      bucket.latencies.add(sample.p95LatencyMs);
    }
    return bucket;
  }

  final DateTime minute;
  int success = 0;
  int blocked = 0;
  int failed = 0;
  int inboundBytes = 0;
  int outboundBytes = 0;
  final List<int> latencies = <int>[];
  int _nextLatencyIndex = 0;

  int get total => success + blocked + failed;

  void addLatency(int value, int limit) {
    if (limit <= 0) return;
    if (latencies.length < limit) {
      latencies.add(value);
      return;
    }
    latencies[_nextLatencyIndex] = value;
    _nextLatencyIndex = (_nextLatencyIndex + 1) % limit;
  }

  WebGatewayTrafficSample toSample() {
    var avgLatencyMs = 0;
    var p95LatencyMs = 0;
    if (latencies.isNotEmpty) {
      final sorted = List<int>.from(latencies)..sort();
      avgLatencyMs =
          (sorted.fold<int>(0, (sum, value) => sum + value) / sorted.length)
              .round();
      p95LatencyMs =
          sorted[((sorted.length - 1) * .95).round().clamp(
            0,
            sorted.length - 1,
          )];
    }
    return WebGatewayTrafficSample(
      minute: minute,
      success: success,
      blocked: blocked,
      failed: failed,
      inboundBytes: inboundBytes,
      outboundBytes: outboundBytes,
      avgLatencyMs: avgLatencyMs,
      p95LatencyMs: p95LatencyMs,
    );
  }
}

DateTime _webGatewayMinuteStart(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
}

class _AllowedWebModel {
  const _AllowedWebModel({
    required this.key,
    required this.providerId,
    required this.providerLabel,
    required this.protocolLabel,
    required this.modelId,
    required this.label,
    required this.supportsAttachments,
    required this.supportsImageInput,
    required this.supportsVideoInput,
    required this.supportsAudioInput,
    required this.supportsFileInput,
    required this.attachmentExtensions,
    required this.supportsImageGeneration,
    required this.supportsVideoGeneration,
    required this.supportsAudioGeneration,
    required this.supportsTextTitleGeneration,
    required this.supportsEmbeddings,
    required this.supportsRerank,
    required this.providerDefaultTitleModelKey,
    required this.isGlobalDefaultTitleModel,
    required this.reasoningEffortControlEnabled,
    required this.reasoningEffort,
    required this.reasoningEffortOptions,
  });

  final String key;
  final String providerId;
  final String providerLabel;
  final String protocolLabel;
  final String modelId;
  final String label;
  final bool supportsAttachments;
  final bool supportsImageInput;
  final bool supportsVideoInput;
  final bool supportsAudioInput;
  final bool supportsFileInput;
  final List<String> attachmentExtensions;
  final bool supportsImageGeneration;
  final bool supportsVideoGeneration;
  final bool supportsAudioGeneration;
  final bool supportsTextTitleGeneration;
  final bool supportsEmbeddings;
  final bool supportsRerank;
  final String? providerDefaultTitleModelKey;
  final bool isGlobalDefaultTitleModel;
  final bool reasoningEffortControlEnabled;
  final String? reasoningEffort;
  final List<AiReasoningEffortOption> reasoningEffortOptions;
}

class _ParsedModelKey {
  const _ParsedModelKey({required this.providerId, required this.modelId});

  final String providerId;
  final String modelId;
}

String _modelKey(String providerId, String modelId) => '$providerId::$modelId';

_ParsedModelKey? _parseModelKey(String key) {
  final parts = key.split('::');
  if (parts.length != 2) return null;
  final providerId = parts[0].trim();
  final modelId = parts[1].trim();
  if (providerId.isEmpty || modelId.isEmpty) return null;
  return _ParsedModelKey(providerId: providerId, modelId: modelId);
}

String _string(Object? value, String fallback) {
  if (value == null) return fallback;
  final text = '$value';
  return text.isEmpty ? fallback : text;
}

List<WebGatewayOpsSnapshotRecord> _mergeSnapshotRecords(
  Iterable<WebGatewayOpsSnapshotRecord> persisted,
  Iterable<WebGatewayOpsSnapshotRecord> live,
) {
  final merged = <int, WebGatewayOpsSnapshotRecord>{};
  for (final item in <WebGatewayOpsSnapshotRecord>[...persisted, ...live]) {
    merged[item.timestamp.toUtc().microsecondsSinceEpoch] = item;
  }
  return _trimSnapshotRecords(merged.values);
}

List<WebGatewayLogEntry> _mergeLogs(
  Iterable<WebGatewayLogEntry> persisted,
  Iterable<WebGatewayLogEntry> live,
) {
  final merged = <int, WebGatewayLogEntry>{};
  for (final item in persisted) {
    merged[item.id] = item;
  }
  var nextId = merged.keys.fold<int>(0, math.max) + 1;
  for (final item in live) {
    final existing = merged[item.id];
    if (existing == null) {
      merged[item.id] = item;
      continue;
    }
    if (jsonEncode(existing.toJson()) == jsonEncode(item.toJson())) {
      continue;
    }
    while (merged.containsKey(nextId)) {
      nextId++;
    }
    merged[nextId] = WebGatewayLogEntry(
      id: nextId++,
      timestamp: item.timestamp,
      level: item.level,
      tag: item.tag,
      message: item.message,
      data: item.data,
    );
  }
  return _trimLogs(merged.values);
}

List<WebGatewayCleanupResult> _mergeCleanupHistory(
  Iterable<WebGatewayCleanupResult> persisted,
  Iterable<WebGatewayCleanupResult> live,
) {
  final merged = <String, WebGatewayCleanupResult>{};
  for (final item in <WebGatewayCleanupResult>[...persisted, ...live]) {
    final key =
        '${item.timestamp.toUtc().microsecondsSinceEpoch}:'
        '${item.target}:${item.expiredOnly}';
    merged[key] = item;
  }
  return _trimCleanupHistory(merged.values);
}

List<WebGatewayOpsSnapshotRecord> _trimSnapshotRecords(
  Iterable<WebGatewayOpsSnapshotRecord> source,
) {
  final items = source.toList(growable: false)
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (items.length <= webGatewayOpsMaxPersistedSnapshots) {
    return List<WebGatewayOpsSnapshotRecord>.unmodifiable(items);
  }
  return List<WebGatewayOpsSnapshotRecord>.unmodifiable(
    items.skip(items.length - webGatewayOpsMaxPersistedSnapshots),
  );
}

List<WebGatewayLogEntry> _trimLogs(Iterable<WebGatewayLogEntry> source) {
  final items = source.toList(growable: false)
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (items.length <= webGatewayOpsMaxPersistedLogs) {
    return List<WebGatewayLogEntry>.unmodifiable(items);
  }
  return List<WebGatewayLogEntry>.unmodifiable(
    items.skip(items.length - webGatewayOpsMaxPersistedLogs),
  );
}

List<WebGatewayCleanupResult> _trimCleanupHistory(
  Iterable<WebGatewayCleanupResult> source,
) {
  final items = source.toList(growable: false)
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (items.length <= webGatewayOpsMaxCleanupHistory) {
    return List<WebGatewayCleanupResult>.unmodifiable(items);
  }
  return List<WebGatewayCleanupResult>.unmodifiable(
    items.skip(items.length - webGatewayOpsMaxCleanupHistory),
  );
}

String _safeFileName(String value) {
  return sanitizePortableFileNamePart(value, fallback: 'attachment.bin');
}
