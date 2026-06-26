import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
import '../../../shared/util/lifecycle_cache.dart';
import '../../../shared/util/timer_safety.dart';
import '../../../shared/util/xml_escape.dart';
import '../../ai/index.dart';
import '../../crons/index.dart';
import '../../hardness/index.dart';
import '../../home/index.dart'
    show SessionCacheHitTrend, SessionCacheHitDisplayMode;
import '../../instructions/index.dart';
import '../../knowledge_base/index.dart';
import '../../mcp/index.dart';
import '../../memory/index.dart';
import '../../plugin_service/index.dart';
import '../../skills/index.dart';
import '../../thread_template_runtime/index.dart';
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
  });

  final String id;
  final String sessionId;
  final String command;
  final String workingDirectory;
  final bool isWriteCommand;
  final DateTime createdAt;
  final DateTime expiresAt;
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
    };
  }
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
    );
  }

  final String id;
  final String sessionId;
  final String command;
  final String workingDirectory;
  final bool isWriteCommand;
  final DateTime createdAt;
  final DateTime expiresAt;

  BashCommandApprovalRequest toBashCommandApprovalRequest() {
    return BashCommandApprovalRequest(
      command: command,
      workingDirectory: workingDirectory,
      isWriteCommand: isWriteCommand,
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
  WebMessagePlatformService({
    required AiSessionController sessionController,
    required SettingsController settingsController,
    required SkillsController skillsController,
    required McpController mcpController,
    required MemoryController memoryController,
    required CronsController cronsController,
    required InstructionsController instructionsController,
    KnowledgeBaseController? knowledgeBaseController,
    required AppInfo appInfo,
    String? cacheDirectoryPath,
    String? logsDirectoryPath,
    String? workspaceDirectoryPath,
  }) : _sessionController = sessionController,
       _settingsController = settingsController,
       _skillsController = skillsController,
       _mcpController = mcpController,
       _memoryController = memoryController,
       _cronsController = cronsController,
       _instructionsController = instructionsController,
       _knowledgeBaseController = knowledgeBaseController,
       _appInfo = appInfo,
       _cacheDirectoryPath =
           cacheDirectoryPath ?? OpenHandPaths.defaultCacheDirectoryPath(),
       _workspaceDirectoryPath =
           workspaceDirectoryPath ?? OpenHandPaths.applicationDirectoryPath(),
       _fileLogger = _WebGatewayRotatingLogger(
         logsDirectoryPath: logsDirectoryPath,
       ) {
    _sessionController.addGoalContinuationYieldPredicate(
      _hasQueuedGoalInterruption,
    );
  }

  final AiSessionController _sessionController;
  final SettingsController _settingsController;
  final SkillsController _skillsController;
  final McpController _mcpController;
  final MemoryController _memoryController;
  final CronsController _cronsController;
  final InstructionsController _instructionsController;
  final KnowledgeBaseController? _knowledgeBaseController;
  final AppInfo _appInfo;
  PluginServiceController? _pluginServiceController;

  /// 注入插件服务控制器（延迟注入，避免循环依赖）。
  set pluginServiceController(PluginServiceController? controller) {
    _pluginServiceController = controller;
  }

  final String _cacheDirectoryPath;
  final String _workspaceDirectoryPath;
  final _WebGatewayRotatingLogger _fileLogger;
  final StreamController<WebGatewayLogEntry> _logStreamController =
      StreamController<WebGatewayLogEntry>.broadcast();
  final StreamController<List<WebWriteApprovalRequest>>
  _pendingWriteApprovalStreamController =
      StreamController<List<WebWriteApprovalRequest>>.broadcast(sync: true);
  final AiTranslationService _translationService = AiTranslationService();
  final AiTtsPlaybackService _ttsPlaybackService = AiTtsPlaybackService();
  final List<WebGatewayLogEntry> _memoryLogs = <WebGatewayLogEntry>[];
  final List<WebGatewayCleanupResult> _cleanupHistory =
      <WebGatewayCleanupResult>[];
  final Map<String, _WebGatewayAuthSession> _authSessions =
      <String, _WebGatewayAuthSession>{};
  final Map<String, _WebWriteApprovalRequest> _pendingWriteApprovals =
      <String, _WebWriteApprovalRequest>{};
  final Map<String, Map<String, DateTime>> _queuedGoalYieldLeasesBySessionId =
      <String, Map<String, DateTime>>{};
  int _nextWriteApprovalId = 1;

  HttpServer? _server;
  WebGatewayRuntimeState _state = WebGatewayRuntimeState.stopped;
  WebMessagePlatformConfig _config = const WebMessagePlatformConfig();
  WebGatewayThemeSnapshot _theme = const WebGatewayThemeSnapshot();
  DateTime? _startedAt;
  int _activeRequests = 0;
  int _totalRequests = 0;
  int _totalErrors = 0;
  int _totalBytesIn = 0;
  int _totalBytesOut = 0;
  int _crashCount = 0;
  int _restartCount = 0;
  int _nextLogId = 1;
  String _lastError = '';
  // 扩展运维指标。遵循 SRE 四黄金信号和 OpenTelemetry HTTP 指标思路：
  // latency / traffic / errors / saturation 全部在进程内轻量采样，路由使用
  // 低基数字段，避免被 query 或动态 ID 撑爆。
  static const int _maxRouteEntries = 32;
  static const int _maxLatencyBuffer = 256;
  static const int _maxTimestampBuffer = 600;
  static const int _maxObservationBuffer = 600;
  static const int _maxMessageWindowLimit = 200;
  static const int _sseMessageWindowSize = 20;
  static const int _sessionSummaryMessageWindowSize = 6;
  static const int _storedMessageWindowScanMultiplier = 1;
  static const int _storedMessageWindowScanContext = 8;
  static const int _storedMessageWindowExpandedScanMultiplier = 2;
  static const int _storedMessageWindowExpandedScanContext = 16;
  static const int _storedMessageWindowExpandedScanLimit = 96;
  static const Duration _queuedGoalYieldLeaseDuration = Duration(minutes: 15);
  final Map<String, int> _statusBuckets = <String, int>{
    '1xx': 0,
    '2xx': 0,
    '3xx': 0,
    '4xx': 0,
    '5xx': 0,
  };
  final Map<String, int> _methodCounts = <String, int>{};
  final Map<String, int> _routeCounts = <String, int>{};
  final List<int> _latencyBuffer = <int>[];
  final List<int> _recentRequestEpochMs = <int>[];
  final List<_RequestObservation> _recentRequestObservations =
      <_RequestObservation>[];
  DateTime? _lastErrorAt;
  String _lastErrorPath = '';
  String _slowestRecentPath = '';
  String _slowestRecentMethod = '';
  int _slowestRecentDurationMs = 0;
  int _slowestRecentStatus = 0;
  DateTime? _slowestRecentAt;
  _ProcessDiagnostics _processDiagnostics = const _ProcessDiagnostics();
  DateTime? _processDiagnosticsAt;
  _LinuxCpuSample? _previousLinuxCpuSample;

  /// 当前活跃的 SSE 订阅数（每个 `/api/sessions/<id>/events` 长连接 +1，
  /// onCancel 时 -1）。Ops 面板用它判断"是否有人在看活跃流"，并辅助识别
  /// 客户端泄漏（断网后未释放的悬挂连接）。
  int _activeSseSubscriptions = 0;

  /// 最近 N 次 4xx/5xx 请求的环形缓冲。Ops 面板按时间倒序展示，便于"刚出错就能看到"。
  /// 每条 ≤ 256B（path 截 80, error 截 160），整体内存占用上限 ≈ 5KB。
  static const int _maxRecentErrors = 16;
  final List<Map<String, Object?>> _recentErrors = <Map<String, Object?>>[];

  /// 缓存当前主机非环回 IPv4 地址列表，作为 `accessibleUrls` 在
  /// 监听 `0.0.0.0` / `::` 时枚举局域网 URL 的数据源。`start()` 后填充，
  /// `runtimeSnapshotAsync()` 触发时按 30s TTL 刷新。
  List<String> _localAddressesCache = const <String>[];
  DateTime? _localAddressesAt;

  Stream<WebGatewayLogEntry> get logStream => _logStreamController.stream;
  Stream<List<WebWriteApprovalRequest>> get pendingWriteApprovalsStream =>
      _pendingWriteApprovalStreamController.stream;
  List<WebGatewayLogEntry> get logs =>
      List<WebGatewayLogEntry>.unmodifiable(_memoryLogs);
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

  bool _hasQueuedGoalInterruption(String sessionId) {
    final leases = _queuedGoalYieldLeasesBySessionId[sessionId];
    if (leases == null || leases.isEmpty) {
      return false;
    }
    final cutoff = DateTime.now().toUtc().subtract(
      _queuedGoalYieldLeaseDuration,
    );
    leases.removeWhere((_, updatedAt) => updatedAt.isBefore(cutoff));
    if (leases.isEmpty) {
      _queuedGoalYieldLeasesBySessionId.remove(sessionId);
      return false;
    }
    return true;
  }

  void _setQueuedGoalInterruption({
    required _WebGatewayAuthSession auth,
    required String sessionId,
    required bool hasPendingQueue,
  }) {
    final authKey = auth.token.trim().isEmpty ? 'anonymous' : auth.token.trim();
    if (!hasPendingQueue) {
      final leases = _queuedGoalYieldLeasesBySessionId[sessionId];
      leases?.remove(authKey);
      if (leases != null && leases.isEmpty) {
        _queuedGoalYieldLeasesBySessionId.remove(sessionId);
      }
      return;
    }
    final leases = _queuedGoalYieldLeasesBySessionId.putIfAbsent(
      sessionId,
      () => <String, DateTime>{},
    );
    leases[authKey] = DateTime.now().toUtc();
  }

  void updateTheme(WebGatewayThemeSnapshot theme) {
    _theme = theme;
  }

  Future<void> start(WebMessagePlatformConfig config) async {
    _config = config;
    if (_server != null) {
      await stop();
    }
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
          .addMiddleware(_corsMiddleware())
          .addMiddleware(_telemetryAndLimitMiddleware());
      final handler = pipeline.addHandler(_buildRouter().call);
      final bindResult = await _serveGateway(
        handler: handler,
        address: address,
        config: config,
      );
      final server = bindResult.server;
      server.serverHeader = 'OpenHand-WebGateway/1.0';
      _server = server;
      _startedAt = DateTime.now().toUtc();
      _lastError = '';
      _lastErrorAt = null;
      _lastErrorPath = '';
      _state = WebGatewayRuntimeState.running;
      // 启动后立刻探测一次主机 IP 列表，使 BOOT 日志可同时打出 LAN URL；
      // NetworkInterface.list 内部毫秒级，且失败仅 silentLog，不阻塞 boot。
      await _refreshLocalAddressesIfStale(ttl: Duration.zero);
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
      // 启动后顺手做一次过期清理；失败不应阻塞 boot 流程，但要走 silentLog
      // 防止 Future error 被 unawaited 静默吞掉。
      unawaited(() async {
        try {
          await cleanupArtifacts(logs: true, uploads: true, expiredOnly: true);
        } catch (error, stack) {
          silentLog(
            'web_message_platform_service',
            'start cleanupArtifacts',
            error,
            stack,
          );
        }
      }());
    } catch (error, stack) {
      _state = WebGatewayRuntimeState.crashed;
      _crashCount++;
      _lastError = _startupFailureMessage(config, error);
      _log(WebGatewayLogLevel.error, 'BOOT', _lastError, <String, Object?>{
        'host': config.listenHost,
        'port': config.listenPort,
      });
      if (!_isAddressAlreadyInUse(error)) {
        silentLog('web_message_platform_service', 'start', error, stack);
      }
      rethrow;
    }
  }

  Future<void> stop() async {
    await _ttsPlaybackService.stop();
    final server = _server;
    if (server == null) {
      _state = WebGatewayRuntimeState.stopped;
      return;
    }
    _state = WebGatewayRuntimeState.stopping;
    _log(WebGatewayLogLevel.warn, 'OPS', '正在停止 Web 服务');
    _server = null;
    try {
      await server.close(force: true);
      _state = WebGatewayRuntimeState.stopped;
      _startedAt = null;
      _authSessions.clear();
      _queuedGoalYieldLeasesBySessionId.clear();
      _log(WebGatewayLogLevel.success, 'OPS', 'Web 服务已停止');
    } catch (error, stack) {
      _state = WebGatewayRuntimeState.crashed;
      _crashCount++;
      _lastError = '$error';
      _log(WebGatewayLogLevel.error, 'OPS', '停止 Web 服务失败: $error');
      silentLog('web_message_platform_service', 'stop', error, stack);
    }
  }

  Future<void> restart(WebMessagePlatformConfig config) async {
    _restartCount++;
    await stop();
    await start(config);
  }

  Future<void> reloadConfig(WebMessagePlatformConfig config) async {
    final needsRestart =
        config.enabled != _config.enabled ||
        config.listenHost != _config.listenHost ||
        config.listenPort != _config.listenPort;
    _config = config;
    _log(WebGatewayLogLevel.info, 'OPS', '配置已重新加载');
    if (needsRestart) {
      await restart(config);
    }
  }

  Future<void> dispose() async {
    await stop();
    _sessionController.removeGoalContinuationYieldPredicate(
      _hasQueuedGoalInterruption,
    );
    _translationService.dispose();
    await _ttsPlaybackService.dispose();
    await _logStreamController.close();
    await _pendingWriteApprovalStreamController.close();
  }

  WebGatewayRuntimeSnapshot runtimeSnapshot() {
    final startedAt = _startedAt;
    final uptimeMs = startedAt == null
        ? 0
        : DateTime.now().toUtc().difference(startedAt).inMilliseconds;
    return WebGatewayRuntimeSnapshot(
      state: _state,
      startedAt: startedAt,
      uptimeMs: uptimeMs,
      boundUrl: boundUrl,
      accessibleUrls: accessibleUrls,
      activeRequests: _activeRequests,
      maxConcurrentRequests: _config.maxConcurrentRequests,
      activeRequestRatio: _config.maxConcurrentRequests <= 0
          ? 0
          : _activeRequests / _config.maxConcurrentRequests,
      totalRequests: _totalRequests,
      totalErrors: _totalErrors,
      totalBytesIn: _totalBytesIn,
      totalBytesOut: _totalBytesOut,
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
      bytesInPerMinute: _computeBytesPerMinute((item) => item.requestBytes),
      bytesOutPerMinute: _computeBytesPerMinute((item) => item.responseBytes),
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
      dartVersion: Platform.version,
      hostName: _safeHostName(),
      activeSseSubscriptions: _activeSseSubscriptions,
      recentErrors: List<Map<String, Object?>>.unmodifiable(
        _recentErrors.map((e) => Map<String, Object?>.unmodifiable(e)),
      ),
      logLevelBreakdown: _computeLogLevelBreakdown(),
      memoryLogCount: _memoryLogs.length,
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
      mcpServerEnabledCount: _mcpController.servers
          .where((s) => s.enabled)
          .length,
      mcpServerTotalCount: _mcpController.servers.length,
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
      // 路由分布：保留前缀，规避 query string；超过容量后按计数最少裁剪一个，避免无界增长。
      final routeKey = path.isEmpty ? '/' : path;
      _routeCounts[routeKey] = (_routeCounts[routeKey] ?? 0) + 1;
      if (_routeCounts.length > _maxRouteEntries) {
        final smallest = _routeCounts.entries.reduce(
          (a, b) => a.value <= b.value ? a : b,
        );
        _routeCounts.remove(smallest.key);
      }
      // 延迟环形缓冲：达到容量就 FIFO 出队。
      _latencyBuffer.add(durationMs);
      if (_latencyBuffer.length > _maxLatencyBuffer) {
        _latencyBuffer.removeAt(0);
      }
      // RPS 时间戳环形缓冲：用 ms-epoch 节省内存；查询时按"最近 60s"过滤计算。
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      _recentRequestEpochMs.add(nowMs);
      if (_recentRequestEpochMs.length > _maxTimestampBuffer) {
        _recentRequestEpochMs.removeAt(0);
      }
      _recentRequestObservations.add(
        _RequestObservation(
          atMs: nowMs,
          method: methodKey,
          path: routeKey,
          statusCode: statusCode,
          durationMs: durationMs,
          requestBytes: requestBytes,
          responseBytes: responseBytes,
        ),
      );
      if (_recentRequestObservations.length > _maxObservationBuffer) {
        _recentRequestObservations.removeRange(
          0,
          _recentRequestObservations.length - _maxObservationBuffer,
        );
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
          'path': _truncate(errorPath ?? routeKey, 80),
          'status': statusCode,
          'duration_ms': durationMs,
          if (errorMessage != null && errorMessage.isNotEmpty)
            'message': _truncate(errorMessage, 160),
        };
        _recentErrors.add(entry);
        if (_recentErrors.length > _maxRecentErrors) {
          _recentErrors.removeRange(0, _recentErrors.length - _maxRecentErrors);
        }
      }
    } catch (error, stack) {
      silentLog(
        'web_message_platform_service',
        'observe metrics',
        error,
        stack,
      );
    }
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

  // 估算"最近 60 秒"内 RPS（每分钟请求数）。
  // 时间窗口固定 60s；落在窗口内的事件计数除以"实际窗口长度（秒）"再 ×60。
  // 当只观测到极短窗口时（启动一两秒），仍能给出收敛较好的瞬时速率，避免长时间显示 0。
  double _computeRequestsPerMinute() {
    if (_recentRequestEpochMs.isEmpty) return 0;
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    const windowMs = 60 * 1000;
    final cutoff = nowMs - windowMs;
    final inWindow = _recentRequestEpochMs
        .where((t) => t >= cutoff)
        .toList(growable: false);
    if (inWindow.isEmpty) return 0;
    final spanMs = math.max(1, nowMs - inWindow.first);
    final actualWindowMs = math.min(spanMs, windowMs);
    return inWindow.length * (60 * 1000) / actualWindowMs;
  }

  double _computeErrorsPerMinute() {
    final items = _observationsInWindow(const Duration(minutes: 1));
    if (items.isEmpty) return 0;
    return items.where((item) => item.statusCode >= 400).length.toDouble();
  }

  double _computeBytesPerMinute(int Function(_RequestObservation) read) {
    final items = _observationsInWindow(const Duration(minutes: 1));
    if (items.isEmpty) return 0;
    var total = 0;
    for (final item in items) {
      total += read(item);
    }
    return total.toDouble();
  }

  List<_RequestObservation> _observationsInWindow(Duration window) {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final cutoff = nowMs - window.inMilliseconds;
    return _recentRequestObservations
        .where((item) => item.atMs >= cutoff)
        .toList(growable: false);
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
      silentLog(
        'web_message_platform_service',
        'read local hostname',
        error,
        stack,
      );
      return '';
    }
  }

  Future<WebGatewayRuntimeSnapshot> runtimeSnapshotAsync() async {
    await _refreshProcessDiagnosticsIfStale();
    await _refreshLocalAddressesIfStale();
    return runtimeSnapshot();
  }

  /// 刷新主机非环回 IPv4 地址列表，30 s TTL。失败不抛，仅 silentLog——
  /// 缓存保持上一次结果（启动期为空列表，UI 仍能显示 localhost/127.0.0.1）。
  Future<void> _refreshLocalAddressesIfStale({
    Duration ttl = const Duration(seconds: 30),
  }) async {
    final stamp = _localAddressesAt;
    if (stamp != null && DateTime.now().toUtc().difference(stamp) < ttl) {
      return;
    }
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final addrs = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final value = addr.address.trim();
          if (value.isNotEmpty) addrs.add(value);
        }
      }
      _localAddressesCache = List<String>.unmodifiable(addrs);
      _localAddressesAt = DateTime.now().toUtc();
    } catch (error, stack) {
      silentLog(
        'web_message_platform_service',
        'refresh local addresses',
        error,
        stack,
      );
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
    final client = HttpClient()
      ..connectionTimeout = Duration(milliseconds: health.timeoutMs);
    try {
      final request = await client
          .openUrl(health.method, uri)
          .timeout(Duration(milliseconds: health.timeoutMs));
      request.followRedirects = health.followRedirects;
      final response = await request.close().timeout(
        Duration(milliseconds: health.timeoutMs),
      );
      final body = await utf8
          .decodeStream(response)
          .timeout(Duration(milliseconds: health.timeoutMs));
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
        bodyPreview: _truncate(body, 600),
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
      silentLog('web_message_platform_service', 'health check', error, stack);
      final result = WebGatewayHealthResult(
        ok: false,
        statusCode: 0,
        durationMs: stopwatch.elapsedMilliseconds,
        summary: '健康检查失败: $error',
      );
      _log(WebGatewayLogLevel.error, 'HEALTH', result.summary);
      return result;
    } finally {
      client.close();
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

    await _refreshLocalAddressesIfStale(ttl: Duration.zero);
    final targets = <String>{...accessibleUrls}.toList(growable: false);
    addLog('发现 ${targets.length} 个当前可访问入口。');
    final timeoutMs = math.min(
      10000,
      math.max(500, _config.healthCheck.timeoutMs),
    );
    final client = HttpClient()
      ..connectionTimeout = Duration(milliseconds: timeoutMs);
    final results = <WebGatewayConnectivityProbeResult>[];

    try {
      for (final baseUrl in targets) {
        final probeStarted = Stopwatch()..start();
        Uri endpoint;
        try {
          final baseUri = Uri.parse(baseUrl);
          endpoint = baseUri.replace(path: '/api/health');
        } catch (error) {
          probeStarted.stop();
          addLog('URL 解析失败: $baseUrl · $error');
          results.add(
            WebGatewayConnectivityProbeResult(
              baseUrl: baseUrl,
              endpointUrl: baseUrl,
              host: baseUrl,
              port: 0,
              ok: false,
              statusCode: 0,
              durationMs: probeStarted.elapsedMilliseconds,
              errorMessage: '$error',
            ),
          );
          continue;
        }

        addLog('开始探测 ${endpoint.host}:${endpoint.port} -> $endpoint');
        try {
          final request = await client
              .getUrl(endpoint)
              .timeout(Duration(milliseconds: timeoutMs));
          request.followRedirects = false;
          final response = await request.close().timeout(
            Duration(milliseconds: timeoutMs),
          );
          final body = await utf8
              .decodeStream(response)
              .timeout(Duration(milliseconds: timeoutMs));
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
              bodyPreview: _truncate(body, 600),
              errorMessage: ok ? '' : 'HTTP ${response.statusCode}',
            ),
          );
        } catch (error, stack) {
          probeStarted.stop();
          if (error is! TimeoutException) {
            silentLog(
              'web_message_platform_service',
              'connectivity probe',
              error,
              stack,
            );
          }
          addLog(
            '探测失败 ${endpoint.host}:${endpoint.port} · ${probeStarted.elapsedMilliseconds}ms · $error',
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
              errorMessage: '$error',
            ),
          );
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
      if (_cleanupHistory.length > 50) {
        _cleanupHistory.removeRange(0, _cleanupHistory.length - 50);
      }
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
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(await _logBundlePayload());
  }

  Future<String> exportCurrentLogText() async {
    final currentFileText = await _fileLogger.readCurrentLogText();
    if (currentFileText.trim().isNotEmpty) {
      return currentFileText;
    }
    return _memoryLogs.map((entry) => entry.toLogLine()).join('\n');
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
    // Vite 产物里 index.html 引用 app.js / app.css 同级文件，直接出 bundle。
    router.get(
      '/app.js',
      (shelf.Request _) => _serveBundleAsset(
        'assets/web/app.js',
        'application/javascript; charset=utf-8',
      ),
    );
    router.get(
      '/app.css',
      (shelf.Request _) =>
          _serveBundleAsset('assets/web/app.css', 'text/css; charset=utf-8'),
    );
    // 兼容旧缓存 shell: 旧 index.html 使用 ./app.css / ./app.js，用户在
    // /threads/<id> 原地刷新时浏览器会解析到 /threads/app.css。
    router.get(
      '/threads/app.js',
      (shelf.Request _) => _serveBundleAsset(
        'assets/web/app.js',
        'application/javascript; charset=utf-8',
      ),
    );
    router.get(
      '/threads/app.css',
      (shelf.Request _) =>
          _serveBundleAsset('assets/web/app.css', 'text/css; charset=utf-8'),
    );
    // 通配子路径覆盖 chunks/*.js 与 assets/*.{png,svg,woff2,...}。
    router.get(
      '/chunks/<path|.+>',
      (shelf.Request _, String path) =>
          _serveBundleAsset('assets/web/chunks/$path', _guessContentType(path)),
    );
    router.get(
      '/threads/chunks/<path|.+>',
      (shelf.Request _, String path) =>
          _serveBundleAsset('assets/web/chunks/$path', _guessContentType(path)),
    );
    router.get(
      '/assets/<path|.+>',
      (shelf.Request _, String path) =>
          _serveBundleAsset('assets/web/assets/$path', _guessContentType(path)),
    );
    router.get(
      '/threads/assets/<path|.+>',
      (shelf.Request _, String path) =>
          _serveBundleAsset('assets/web/assets/$path', _guessContentType(path)),
    );
    // public/ 拷贝到 assets/web/ 根的静态资源（logo、favicon 等）。Vite build
    // 把 clients/web/public/* 平铺至产物根目录，Flutter pubspec 把整个目录纳入
    // bundle，这里按白名单显式 expose 以避免被 SPA shell 路由 catch-all 截胡。
    router.get(
      '/openhand_logo.png',
      (shelf.Request _) =>
          _serveBundleAsset('assets/web/openhand_logo.png', 'image/png'),
    );
    router.get(
      '/threads/openhand_logo.png',
      (shelf.Request _) =>
          _serveBundleAsset('assets/web/openhand_logo.png', 'image/png'),
    );
    router.get(
      '/favicon.ico',
      (shelf.Request _) =>
          _serveBundleAsset('assets/web/openhand_logo.png', 'image/png'),
    );
    router.get(
      '/threads/favicon.ico',
      (shelf.Request _) =>
          _serveBundleAsset('assets/web/openhand_logo.png', 'image/png'),
    );
    // PWA: Service Worker 必须挂在站点根 scope, manifest.webmanifest 给浏览器
    // 装机使用. 两者通过 vite public/ 目录被 Flutter rootBundle 一并打包。
    router.get(
      '/sw.js',
      (shelf.Request _) => _serveBundleAsset(
        'assets/web/sw.js',
        'application/javascript; charset=utf-8',
      ),
    );
    router.get(
      '/threads/sw.js',
      (shelf.Request _) => _serveBundleAsset(
        'assets/web/sw.js',
        'application/javascript; charset=utf-8',
      ),
    );
    router.get(
      '/manifest.webmanifest',
      (shelf.Request _) => _serveBundleAsset(
        'assets/web/manifest.webmanifest',
        'application/manifest+json; charset=utf-8',
      ),
    );
    router.get(
      '/threads/manifest.webmanifest',
      (shelf.Request _) => _serveBundleAsset(
        'assets/web/manifest.webmanifest',
        'application/manifest+json; charset=utf-8',
      ),
    );
    // SPA 深路由：/threads/<id> 直接刷新或粘贴打开都能命中前端 Router。
    // 必须放在静态资源别名之后，避免 /threads/app.css 被 HTML shell 截获。
    router.get(
      '/threads/<rest|.+>',
      (shelf.Request _, String rest) => _serveWebShell(),
    );
    router.get('/api/health', _apiHealth);
    router.get('/api/meta', _apiMeta);
    router.post('/api/login', _login);
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
    router.post(
      '/api/sessions/<sessionId>/messages',
      (shelf.Request r, String sessionId) =>
          _withAuth(r, (req, auth) => _sendMessage(req, auth, sessionId)),
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

    // Toolbox: 只读列出 MCP 服务器 / 已安装技能 / 用户记忆 / 定时任务
    // App 端是这些资源的真权威 (增删改全在 GUI), Web 端只读消费即可。
    router.get(
      '/api/mcp/servers',
      (shelf.Request r) => _withAuth(r, (_, _) => _listMcpServersHandler()),
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
      '/api/hardness/session',
      (shelf.Request r) => _withAuth(r, (_, _) => _hardnessSessionHandler()),
    );
    router.get(
      '/api/harness/session',
      (shelf.Request r) => _withAuth(r, (_, _) => _hardnessSessionHandler()),
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

    return router;
  }

  shelf.Response _shelfNotFound(shelf.Request request) =>
      _json(HttpStatus.notFound, <String, Object?>{'error': 'not_found'});

  /// CORS 头 + OPTIONS 预检统一处理。
  shelf.Middleware _corsMiddleware() {
    const corsHeaders = <String, String>{
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
      'access-control-allow-headers':
          'authorization,content-type,x-openhand-device-id,x-openhand-source,x-openhand-device-mac,x-openhand-device-name,x-openhand-device-platform,x-openhand-os-name,x-openhand-os-version,x-openhand-browser-name,x-openhand-browser-version,x-openhand-web-client-version,x-openhand-locale,x-openhand-timezone,x-openhand-screen-class',
    };
    return (innerHandler) {
      return (shelf.Request request) async {
        if (request.method == 'OPTIONS') {
          return shelf.Response(HttpStatus.noContent, headers: corsHeaders);
        }
        final response = await innerHandler(request);
        return response.change(headers: corsHeaders);
      };
    };
  }

  /// 并发限流 + 请求/字节计数 + 异常兜底 + 访问日志。
  /// 与旧 `_handleRequest` 的副作用一一对应：超过 `maxConcurrentRequests`
  /// 直接返回 429，否则在 finally 写访问日志，按状态码挑选 level。
  shelf.Middleware _telemetryAndLimitMiddleware() {
    return (innerHandler) {
      return (shelf.Request request) async {
        _totalRequests++;
        final requestBytes = request.contentLength ?? 0;
        _totalBytesIn += requestBytes;
        final stopwatch = Stopwatch()..start();
        if (_activeRequests >= _config.maxConcurrentRequests) {
          _totalErrors++;
          stopwatch.stop();
          final limited = _json(
            HttpStatus.tooManyRequests,
            const <String, Object?>{'error': 'too_many_requests'},
          );
          final responseBytes = limited.contentLength ?? 0;
          _totalBytesOut += responseBytes;
          _observeRequestMetrics(
            method: request.method,
            path: request.requestedUri.path,
            statusCode: HttpStatus.tooManyRequests,
            durationMs: stopwatch.elapsedMilliseconds,
            requestBytes: requestBytes,
            responseBytes: responseBytes,
            errorPath: request.requestedUri.path,
            errorMessage: 'too_many_requests',
          );
          _log(WebGatewayLogLevel.warn, 'HTTP', '请求被并发限制拒绝', <String, Object?>{
            'path': request.requestedUri.path,
            'active_requests': _activeRequests,
            'limit': _config.maxConcurrentRequests,
          });
          return limited;
        }
        _activeRequests++;
        var statusCode = 0;
        var responseBytes = 0;
        String? errorText;
        try {
          final response = await innerHandler(request);
          statusCode = response.statusCode;
          responseBytes = response.contentLength ?? 0;
          return response;
        } catch (error, stack) {
          statusCode = HttpStatus.internalServerError;
          errorText = '$error';
          _totalErrors++;
          _lastError = errorText;
          silentLog(
            'web_message_platform_service',
            'handle request',
            error,
            stack,
          );
          final fallback = _json(
            HttpStatus.internalServerError,
            <String, Object?>{'error': 'internal_error', 'message': errorText},
          );
          responseBytes = fallback.contentLength ?? 0;
          return fallback;
        } finally {
          _activeRequests = math.max(0, _activeRequests - 1);
          stopwatch.stop();
          _totalBytesOut += responseBytes;
          // 在 telemetry 写日志前更新指标，确保 snapshot 与日志同源（同一窗口同一观察者）。
          _observeRequestMetrics(
            method: request.method,
            path: request.requestedUri.path,
            statusCode: statusCode,
            durationMs: stopwatch.elapsedMilliseconds,
            requestBytes: requestBytes,
            responseBytes: responseBytes,
            errorPath: errorText != null ? request.requestedUri.path : null,
            errorMessage: errorText,
          );
          final connectionInfo =
              request.context['shelf.io.connection_info']
                  as HttpConnectionInfo?;
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
                'query': request.requestedUri.queryParameters,
                'status_code': statusCode,
                'duration_ms': stopwatch.elapsedMilliseconds,
                'remote_ip': connectionInfo?.remoteAddress.address,
                'remote_port': connectionInfo?.remotePort,
                'user_agent': request.headers[HttpHeaders.userAgentHeader],
                'content_length': requestBytes,
                'response_bytes': responseBytes,
                'active_requests': _activeRequests,
                if (errorText != null) 'error': errorText,
              },
            );
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
      return _json(HttpStatus.unauthorized, <String, Object?>{
        'error': 'unauthorized',
      });
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
    return _json(HttpStatus.ok, _metaPayload());
  }

  Future<shelf.Response> _opsSnapshot() async {
    if (!_config.opsEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'ops_disabled',
      });
    }
    return _json(HttpStatus.ok, (await runtimeSnapshotAsync()).toJson());
  }

  List<Map<String, Object?>> _templateAssociationsForMcpServer(
    McpServer server,
  ) {
    final catalog = _mcpController.toolCatalogFor(server.name);
    final text = StringBuffer()
      ..write(server.name)
      ..write(' ')
      ..write(server.summary)
      ..write(' ')
      ..write(server.type.transportValue);
    for (final tool in catalog.tools) {
      text
        ..write(' ')
        ..write(tool.id)
        ..write(' ')
        ..write(tool.name)
        ..write(' ')
        ..write(tool.description);
    }
    final raw = text.toString();
    return TemplateRuntimeDependencyRegistry.specsForMcpText(raw)
        .map(
          (spec) => <String, Object?>{
            'template_id': spec.templateId,
            'label_zh': spec.labelZh,
            'label_en': spec.labelEn,
            'capabilities': spec
                .matchingCapabilities(raw)
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
          },
        )
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
    final items = _mcpController.servers
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

  /// Toolbox: 持久化的 Harness Engineering 会话快照 (单实例)。
  /// App 同时只跑一个 Harness session, 持久化在 SQLite 的 hardness_sessions 表;
  /// orchestrator 是 home page 内部状态, 不直接暴露到 service, 故 web 走 store
  /// 的最近一次写入。返回 `{record: null}` 表示尚未运行过 Harness。
  Future<shelf.Response> _hardnessSessionHandler() async {
    try {
      final record = await HardnessSessionStore().load();
      return _json(HttpStatus.ok, <String, Object?>{
        'record': record?.toJson(),
      });
    } catch (e, st) {
      silentLog('web_gateway', 'hardness_session_load_failed', e, st);
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'error': 'hardness_load_failed',
        'message': e.toString(),
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
    final body = await _readJsonBody(request, maxBytes: 4 * 1024);
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

  // ─── Plugin Service Handlers ───────────────────────────────────────────────

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
    } catch (e) {
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'error': 'plugin_list_failed',
        'message': '$e',
      });
    }
  }

  Future<shelf.Response> _pluginInstallHandler(shelf.Request request) async {
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
    final success = await controller.installPlugin(pluginId);
    return _json(HttpStatus.ok, <String, Object?>{
      'success': success,
      'message': controller.errorMessage,
      'new_version': controller.pluginById(pluginId)?.installedVersion,
    });
  }

  Future<shelf.Response> _pluginUpdateHandler(shelf.Request request) async {
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
    final success = await controller.updatePlugin(pluginId);
    return _json(HttpStatus.ok, <String, Object?>{
      'success': success,
      'message': controller.errorMessage,
      'new_version': controller.pluginById(pluginId)?.installedVersion,
    });
  }

  Future<shelf.Response> _pluginUninstallHandler(shelf.Request request) async {
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
    final success = await controller.uninstallPlugin(pluginId);
    return _json(HttpStatus.ok, <String, Object?>{
      'success': success,
      'message': controller.errorMessage,
    });
  }

  Future<shelf.Response> _pluginRescanHandler() async {
    final controller = _pluginServiceController;
    if (controller == null) {
      return _json(HttpStatus.ok, <String, Object?>{'items': <Object?>[]});
    }
    await controller.rescan();
    final items = controller.plugins
        .map(_pluginPayload)
        .toList(growable: false);
    return _json(HttpStatus.ok, <String, Object?>{'items': items});
  }

  Future<shelf.Response> _pluginCheckUpdateHandler(
    shelf.Request request,
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
                      ? '${entry.body.substring(0, 4096)}…'
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
              'supports_image_generation': item.supportsImageGeneration,
              'supports_video_generation': item.supportsVideoGeneration,
              'supports_audio_generation': item.supportsAudioGeneration,
              'supports_text_title_generation':
                  item.supportsTextTitleGeneration,
              'supports_embeddings': item.supportsEmbeddings,
              'provider_default_title_model_key':
                  item.providerDefaultTitleModelKey,
              'is_global_default_title_model': item.isGlobalDefaultTitleModel,
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
    final body = await _readJsonBody(request);
    final source = WebGatewayLoginSource.fromStorage(
      _string(body['source'], 'WEB_PC'),
    );
    final deviceId = _string(body['device_id'], '').trim();
    if (deviceId.isEmpty) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'device_id_required',
      });
    }
    if (_config.authEnabled) {
      final username = _string(body['username'], '').trim();
      final password = _string(body['password'], '');
      if (username != _config.username || password != _config.password) {
        _log(WebGatewayLogLevel.warn, 'AUTH', '登录失败', <String, Object?>{
          'username': username,
          'device_id': deviceId,
          'remote_ip':
              (request.context['shelf.io.connection_info']
                      as HttpConnectionInfo?)
                  ?.remoteAddress
                  .address,
        });
        return _json(HttpStatus.unauthorized, <String, Object?>{
          'error': 'invalid_credentials',
        });
      }
    }
    final token = _makeToken();
    final session = _WebGatewayAuthSession(
      token: token,
      source: source,
      deviceId: deviceId,
      deviceMacAddress: _string(body['device_mac_address'], ''),
      deviceName: _string(body['device_name'], ''),
      devicePlatform: _string(body['device_platform'], ''),
      osName: _string(body['os_name'], ''),
      osVersion: _string(body['os_version'], ''),
      browserName: _string(body['browser_name'], ''),
      browserVersion: _string(body['browser_version'], ''),
      webClientVersion: _string(body['web_client_version'], ''),
      locale: _string(body['locale'], ''),
      timezone: _string(body['timezone'], ''),
      screenClass: _string(body['screen_class'], ''),
      loginAt: DateTime.now().toUtc(),
      remoteAddress:
          (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
              ?.remoteAddress
              .address ??
          '',
      userAgent: request.headers[HttpHeaders.userAgentHeader] ?? '',
    );
    _authSessions[token] = session;
    _log(WebGatewayLogLevel.success, 'AUTH', '登录成功', session.toMetadata());
    return _json(HttpStatus.ok, <String, Object?>{
      'token': token,
      'expires_in': null,
      'profile': session.toMetadata(),
    });
  }

  Future<shelf.Response> _listSessions(
    shelf.Request request,
    _WebGatewayAuthSession auth,
  ) async {
    final page = math.max(
      1,
      int.tryParse(request.requestedUri.queryParameters['page'] ?? '') ?? 1,
    );
    final pageSize = math.min(
      50,
      math.max(
        1,
        int.tryParse(request.requestedUri.queryParameters['page_size'] ?? '') ??
            10,
      ),
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

  Future<shelf.Response> _createSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
  ) async {
    final body = await _readJsonBody(request);
    final templateId = _string(body['template_id'], 'default').trim();
    if (!_templateAllowed(templateId)) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'template_not_allowed',
      });
    }
    final requestedMode = _string(body['mode'], 'chat').trim();
    if (requestedMode == 'goal' &&
        !aiSessionGoalModeAllowedForTemplate(templateId)) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'goal_mode_not_available',
      });
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
    final mode = switch (requestedMode) {
      'plan' when _config.planModeEnabled => AiSessionMode.plan,
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
    final metadata = _metadataForRequest(auth, request, <String, Object?>{
      'created_via': 'web_api',
      'requested_template_id': templateId,
      'requested_mode': mode.storageValue,
      if (requestedModelKey.isNotEmpty)
        'requested_model_key': requestedModelKey,
    });
    final ok = await _sessionController.createSession(
      templateId: templateId,
      runtimeContext: _buildRuntimeContext(templateId: templateId),
      mode: mode,
      metadata: metadata,
      awaitStartHook: false,
    );
    if (!ok || _sessionController.currentSession == null) {
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'error': 'create_failed',
      });
    }
    var session = _sessionController.currentSession!;
    if (requestedModel != null) {
      await _sessionController.updateSessionLastUsedModel(
        session.id,
        providerConfigId: requestedModel.id,
        modelId: requestedModel.modelId,
      );
      session = _sessionController.sessions.firstWhere(
        (item) => item.id == session.id,
        orElse: () => session,
      );
    }
    final title = _string(body['title'], '').trim();
    if (title.isNotEmpty) {
      await _sessionController.renameSession(session.id, title);
      session = _sessionController.sessions.firstWhere(
        (item) => item.id == session.id,
        orElse: () => session,
      );
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
    });
  }

  Future<shelf.Response> _getSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    return _json(HttpStatus.ok, <String, Object?>{
      'session': await _sessionSummaryWithStoredMessageCount(
        session,
        includeDetails: true,
      ),
      'runtime': <String, Object?>{
        'send_phase': _sessionController.sendPhaseForSession(session.id).name,
        'can_stop': _sessionController.canStopResponding(session.id),
        'last_error': _sessionController.lastErrorMessageForSession(session.id),
      },
    });
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
    final hasKnowledgeBaseReference =
        body.containsKey(knowledgeBaseSessionToggleMetadataKey) ||
        body.containsKey('knowledgeBaseReferenceEnabled');
    if (!_config.sessionManagementEnabled &&
        (hasTitle || hasMode || hasFullAccess)) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'session_management_disabled',
      });
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    if (!hasTitle && !hasMode && !hasFullAccess && !hasKnowledgeBaseReference) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'session_patch_empty',
      });
    }
    var ok = true;
    var updated = session;
    final changed = <String, Object?>{};

    if (hasTitle) {
      final title = _string(body['title'], '').trim();
      if (title.isEmpty) {
        return _json(HttpStatus.badRequest, <String, Object?>{
          'error': 'title_required',
        });
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
        return _json(HttpStatus.forbidden, <String, Object?>{
          'error': 'plan_mode_disabled',
        });
      }
      if (mode == AiSessionMode.goal &&
          !aiSessionGoalModeAllowedForTemplate(session.templateId)) {
        return _json(HttpStatus.forbidden, <String, Object?>{
          'error': 'goal_mode_not_available',
        });
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
      final raw = body['full_access_permission'];
      final enabled = raw == true || raw == 'true' || raw == 1 || raw == '1';
      final updatedPermission = await _sessionController
          .updateSessionFullAccessPermission(session.id, enabled);
      ok = ok && updatedPermission;
      updated = _sessionController.sessions.firstWhere(
        (item) => item.id == session.id,
        orElse: () => updated.copyWith(fullAccessPermission: enabled),
      );
      changed['full_access_permission'] = enabled;
    }

    if (hasKnowledgeBaseReference) {
      final raw = body.containsKey(knowledgeBaseSessionToggleMetadataKey)
          ? body[knowledgeBaseSessionToggleMetadataKey]
          : body['knowledgeBaseReferenceEnabled'];
      final enabled = _boolishWebValue(raw);
      final updatedMetadata = await _sessionController.updateSessionMetadata(
        session.id,
        <String, Object?>{knowledgeBaseSessionToggleMetadataKey: enabled},
      );
      ok = ok && updatedMetadata;
      updated = _sessionController.sessions.firstWhere(
        (item) => item.id == session.id,
        orElse: () => updated,
      );
      changed[knowledgeBaseSessionToggleMetadataKey] = enabled;
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
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'session_management_disabled',
      });
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
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
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final limit = math.min(
      200,
      math.max(
        1,
        int.tryParse(request.requestedUri.queryParameters['limit'] ?? '') ?? 80,
      ),
    );
    final rawOffset = math.max(
      0,
      int.tryParse(request.requestedUri.queryParameters['offset'] ?? '') ?? 0,
    );
    final tail =
        _truthy(request.requestedUri.queryParameters['tail']) ||
        request.requestedUri.queryParameters['window'] == 'tail';
    final window = await _loadStoredMessageWindow(
      session,
      limit: limit,
      offset: rawOffset,
      tail: tail,
    );
    final lastMessage = window.messages.isEmpty ? null : window.messages.last;
    return _json(HttpStatus.ok, <String, Object?>{
      'session': _sessionSummary(
        session,
        messageCountOverride: window.total,
        lastMessageOverride: lastMessage,
      ),
      'items': window.messages.map(_messageJson).toList(growable: false),
      'offset': window.offset,
      'limit': window.limit,
      'total': window.total,
      'has_more': window.hasMore,
      'has_older': window.hasOlder,
      'has_newer': window.hasNewer,
      'window': window.window,
      'send_phase': _sessionController.sendPhaseForSession(session.id).name,
      'last_error': _sessionController.lastErrorMessageForSession(session.id),
      'pending_write_approval': _pendingWriteApprovalJson(session.id),
    });
  }

  Future<shelf.Response> _listTitleSourceMessages(
    shelf.Request _,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
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
      _log(
        WebGatewayLogLevel.warn,
        'SESSION',
        'Web 获取标题摘要消息源失败',
        <String, Object?>{
          'session_id': session.id,
          'error': '$error',
          'stack': '$stackTrace',
        },
      );
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'error': 'title_source_messages_failed',
        'message': '$error',
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

  /// 导出整会话为 JSONL 附件下载。复用 APP 端同一编码语义，确保下载后缀、
  /// MIME 与实际载荷格式一致。
  Future<shelf.Response> _exportSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final bodyText = encodeAiSessionToJsonlText(session: session);
    final safeTitle = (session.title.isEmpty ? 'session' : session.title)
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fff\-\.]+'), '_');
    final filename = normalizeJsonlExportFilename(
      '${safeTitle}_${session.id}.jsonl',
    );
    return shelf.Response.ok(
      bodyText,
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: 'application/x-ndjson; charset=utf-8',
        'content-disposition': _attachmentContentDisposition(filename),
        HttpHeaders.cacheControlHeader: 'no-store',
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
      silentLog('WebGateway', 'selectedSkill.readManifest', error, stack);
    }
    final manifest = (manifestContent ?? '').trim();
    final fallbackDescription = selected.description.trim();
    final manifestBody = manifest.isNotEmpty
        ? manifest
        : (fallbackDescription.isNotEmpty
              ? fallbackDescription
              : 'No SKILL.md content is available; honour the user intent implied by the skill name.');
    final reminder = StringBuffer()
      ..writeln(
        'The user explicitly selected the local skill "${selected.name}" for this request.',
      )
      ..writeln(
        'Follow the SKILL.md content below with the highest priority, overriding any conflicting default behaviour.',
      )
      ..writeln(
        "Apply the skill's guidance to the user's message for this turn; do not ignore this directive even if the skill seems unrelated.",
      )
      ..writeln()
      ..writeln(
        '<skill-manifest name="${escapeXmlAttribute(selected.name)}" path="${escapeXmlAttribute(selected.manifestPath)}">',
      )
      ..writeln(manifestBody)
      ..write('</skill-manifest>');
    return (
      reminder: reminder.toString(),
      metadata: <String, Object?>{
        'name': selected.name,
        'path': selected.manifestPath,
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
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final messageLimitWindow = await _loadStoredMessageWindow(
      session,
      limit: 1,
      tail: true,
    );
    final existingMessageCount = math.max(
      messageLimitWindow.total,
      session.displayMessages.length,
    );
    if (existingMessageCount >= _config.maxMessagesPerSession) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'session_message_limit_reached',
      });
    }
    final body = await _readJsonBody(request, maxBytes: 24 * 1024 * 1024);
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
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'conversation_mode_not_allowed',
      });
    }
    final attachments = await _materializeAttachments(
      session.id,
      body['attachments'],
    );
    if (attachments.isNotEmpty &&
        !_config.allowedMessageTypes.contains(
          WebGatewayMessageType.attachment,
        )) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'attachments_not_allowed',
      });
    }
    if (content.isNotEmpty &&
        !_config.allowedMessageTypes.contains(WebGatewayMessageType.text)) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'text_not_allowed',
      });
    }
    final model = _resolveModel(_string(body['model_key'], ''));
    if (model == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'model_not_configured',
      });
    }
    final selectedSkill = await _resolveWebSelectedSkill(
      body['selected_skill'],
    );
    if (selectedSkill.error != null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': selectedSkill.error,
      });
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
          ? Map<String, Object?>.from(body['creation_options'] as Map)
          : null,
    );
    if (!_modelSupportsConversationMode(model, conversationMode)) {
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
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'goal_options_invalid',
      });
    }
    if (goalStartOptions != null &&
        !aiSessionGoalModeAllowedForTemplate(session.templateId)) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'goal_mode_not_available',
      });
    }
    final allowQueuedGoalInterruption =
        body['allow_queued_goal_interruption'] == true ||
        body['allowQueuedGoalInterruption'] == true;
    if (session.hasActiveGoal && !allowQueuedGoalInterruption) {
      return _json(HttpStatus.conflict, <String, Object?>{
        'error': 'goal_active',
        'goal_state': session.goalState.toJson(),
      });
    }
    if (session.mode == AiSessionMode.goal &&
        goalStartOptions == null &&
        !allowQueuedGoalInterruption) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'goal_options_required',
      });
    }
    final hasKnowledgeBaseReferenceFlag =
        body.containsKey(knowledgeBaseSessionToggleMetadataKey) ||
        body.containsKey('knowledgeBaseReferenceEnabled');
    final knowledgeBaseReferenceEnabled = hasKnowledgeBaseReferenceFlag
        ? _boolishWebValue(
            body.containsKey(knowledgeBaseSessionToggleMetadataKey)
                ? body[knowledgeBaseSessionToggleMetadataKey]
                : body['knowledgeBaseReferenceEnabled'],
          )
        : session.metadata[knowledgeBaseSessionToggleMetadataKey] == true;
    // 单一发送通道 + 互斥：同一会话若已在 sending/responding/streaming/finalizing
    // 等任一非 idle 阶段，立刻拒绝新的 web 端发送，避免并发触发同一控制器。
    // 这与 AiSessionController._enqueueSessionOperation 内部排队一起构成两层防护：
    // 第一层让前端立即得到 409 反馈以禁用按钮，第二层兜底防止异常路径并发。
    final currentPhase = _sessionController.sendPhaseForSession(session.id);
    if (currentPhase != AiSendPhase.idle) {
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
    if (knowledgeBaseReferenceEnabled) {
      final knowledgeBaseController = _knowledgeBaseController;
      if (knowledgeBaseController == null) {
        return _json(HttpStatus.serviceUnavailable, <String, Object?>{
          'error': 'knowledge_base_unavailable',
          'message': '知识库服务未初始化。',
        });
      }
      try {
        final embeddingModel = knowledgeBaseController.resolveEmbeddingModel(
          _settingsController.aiModels,
        );
        final knowledgeBaseMetadata = await knowledgeBaseController
            .buildMessageAugmentation(
              query: content,
              enabled: true,
              embeddingModel: embeddingModel,
            );
        if (knowledgeBaseMetadata != null && knowledgeBaseMetadata.isNotEmpty) {
          userMessageMetadata[knowledgeBaseMessageMetadataKey] =
              knowledgeBaseMetadata;
        }
      } catch (error, stack) {
        silentLog('WebGateway', 'knowledgeBaseAugmentation', error, stack);
        return _json(HttpStatus.badGateway, <String, Object?>{
          'error': 'knowledge_base_augmentation_failed',
          'message': '$error',
        });
      }
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
            runtimeContext: _buildRuntimeContext(
              templateId: session.templateId,
              skippedInstructionIds: skippedInstructionIds,
            ),
            attachmentFilePaths: attachments,
            responseModalities: responseModalities,
            creationRequest: creationRequest,
            denyCommandRules: _settingsController.aiDenyCommandRules,
            requireWriteCommandConfirmation: session.fullAccessPermission
                ? false
                : _settingsController.aiWriteCommandConfirmationEnabled,
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
            silentLog('WebGateway', 'sendMessage.async', error, stack);
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
        'knowledge_base_reference_enabled': knowledgeBaseReferenceEnabled,
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
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'message_feedback_disabled',
      });
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final body = await _readJsonBody(request, maxBytes: 4096);
    if (!body.containsKey('feedback')) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'feedback_required',
      });
    }
    final rawFeedback = body['feedback'];
    final feedback = AiSessionMessageFeedback.fromStorage(rawFeedback);
    if (rawFeedback != null &&
        '$rawFeedback'.trim().isNotEmpty &&
        feedback == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'invalid_feedback',
      });
    }
    final message = await _loadMessageForWebOperation(session, messageId);
    if (message == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'message_not_found',
      });
    }
    if (!_messageSupportsWebFeedback(message)) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'message_feedback_not_supported',
      });
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
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'message_translation_disabled',
      });
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final message = await _loadMessageForWebOperation(session, messageId);
    if (message == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'message_not_found',
      });
    }
    if (!_messageSupportsWebTextAction(message)) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'message_translation_not_supported',
      });
    }
    final settings = _settingsController.aiTranslationSettings;
    if (!settings.enabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'translation_settings_disabled',
      });
    }
    final text = _webTranslationMessageText(message, settings);
    if (text == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'message_translation_not_supported',
      });
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
      silentLog('WebGateway', 'translate message', error, stack);
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'ok': false,
        'error': 'message_translation_failed',
        'message': '$error',
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
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final message = await _loadMessageForWebOperation(session, messageId);
    if (message == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'message_not_found',
      });
    }
    if (_ttsPlaybackService.isPlayingMessage(message.id)) {
      await _ttsPlaybackService.stop();
      return _json(HttpStatus.ok, <String, Object?>{
        'ok': true,
        'playback': _ttsPlaybackPayload(),
      });
    }
    if (!_config.readAloudEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'message_tts_disabled',
      });
    }
    if (!_messageSupportsWebTextAction(message)) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'message_tts_not_supported',
      });
    }
    final settings = _settingsController.aiTtsSettings;
    if (!settings.enabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'tts_settings_disabled',
      });
    }
    final text = _webTtsMessageText(message);
    if (text == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'message_tts_not_supported',
      });
    }
    final fallbackModel =
        _resolveModel(_lastModelKeyForSession(session) ?? '') ??
        _settingsController.selectedAiModel;
    unawaited(() async {
      try {
        await _ttsPlaybackService.speak(
          messageId: message.id,
          text: text,
          settings: settings,
          availableModels: _settingsController.aiModels,
          fallbackModel: fallbackModel,
        );
      } catch (error, stack) {
        silentLog('WebGateway', 'toggle message tts', error, stack);
      }
    }());
    await Future<void>.delayed(const Duration(milliseconds: 16));
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

  Future<shelf.Response> _regenerateMessage(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
    String messageId,
  ) async {
    if (!_config.regenerationEnabled) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'message_regeneration_disabled',
      });
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final message = await _loadMessageForWebOperation(session, messageId);
    if (message == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'message_not_found',
      });
    }
    if (!_messageSupportsWebRegeneration(message)) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'message_regeneration_not_supported',
      });
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
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'model_not_configured',
      });
    }
    unawaited(
      _sessionController
          .regenerateAssistantMessageVariant(
            sessionId: session.id,
            messageId: message.id,
            model: model,
            runtimeContext: _buildRuntimeContext(
              templateId: session.templateId,
            ),
            denyCommandRules: _settingsController.aiDenyCommandRules,
            requireWriteCommandConfirmation: session.fullAccessPermission
                ? false
                : _settingsController.aiWriteCommandConfirmationEnabled,
            confirmWriteCommand: (request) =>
                _confirmWebWriteCommand(session.id, request),
          )
          .catchError((Object error, StackTrace stack) {
            silentLog('WebGateway', 'regenerateMessage.async', error, stack);
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
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    if (!_sessionController.canStopResponding(session.id)) {
      return _json(HttpStatus.ok, <String, Object?>{
        'ok': false,
        'send_phase': _sessionController.sendPhaseForSession(session.id).name,
        'reason': 'not_running',
      });
    }
    _resolvePendingWriteApprovals(
      session.id,
      decision: BashCommandApprovalDecision.cancelled,
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
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
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
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
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
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final body = await _readJsonBody(request);
    final rawHasPending =
        body['has_pending'] ?? body['hasPending'] ?? body['pending'];
    final hasPendingQueue = rawHasPending == true || rawHasPending == 'true';
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
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final body = await _readJsonBody(request);
    final requestedModelKey = _string(body['model_key'], '').trim();
    final model = requestedModelKey.isNotEmpty
        ? _resolveModel(requestedModelKey)
        : _resolveModel(_lastModelKeyForSession(session) ?? '') ??
              _resolveModel('');
    if (model == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'model_not_configured',
      });
    }
    final currentPhase = _sessionController.sendPhaseForSession(session.id);
    if (currentPhase != AiSendPhase.idle) {
      return _json(HttpStatus.conflict, <String, Object?>{
        'error': 'session_busy',
        'send_phase': currentPhase.name,
      });
    }
    unawaited(
      _sessionController
          .resumeGoal(
            sessionId: session.id,
            model: model,
            runtimeContext: _buildRuntimeContext(
              templateId: session.templateId,
            ),
            denyCommandRules: _settingsController.aiDenyCommandRules,
            requireWriteCommandConfirmation: session.fullAccessPermission
                ? false
                : _settingsController.aiWriteCommandConfirmationEnabled,
            confirmWriteCommand: (request) =>
                _confirmWebWriteCommand(session.id, request),
          )
          .catchError((Object error, StackTrace stack) {
            silentLog('WebGateway', 'resumeGoal.async', error, stack);
            return false;
          }),
    );
    return _json(HttpStatus.accepted, <String, Object?>{
      'ok': true,
      'send_phase': AiSendPhase.sendingMessage.name,
    });
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
  /// 手动触发标题生成：接收用户选择的消息内容，调用 AI 生成摘要标题。
  Future<shelf.Response> _generateTitle(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_not_found',
      });
    }
    final body = await _readJsonBody(request);
    if (body.isEmpty) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'invalid_body',
      });
    }
    final content = _string(body['content'], '').trim();
    if (content.isEmpty) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'content_required',
      });
    }
    final requestedModelKey = _string(body['model_key'], '').trim();
    final requestedModel = requestedModelKey.isEmpty
        ? null
        : _resolveModel(requestedModelKey);
    if (requestedModelKey.isNotEmpty && requestedModel == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'model_not_configured',
      });
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
    } catch (error) {
      return _json(HttpStatus.internalServerError, <String, Object?>{
        'error': 'title_generation_failed',
        'detail': '$error',
      });
    }
  }

  /// ```
  Future<shelf.Response> _compactSession(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    Map<String, Object?> body = const <String, Object?>{};
    try {
      body = await _readJsonBody(request);
    } catch (error, stack) {
      silentLog(
        'web_message_platform_service',
        'read compact body',
        error,
        stack,
      );
    }
    final model = _resolveModel(_string(body['model_key'], ''));
    if (model == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'model_not_configured',
      });
    }
    final result = await _sessionController.requestManualCompaction(
      sessionId: session.id,
      model: model,
      runtimeContext: _buildRuntimeContext(templateId: session.templateId),
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
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final approval = _pendingWriteApprovals[approvalId];
    if (approval == null || approval.sessionId != session.id) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'write_approval_not_found',
      });
    }
    final body = await _readJsonBody(request);
    // 兼容历史 web 客户端：仅传 approved=true/false → 转为 approved/rejected。
    // 新客户端可显式传 decision: approved | rejected | dismissed。
    final rawDecision = body['decision'];
    final BashCommandApprovalDecision decision;
    if (rawDecision is String) {
      decision = BashCommandApprovalDecision.values.firstWhere(
        (d) => d.name == rawDecision,
        orElse: () => body['approved'] == true
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
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'write_approval_not_found',
      });
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
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
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
      // 2026-05-19 — 会话级启用开关：null 清除覆盖；true/false 立即生效。
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
    if (raw is int) return raw;
    if (raw is num && raw.isFinite) return raw.round();
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      return int.tryParse(trimmed);
    }
    return null;
  }

  /// 清除会话级节流覆盖，恢复到全局设置。
  Future<shelf.Response> _clearSessionThrottle(
    shelf.Request request,
    _WebGatewayAuthSession auth,
    String sessionId,
  ) async {
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
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
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
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
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'session_management_disabled',
      });
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
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
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'message_not_found_or_fork_failed',
      });
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
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
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
      return _json(HttpStatus.unauthorized, <String, Object?>{
        'error': 'unauthorized',
      });
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }

    String? lastSnapshotHash;
    Timer? throttleTimer;
    Timer? keepaliveTimer;
    var disposed = false;
    var snapshotInFlight = false;
    var snapshotQueued = false;

    Future<Map<String, Object?>> buildSnapshot(AiSession live) async {
      final liveMessages = live.displayMessages;
      final _WebSessionMessageWindow messageWindow;
      final liveLooksComplete =
          liveMessages.isNotEmpty &&
          live.messages.length >= live.statistics.totalMessageCount;
      if (liveLooksComplete) {
        messageWindow = _messageWindowFromDisplayMessages(
          liveMessages,
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
      // 2026-05-17 — 把当前会话生效的字符 / 卡片节流速率推给前端，让 Web
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
          // 2026-05-19 — 启用态：会话级 > 全局。前端据此渲染 Switch 与
          // 灰色胶囊。
          'enabled':
              throttleOverride?.enabled ??
              _settingsController.aiStreamThrottleEnabled,
          // 2026-05-19 — 会话历史上是否曾节流。胶囊可见性所需。
          'was_initially_throttled': _sessionController
              .sessionWasInitiallyThrottled(live.id),
          'duration_expired': _sessionController
              .sessionStreamThrottleDurationExpired(live.id),
          // 2026-05-24 — 字符吞吐 30s 桶（桶 0 = 当前秒），让 Web 端节流弹
          // 窗渲染和 App 端一致的柱状图。非流式 / 从未流式时也会回填全 0。
          'throughput_buckets': _sessionController
              .sessionStreamCharThroughputSnapshot(live.id),
        },
        'served_at': DateTime.now().toUtc().toIso8601String(),
      };
    }

    final controller = StreamController<List<int>>();

    void emit(String event, Object payload) {
      if (disposed || controller.isClosed) return;
      try {
        final body = jsonEncode(payload);
        final frame = 'event: $event\ndata: $body\n\n';
        controller.add(utf8.encode(frame));
      } catch (error, stack) {
        silentLog('WebGateway', 'sse.emit', error, stack);
      }
    }

    late void Function() dispose;

    void scheduleSnapshot() {
      if (disposed) return;
      throttleTimer?.cancel();
      throttleTimer = Timer(const Duration(milliseconds: 80), () async {
        if (disposed) return;
        if (snapshotInFlight) {
          snapshotQueued = true;
          return;
        }
        snapshotInFlight = true;
        try {
          final live = _findAuthorizedSession(auth, sessionId);
          if (live == null) {
            emit('session_deleted', <String, Object?>{
              'error': 'session_deleted_or_not_found',
              'session_id': sessionId,
              'served_at': DateTime.now().toUtc().toIso8601String(),
            });
            Future<void>.microtask(dispose);
            return;
          }
          final snapshot = await buildSnapshot(live);
          if (disposed) return;
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
          final goalStateSig = jsonEncode(sessionPayload['goal_state']);
          final messagesPayload = snapshot['messages'] as List;
          final hash =
              '${sessionPayload['title']}|${sessionPayload['updated_at']}|${sessionPayload['message_count']}|${sessionPayload['last_model_key']}|${sessionPayload['full_access_permission']}|${snapshot['send_phase']}|${snapshot['last_error']}|${(snapshot['pending_write_approval'] as Map?)?['id'] ?? ''}|goal=$goalStateSig|throttle=${throttlePayload?['chars_per_second'] ?? 0}:${throttlePayload?['cards_per_second'] ?? 0}:${throttlePayload?['has_session_override'] ?? false}:${throttlePayload?['duration_expired'] ?? false}:$bucketsSig|tokens=$tokenStatsSig|messages=${_messagePayloadWindowSignature(messagesPayload)}';
          if (hash == lastSnapshotHash) return;
          lastSnapshotHash = hash;
          emit('snapshot', snapshot);
        } catch (error, stack) {
          silentLog('WebGateway', 'sse.snapshot', error, stack);
        } finally {
          snapshotInFlight = false;
          if (!disposed && snapshotQueued) {
            snapshotQueued = false;
            scheduleSnapshot();
          }
        }
      });
    }

    void controllerListener() => scheduleSnapshot();

    dispose = () {
      if (disposed) return;
      disposed = true;
      throttleTimer?.cancel();
      keepaliveTimer?.cancel();
      _sessionController.removeListener(controllerListener);
      _sessionController.streamThrottleOverrideSignal.removeListener(
        controllerListener,
      );
      if (!controller.isClosed) {
        controller.close();
      }
      _activeSseSubscriptions = math.max(0, _activeSseSubscriptions - 1);
    };

    _sessionController.addListener(controllerListener);
    _sessionController.streamThrottleOverrideSignal.addListener(
      controllerListener,
    );
    keepaliveTimer = startSafePeriodicTimer(
      const Duration(seconds: 25),
      (_) {
        if (disposed || controller.isClosed) return;
        try {
          controller.add(utf8.encode(':keepalive\n\n'));
        } catch (error, stack) {
          silentLog('WebGateway', 'sse.keepalive', error, stack);
        }
      },
      onError: (error, stack) {
        silentLog('WebGateway', 'sse.keepalive.timer', error, stack);
      },
    );

    controller.onCancel = dispose;
    _activeSseSubscriptions += 1;

    // 立即推送首帧，避免前端等待第一次 notifyListeners。
    Future<void>.microtask(() {
      lastSnapshotHash = null;
      scheduleSnapshot();
    });

    return shelf.Response.ok(
      controller.stream,
      headers: <String, String>{
        HttpHeaders.contentTypeHeader: 'text/event-stream; charset=utf-8',
        HttpHeaders.cacheControlHeader: 'no-store, no-transform',
        HttpHeaders.connectionHeader: 'keep-alive',
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
      return _json(HttpStatus.unauthorized, <String, Object?>{
        'error': 'unauthorized',
      });
    }
    final session = _findAuthorizedSession(auth, sessionId);
    if (session == null) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'session_deleted_or_not_found',
      });
    }
    final requested = request.requestedUri.queryParameters['path'] ?? '';
    if (requested.isEmpty) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'missing_path',
      });
    }
    final whitelist = _collectSessionAssetPaths(session);
    if (!whitelist.contains(requested)) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'asset_not_in_whitelist',
      });
    }
    final file = File(requested);
    if (!await file.exists()) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'asset_missing',
      });
    }
    final stat = await file.stat();
    // 简单上限: 单文件 ≤ 512 MiB, 覆盖常见生成视频同时防止误暴露超大文件。
    const maxBytes = 512 * 1024 * 1024;
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
      final suffixLength = int.tryParse(rawEnd);
      if (suffixLength == null || suffixLength <= 0) {
        return null;
      }
      start = math.max(0, totalBytes - suffixLength);
      end = totalBytes - 1;
    } else {
      start = int.tryParse(rawStart) ?? -1;
      end = rawEnd.isEmpty ? totalBytes - 1 : int.tryParse(rawEnd) ?? -1;
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
      String pick(String queryKey, String headerKey, String fallback) {
        final queryValue = qp[queryKey]?.trim();
        if (queryValue != null && queryValue.isNotEmpty) return queryValue;
        final headerValue = request.headers[headerKey]?.trim();
        if (headerValue != null && headerValue.isNotEmpty) return headerValue;
        return fallback;
      }

      final deviceId = pick(
        'device_id',
        'x-openhand-device-id',
        'anonymous-web',
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
        remoteAddress:
            (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address ??
            '',
        userAgent: request.headers[HttpHeaders.userAgentHeader] ?? '',
      );
    }
    final fromHeader = _authorize(request);
    if (fromHeader != null) return fromHeader;
    final token = request.requestedUri.queryParameters['token']?.trim() ?? '';
    if (token.isEmpty) return null;
    return _authSessions[token];
  }

  Future<shelf.Response> _listLogs(shelf.Request request) async {
    final offset = math.max(
      0,
      int.tryParse(request.requestedUri.queryParameters['offset'] ?? '') ?? 0,
    );
    final limit = math.min(
      2000,
      math.max(
        1,
        int.tryParse(request.requestedUri.queryParameters['limit'] ?? '') ??
            _config.logConfig.lazyReadPageSize,
      ),
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
    final body = await _readJsonBody(request);
    final target = _string(body['target'], 'all').trim().toLowerCase();
    final expiredOnly = body['expired_only'] as bool? ?? false;
    final logs = target == 'logs' || target == 'all';
    final uploads = target == 'uploads' || target == 'all';
    if (!logs && !uploads) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'invalid_cleanup_target',
      });
    }
    final result = await cleanupArtifacts(
      logs: logs,
      uploads: uploads,
      expiredOnly: expiredOnly,
    );
    return _json(HttpStatus.ok, result.toJson());
  }

  Future<shelf.Response> _cleanupHistoryPayload() async {
    return _json(HttpStatus.ok, <String, Object?>{
      'items': _cleanupHistory.reversed
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'total': _cleanupHistory.length,
      'max_items': 50,
    });
  }

  Future<shelf.Response> _exportLogs() async {
    final body = await exportLogBundleJson();
    return shelf.Response.ok(
      body,
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        HttpHeaders.cacheControlHeader: 'no-store',
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
    final dir = _resolveWorkspacePath(relative);
    if (dir == null || !await FileSystemEntity.isDirectory(dir)) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'directory_not_found',
      });
    }
    final root = _workspaceDirectoryPath;
    final entries = Directory(dir).listSync(followLinks: false)
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
      final stat = entry.statSync();
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
    return _json(HttpStatus.ok, <String, Object?>{
      'root': root,
      'path': _relativeWorkspacePath(dir),
      'items': items,
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
    final filePath = _resolveWorkspacePath(relative);
    if (filePath == null || !await FileSystemEntity.isFile(filePath)) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'file_not_found',
      });
    }
    if (!_workspaceExtensionAllowed(filePath, _workspaceAllowedExtensions())) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'file_extension_not_allowed',
      });
    }
    final stat = await File(filePath).stat();
    if (stat.size > _config.workspaceFileMaxBytes) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'file_too_large',
        'limit_bytes': _config.workspaceFileMaxBytes,
      });
    }
    final bytes = await File(filePath).readAsBytes();
    if (_looksBinary(bytes)) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'binary_file_not_supported',
      });
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
    final filePath = _resolveWorkspacePath(relative);
    if (filePath == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'path_outside_workspace',
      });
    }
    if (!_workspaceExtensionAllowed(filePath, _workspaceAllowedExtensions())) {
      return _json(HttpStatus.forbidden, <String, Object?>{
        'error': 'file_extension_not_allowed',
      });
    }
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    final stat = await file.stat();
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
    final body = await _readJsonBody(request, maxBytes: 16 * 1024);
    final relative = _string(body['path'], '');
    if (relative.trim().isEmpty || relative == '.' || relative == '/') {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'path_required',
      });
    }
    final dirPath = _resolveWorkspacePath(relative);
    if (dirPath == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'path_outside_workspace',
      });
    }
    final type = await FileSystemEntity.type(dirPath, followLinks: false);
    if (type == FileSystemEntityType.file) {
      return _json(HttpStatus.conflict, <String, Object?>{
        'error': 'file_already_exists',
      });
    }
    await Directory(dirPath).create(recursive: true);
    final stat = await Directory(dirPath).stat();
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
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'path_required',
      });
    }
    final resolved = _resolveWorkspacePath(relative);
    if (resolved == null) {
      return _json(HttpStatus.badRequest, <String, Object?>{
        'error': 'path_outside_workspace',
      });
    }
    final type = await FileSystemEntity.type(resolved, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return _json(HttpStatus.notFound, <String, Object?>{
        'error': 'not_found',
      });
    }
    if (type == FileSystemEntityType.directory) {
      // 不递归：让用户明确清空再删（避免一次误调清掉整棵子树）。
      final entries = Directory(resolved).listSync(followLinks: false);
      if (entries.isNotEmpty) {
        return _json(HttpStatus.conflict, <String, Object?>{
          'error': 'directory_not_empty',
        });
      }
      await Directory(resolved).delete();
    } else {
      if (!_workspaceExtensionAllowed(
        resolved,
        _workspaceAllowedExtensions(),
      )) {
        return _json(HttpStatus.forbidden, <String, Object?>{
          'error': 'file_extension_not_allowed',
        });
      }
      await File(resolved).delete();
    }
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
      final deviceId =
          request.headers['x-openhand-device-id'] ?? 'anonymous-web';
      return _WebGatewayAuthSession(
        token: 'anonymous',
        source: WebGatewayLoginSource.fromStorage(
          request.headers['x-openhand-source'] ?? 'WEB_PC',
        ),
        deviceId: deviceId,
        deviceMacAddress: request.headers['x-openhand-device-mac'] ?? '',
        deviceName: request.headers['x-openhand-device-name'] ?? '',
        devicePlatform: request.headers['x-openhand-device-platform'] ?? '',
        osName: request.headers['x-openhand-os-name'] ?? '',
        osVersion: request.headers['x-openhand-os-version'] ?? '',
        browserName: request.headers['x-openhand-browser-name'] ?? '',
        browserVersion: request.headers['x-openhand-browser-version'] ?? '',
        webClientVersion:
            request.headers['x-openhand-web-client-version'] ?? '',
        locale: request.headers['x-openhand-locale'] ?? '',
        timezone: request.headers['x-openhand-timezone'] ?? '',
        screenClass: request.headers['x-openhand-screen-class'] ?? '',
        loginAt: DateTime.now().toUtc(),
        remoteAddress:
            (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address ??
            '',
        userAgent: request.headers[HttpHeaders.userAgentHeader] ?? '',
      );
    }
    final authHeader = request.headers[HttpHeaders.authorizationHeader] ?? '';
    if (!authHeader.startsWith('Bearer ')) return null;
    final token = authHeader.substring('Bearer '.length).trim();
    if (token.isEmpty) return null;
    return _authSessions[token];
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
      silentLog('WebGateway', 'load message for web operation', error, stack);
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
    };
  }

  bool _messageHasWebMultimediaPayload(AiSessionMessage message) {
    final metadata = message.metadata;
    if (_nonEmptyList(metadata['attachments'])) return true;
    if (_intFromWebValue(metadata['attachment_count'], 0) > 0) return true;
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
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = '$value'.trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  int _intFromWebValue(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.round();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
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
    final createdAt = DateTime.now().toUtc();
    final timeoutMs = _settingsController.aiWriteConfirmationTimeoutMs;
    final completer = Completer<BashCommandApprovalDecision>();
    final approval = _WebWriteApprovalRequest(
      id: '${createdAt.microsecondsSinceEpoch}-${_nextWriteApprovalId++}',
      sessionId: sessionId,
      command: request.command,
      workingDirectory: request.workingDirectory,
      isWriteCommand: request.isWriteCommand,
      createdAt: createdAt,
      expiresAt: createdAt.add(Duration(milliseconds: timeoutMs)),
      completer: completer,
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
    final timer = Timer(Duration(milliseconds: timeoutMs), () {
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
      _sessionController.clearSessionAwaitingApproval(sessionId);
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

  void _resolvePendingWriteApprovals(
    String sessionId, {
    required BashCommandApprovalDecision decision,
  }) {
    for (final approval in _pendingWriteApprovals.values.toList()) {
      if (approval.sessionId == sessionId) {
        _completePendingWriteApproval(
          approval,
          decision: decision,
          source: 'session_stop',
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
    return buildLegacyWebGatewayRequestMetadata(
      authMetadata: auth.toMetadata(),
      requestMethod: request.method,
      requestPath: request.requestedUri.path,
      requestId: _nextLogId,
      extras: extra,
    );
  }

  Map<String, Object?> _webContext(Map<String, Object?> metadata) {
    final raw = metadata[webGatewayMetadataKey];
    if (raw is Map) return Map<String, Object?>.from(raw);
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

  String? _lastModelKeyForSession(AiSession session) {
    for (final message in session.displayMessages.reversed) {
      final direct = _allowedModelKeyFromValue(message.metadata['model_key']);
      if (direct != null) return direct;
      final context = _webContext(message.metadata);
      final nested = _allowedModelKeyFromValue(context['model_key']);
      if (nested != null) return nested;
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

  /// 2026-06-08 — 每次序列化会话时，若 statistics.cacheHitRatio 为 0 或 null
  /// 但累积 cache 数据明确有值，直接用 SessionCacheHitTrend.fromSession（与
  /// APP 端同源）重算，保证 `getSession` / SSE 快照始终携带正确的缓存命中率。
  Map<String, Object?> _ensureCacheHitStats(AiSession session) {
    final stats = Map<String, Object?>.from(session.statistics.toJson());
    final existingRatio = stats['cache_hit_ratio'];
    final hasExisting =
        existingRatio is num &&
        (existingRatio is double ? existingRatio > 0.0001 : existingRatio > 0);
    final cacheRead = (stats['cache_read_tokens'] is int)
        ? stats['cache_read_tokens'] as int
        : 0;
    final prompt = (stats['total_prompt_tokens'] is int)
        ? stats['total_prompt_tokens'] as int
        : 0;
    if (cacheRead <= 0 || prompt <= 0) return stats;
    final trendSchemaCurrent = _cacheHitTrendUsesRoundStarterSchema(
      stats['cache_hit_trend_points'],
    );
    if (hasExisting && trendSchemaCurrent) return stats;
    final protocol = _lastModelProtocolForSession(session);
    final claudeStyle =
        protocol != null && protocol.trim().toLowerCase() == 'claude';
    final trend = SessionCacheHitTrend.fromSession(
      session,
      claudeStyle: claudeStyle,
    );
    final display = trend.displayData(
      SessionCacheHitDisplayMode.excludeExtremeMisses,
    );
    final trendPoints = trend.points
        .map((point) => point.toJson())
        .toList(growable: false);
    stats['cache_hit_ratio'] = display.averageHitRatio;
    stats['cache_hit_trend_points'] = trendPoints;
    stats['cache_hit_trend_excluded_count'] =
        trend.points.length - display.trend.points.length;
    return stats;
  }

  bool _cacheHitTrendUsesRoundStarterSchema(Object? value) {
    if (value is! List || value.isEmpty) return false;
    for (final item in value) {
      final Map<String, Object?>? point = switch (item) {
        final Map<String, Object?> typed => typed,
        final Map raw => Map<String, Object?>.from(raw),
        _ => null,
      };
      if (point == null ||
          !point.containsKey(
            AiSessionCacheHitTrendPoint.starterOriginJsonKey,
          )) {
        return false;
      }
    }
    return true;
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
      if (session.messages.isNotEmpty && session.messages.length >= rawTotal) {
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
        final page = await _sessionController.store.loadMessages(
          session.id,
          limit: scanLimit,
          offset: rawOffset,
        );
        return _boundedStoredMessageWindow(
          session: session,
          storedMessages: page.messages,
          rawOffset: rawOffset,
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
      silentLog('WebGateway', 'load stored message window', error, stack);
      return _messageWindowFromDisplayMessages(
        session.displayMessages,
        limit: safeLimit,
        offset: offset,
        tail: tail,
      );
    }
  }

  _WebSessionMessageWindow _boundedStoredMessageWindow({
    required AiSession session,
    required List<AiSessionMessage> storedMessages,
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
      session.messages,
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

    final displayMessages = session
        .copyWith(messages: mergedMessages)
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

  Future<Map<String, Object?>> _sessionSummaryWithStoredMessages(
    AiSession session, {
    bool includeDetails = false,
  }) async {
    final window = await _loadStoredMessageWindow(
      session,
      limit: _sessionSummaryMessageWindowSize,
      tail: true,
    );
    final liveDisplayMessages = session.displayMessages;
    final lastMessage = liveDisplayMessages.isNotEmpty
        ? liveDisplayMessages.last
        : (window.messages.isEmpty ? null : window.messages.last);
    return _sessionSummary(
      session,
      includeDetails: includeDetails,
      messageCountOverride: math.max(window.total, liveDisplayMessages.length),
      lastMessageOverride: lastMessage,
    );
  }

  Future<Map<String, Object?>> _sessionSummaryWithStoredMessageCount(
    AiSession session, {
    bool includeDetails = false,
  }) async {
    var total = session.statistics.totalMessageCount;
    try {
      total = math.max(
        total,
        await _sessionController.store.countMessages(session.id),
      );
    } catch (error, stack) {
      silentLog('WebGateway', 'count stored messages', error, stack);
    }
    final liveDisplayMessages = session.messages.isEmpty
        ? const <AiSessionMessage>[]
        : session.displayMessages;
    return _sessionSummary(
      session,
      includeDetails: includeDetails,
      messageCountOverride: math.max(total, liveDisplayMessages.length),
      lastMessageOverride: liveDisplayMessages.isEmpty
          ? null
          : liveDisplayMessages.last,
    );
  }

  Map<String, Object?> _sessionSummary(
    AiSession session, {
    bool includeDetails = false,
    int? messageCountOverride,
    AiSessionMessage? lastMessageOverride,
  }) {
    final context = _webContext(session.metadata);
    final needsDisplayMessages =
        messageCountOverride == null || lastMessageOverride == null;
    final displayMessages = needsDisplayMessages
        ? session.displayMessages
        : const <AiSessionMessage>[];
    final last =
        lastMessageOverride ??
        (displayMessages.isEmpty ? null : displayMessages.last);
    final lastModelKey = _lastModelKeyForSession(session);
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
      'message_count': messageCountOverride ?? displayMessages.length,
      'statistics': _ensureCacheHitStats(session),
      'total_tokens': session.statistics.totalTokens,
      'total_prompt_tokens': session.statistics.totalPromptTokens,
      'total_completion_tokens': session.statistics.totalCompletionTokens,
      'tool_message_count': session.statistics.toolMessageCount,
      'compression_point_count': session.statistics.compressionPointCount,
      'last_message_preview': last == null
          ? ''
          : _truncate(last.content.replaceAll('\n', ' '), 160),
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
      'latest_compression_point': session.latestCompressionPoint == null
          ? null
          : _messageJson(session.latestCompressionPoint!),
    });
    return summary;
  }

  Map<String, Object?> _messageJson(AiSessionMessage message) {
    final usage = message.usage;
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
      'metadata': message.metadata,
    };
  }

  String _messagePayloadWindowSignature(List<Object?> messages) {
    if (messages.isEmpty) {
      return '0';
    }

    String itemSignature(Object? value) {
      final Map<String, Object?>? message = switch (value) {
        final Map<String, Object?> typed => typed,
        final Map raw => Map<String, Object?>.from(raw),
        _ => null,
      };
      if (message == null) {
        return '?';
      }
      final content = message['content'];
      final contentText = content is String ? content : '';
      final contentLength = contentText.length;
      final contentHead = contentText.length <= 48
          ? contentText
          : contentText.substring(0, 48);
      final contentTail = contentText.length <= 24
          ? contentText
          : contentText.substring(contentText.length - 24);
      return '${message['id']}:${message['role']}:${message['kind']}:$contentLength:$contentHead:$contentTail:${message['character_count'] ?? 0}';
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

  AiSessionRuntimeContext _buildRuntimeContext({
    required String templateId,
    Set<String> skippedInstructionIds = const <String>{},
  }) {
    final now = DateTime.now().toLocal();
    final mcpToolCatalogsByServerName = <String, McpToolCatalog>{
      for (final server in _mcpController.servers)
        server.name: _mcpController.toolCatalogFor(server.name),
    };
    return AiSessionRuntimeContext(
      localeTag: _settingsController.locale.toLanguageTag(),
      appVersion: _appInfo.version,
      appBuildNumber: _appInfo.buildNumber,
      settingsFilePath: _settingsController.settingsFilePath,
      skillsStoragePath: _settingsController.skillsStoragePath,
      mcpServersFilePath: _settingsController.mcpServersFilePath,
      userMemoryFilePath: _settingsController.userMemoryFilePath,
      compressionThresholdChars:
          _settingsController.aiMessageCompressionThresholdChars,
      messageContentFormat: _settingsController.aiMessageContentFormat,
      htmlRenderFallback: _settingsController.aiHtmlRenderFallback,
      htmlContentRichness: _settingsController.aiHtmlContentRichness,
      appThemeBrightness: _resolveEffectiveBrightness(),
      appThemePresetName: _settingsController.themePreset.storageValue,
      appThemePrimaryColor:
          '#${_settingsController.themePreset.seedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      fallbackTitleMaxCharacters:
          _settingsController.aiFallbackTitleMaxCharacters,
      generatedTitleMaxCharacters:
          _settingsController.aiGeneratedTitleMaxCharacters,
      minimumMeaningfulTitleCharacters:
          _settingsController.aiMinimumMeaningfulTitleCharacters,
      minimumMeaningfulLatinTitleWords:
          _settingsController.aiMinimumMeaningfulLatinTitleWords,
      memoryEnabled: _settingsController.memoryEnabled,
      memoryEntries: _settingsController.memoryEnabled
          ? _memoryController.entries
          : const [],
      templateId: templateId,
      platformName: Platform.operatingSystem,
      workingDirectory: OpenHandPaths.applicationDirectoryPath(),
      todayLocalDate:
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      timeZoneName: now.timeZoneName,
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
          ? _mcpController.servers
          : _mcpController.servers
                .where(
                  (server) =>
                      _config.allowedMcpServerNames.contains(server.name),
                )
                .toList(growable: false),
      mcpToolCatalogsByServerName: mcpToolCatalogsByServerName,
      builtinToolConfigs:
          webGatewayIsDenyAllSelection(_config.allowedBuiltinToolNames)
          ? const []
          : _settingsController.builtinToolConfigs
                .where(
                  (tool) =>
                      _config.allowedBuiltinToolNames.isEmpty ||
                      _config.allowedBuiltinToolNames.contains(
                        tool.effectiveName,
                      ),
                )
                .toList(growable: false),
      autoTitleEnabled: _settingsController.aiAutoTitleEnabled,
      autoTitleFetchMode: _settingsController.aiAutoTitleFetchMode,
      autoTitleMaxRetryCount: _settingsController.aiAutoTitleMaxRetryCount,
      streamMaxCharsPerSecond: _settingsController.aiStreamMaxCharsPerSecond,
      streamMaxMessageCardsPerSecond:
          _settingsController.aiStreamMaxMessageCardsPerSecond,
      streamThrottleEnabled: _settingsController.aiStreamThrottleEnabled,
      streamThrottleAutoMode: _settingsController.aiStreamThrottleAutoMode,
      streamThrottleDurationSeconds:
          _settingsController.aiStreamThrottleDurationSeconds,
      skippedInstructionIds: skippedInstructionIds,
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
    );
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
        result.add(
          _AllowedWebModel(
            key: key,
            providerId: provider.id,
            providerLabel: provider.providerLabel,
            protocolLabel: provider.protocolType.storageValue,
            modelId: modelId,
            label: '${provider.providerLabel} / $modelId',
            supportsAttachments: resolved.resolvedSupportsAttachments,
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
            providerDefaultTitleModelKey: providerDefaultTitleModelKey,
            isGlobalDefaultTitleModel:
                profile.isGlobalDefaultTitleModel ||
                (legacyGlobalDefaultTitleModelId.isNotEmpty &&
                    modelId == legacyGlobalDefaultTitleModelId),
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
    if (raw is! List || raw.isEmpty) return const <String>[];
    final output = <String>[];
    final dir = Directory(p.join(_uploadCacheDirectoryPath, sessionId));
    await dir.create(recursive: true);
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, Object?>.from(item);
      final name = _safeFileName(_string(map['name'], 'attachment.bin'));
      final data = _string(map['data_base64'], '').trim();
      if (data.isEmpty) continue;
      final bytes = base64Decode(data);
      final file = File(
        p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}-$name'),
      );
      await file.writeAsBytes(bytes);
      output.add(file.path);
    }
    return output;
  }

  String get _uploadCacheDirectoryPath =>
      p.join(_cacheDirectoryPath, 'message_gateway', 'uploads');

  Future<_CleanupStats> _cleanupUploadCache({required bool expiredOnly}) async {
    final root = Directory(_uploadCacheDirectoryPath);
    if (!await root.exists()) return const _CleanupStats();
    if (!expiredOnly) {
      final stats = await _measureDirectory(root);
      await root.delete(recursive: true);
      return stats.copyWith(deletedDirectories: stats.deletedDirectories + 1);
    }
    final cutoff = DateTime.now().subtract(
      Duration(days: _config.uploadCacheRetentionDays),
    );
    final entities = await root
        .list(recursive: true, followLinks: false)
        .toList();
    entities.sort((a, b) => b.path.length.compareTo(a.path.length));
    var stats = const _CleanupStats();
    for (final entity in entities) {
      try {
        final stat = await entity.stat();
        if (stat.modified.isAfter(cutoff)) continue;
        if (entity is File) {
          stats += _CleanupStats(deletedFiles: 1, bytesFreed: stat.size);
          await entity.delete();
        } else if (entity is Directory) {
          final isEmpty = await entity.list(followLinks: false).isEmpty;
          if (!isEmpty) continue;
          stats += const _CleanupStats(deletedDirectories: 1);
          await entity.delete();
        }
      } catch (error, stack) {
        silentLog(
          'web_message_platform_service',
          'cleanup upload cache',
          error,
          stack,
        );
      }
    }
    return stats + await _enforceUploadCacheMaxBytes();
  }

  Future<_CleanupStats> _enforceUploadCacheMaxBytes() async {
    final root = Directory(_uploadCacheDirectoryPath);
    if (!await root.exists()) return const _CleanupStats();
    final files = <File>[];
    var totalBytes = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        totalBytes += stat.size;
        files.add(entity);
      } catch (error, stack) {
        silentLog(
          'web_message_platform_service',
          'stat upload cache ${entity.path}',
          error,
          stack,
        );
      }
    }
    if (totalBytes <= _config.uploadCacheMaxBytes) {
      return const _CleanupStats();
    }
    files.sort(
      (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
    );
    var stats = const _CleanupStats();
    var remainingBytes = totalBytes;
    for (final file in files) {
      if (remainingBytes <= _config.uploadCacheMaxBytes) break;
      try {
        final stat = await file.stat();
        await file.delete();
        remainingBytes -= stat.size;
        stats += _CleanupStats(deletedFiles: 1, bytesFreed: stat.size);
      } catch (error, stack) {
        silentLog(
          'web_message_platform_service',
          'enforce upload cache max bytes',
          error,
          stack,
        );
      }
    }
    return stats;
  }

  Future<_CleanupStats> _measureDirectory(Directory directory) async {
    var stats = const _CleanupStats();
    if (!await directory.exists()) return stats;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      try {
        final stat = await entity.stat();
        if (entity is File) {
          stats += _CleanupStats(deletedFiles: 1, bytesFreed: stat.size);
        } else if (entity is Directory) {
          stats += const _CleanupStats(deletedDirectories: 1);
        }
      } catch (error, stack) {
        silentLog(
          'web_message_platform_service',
          'measure ${entity.path}',
          error,
          stack,
        );
      }
    }
    return stats;
  }

  /// 读取并解析 JSON 请求体；超过 [maxBytes] 抛 `FormatException`，
  /// 由外层中间件转 500。空 body 返回 `{}`。
  Future<Map<String, Object?>> _readJsonBody(
    shelf.Request request, {
    int maxBytes = 1024 * 1024,
  }) async {
    final chunks = <int>[];
    await for (final chunk in request.read()) {
      chunks.addAll(chunk);
      if (chunks.length > maxBytes) {
        throw const FormatException('Request body is too large.');
      }
    }
    if (chunks.isEmpty) return <String, Object?>{};
    final decoded = jsonDecode(utf8.decode(chunks));
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    return <String, Object?>{};
  }

  /// 构造 JSON 响应。`Cache-Control: no-store` 避免浏览器/CDN 缓存敏感数据。
  shelf.Response _json(int statusCode, Map<String, Object?> payload) {
    final body = jsonEncode(payload);
    return shelf.Response(
      statusCode,
      body: body,
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        HttpHeaders.cacheControlHeader: 'no-store',
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
      final html = await rootBundle.loadString('assets/web/index.html');
      return _html(html);
    } catch (e, stack) {
      silentLog(
        'web_gateway_service',
        '_serveWebShell.missing_bundle',
        e,
        stack,
      );
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
      silentLog('web_gateway_service', '_serveBundleAsset:$key', e, stack);
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
    if (!key.startsWith('assets/web/chunks/') &&
        !key.startsWith('assets/web/assets/')) {
      return false;
    }
    return RegExp(r'-[A-Za-z0-9_-]{8,}\.[^.]+$').hasMatch(p.basename(key));
  }

  /// 极简 MIME 推断，只覆盖 Vite 构建会产生的扩展名。
  String _guessContentType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
      return 'application/javascript; charset=utf-8';
    }
    if (lower.endsWith('.css')) return 'text/css; charset=utf-8';
    if (lower.endsWith('.json')) return 'application/json; charset=utf-8';
    if (lower.endsWith('.svg')) return 'image/svg+xml';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.woff2')) return 'font/woff2';
    if (lower.endsWith('.woff')) return 'font/woff';
    if (lower.endsWith('.ttf')) return 'font/ttf';
    if (lower.endsWith('.map')) return 'application/json; charset=utf-8';
    return 'application/octet-stream';
  }

  String _attachmentContentDisposition(String filename) {
    final ascii = filename
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
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
    if (_memoryLogs.length > 5000) {
      _memoryLogs.removeRange(0, _memoryLogs.length - 5000);
    }
    if (!_logStreamController.isClosed) {
      _logStreamController.add(entry);
    }
    if (_config.loggingEnabled) {
      unawaited(_fileLogger.write(entry, _config.logConfig));
    }
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
    return 'Web 服务启动失败: $error';
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

  String? _resolveWorkspacePath(String rawPath) {
    final root = _workspaceDirectoryPath;
    final normalizedInput = rawPath.trim().replaceAll('\\', '/');
    if (normalizedInput.startsWith('/')) return null;
    final resolved = p.normalize(p.join(root, normalizedInput));
    if (resolved == root || p.isWithin(root, resolved)) return resolved;
    return null;
  }

  String _relativeWorkspacePath(String absolutePath) {
    final root = _workspaceDirectoryPath;
    if (absolutePath == root) return '';
    return p.relative(absolutePath, from: root).replaceAll('\\', '/');
  }

  Set<String> _workspaceAllowedExtensions() {
    return _config.workspaceFileAllowedExtensions
        .map(_normalizeWorkspaceExtension)
        .where((extension) => extension.isNotEmpty)
        .toSet();
  }

  Set<String> _workspaceExtensionsForQuery(String? raw) {
    final configured = _workspaceAllowedExtensions();
    final requested = (raw ?? '')
        .split(',')
        .map(_normalizeWorkspaceExtension)
        .where((extension) => extension.isNotEmpty)
        .toSet();
    if (requested.isEmpty) return configured;
    if (configured.isEmpty) return requested;
    return requested.where(configured.contains).toSet();
  }

  bool _workspaceExtensionAllowed(String path, Set<String> allowedExtensions) {
    if (allowedExtensions.isEmpty) return true;
    final extension = _normalizeWorkspaceExtension(p.extension(path));
    return allowedExtensions.contains(extension);
  }

  bool _looksBinary(List<int> bytes) {
    final sampleLength = math.min(bytes.length, 4096);
    for (var i = 0; i < sampleLength; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  Future<void> _refreshProcessDiagnosticsIfStale() async {
    final now = DateTime.now();
    final previous = _processDiagnosticsAt;
    if (previous != null && now.difference(previous).inSeconds < 2) return;
    _processDiagnosticsAt = now;
    try {
      if (Platform.isMacOS) {
        _processDiagnostics = await _sampleMacProcessDiagnostics();
      } else if (Platform.isLinux) {
        _processDiagnostics = await _sampleLinuxProcessDiagnostics();
      }
    } catch (error, stack) {
      silentLog(
        'web_message_platform_service',
        'process diagnostics',
        error,
        stack,
      );
    }
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
      final parts = '${ps.stdout}'.trim().split(RegExp(r'\s+'));
      if (parts.isNotEmpty) cpuPercent = double.tryParse(parts[0]);
      if (parts.length > 1) threadCount = int.tryParse(parts[1]);
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
      final status = await File('/proc/self/status').readAsLines();
      for (final line in status) {
        if (line.startsWith('Threads:')) {
          threadCount = int.tryParse(line.split(RegExp(r'\s+')).last);
        }
        if (line.startsWith('VmSwap:')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length > 1) {
            swapBytes = (int.tryParse(parts[1]) ?? 0) * 1024;
          }
        }
      }
    } catch (error, stack) {
      silentLog(
        'web_message_platform_service',
        'read proc status',
        error,
        stack,
      );
    }
    int? fileHandleCount;
    try {
      fileHandleCount = Directory('/proc/self/fd').listSync().length;
    } catch (error, stack) {
      silentLog(
        'web_message_platform_service',
        'count file handles',
        error,
        stack,
      );
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
      final processStat = await File('/proc/self/stat').readAsString();
      final processEnd = processStat.lastIndexOf(')');
      if (processEnd < 0) return null;
      final processFields = processStat
          .substring(processEnd + 1)
          .trim()
          .split(RegExp(r'\s+'));
      if (processFields.length <= 12) return null;
      final userTicks = int.tryParse(processFields[11]);
      final systemTicks = int.tryParse(processFields[12]);
      if (userTicks == null || systemTicks == null) return null;

      final statLines = await File('/proc/stat').readAsLines();
      final cpuLine = statLines.firstWhere(
        (line) => line.startsWith('cpu '),
        orElse: () => '',
      );
      if (cpuLine.isEmpty) return null;
      var totalTicks = 0;
      for (final part in cpuLine.trim().split(RegExp(r'\s+')).skip(1)) {
        totalTicks += int.tryParse(part) ?? 0;
      }
      if (totalTicks <= 0) return null;
      return _LinuxCpuSample(
        processTicks: userTicks + systemTicks,
        totalTicks: totalTicks,
      );
    } catch (error, stack) {
      silentLog(
        'web_message_platform_service',
        'read linux cpu sample',
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
  final value = raw?.trim().toLowerCase() ?? '';
  return value == '1' || value == 'true' || value == 'yes' || value == 'tail';
}

class _RequestObservation {
  const _RequestObservation({
    required this.atMs,
    required this.method,
    required this.path,
    required this.statusCode,
    required this.durationMs,
    required this.requestBytes,
    required this.responseBytes,
  });

  final int atMs;
  final String method;
  final String path;
  final int statusCode;
  final int durationMs;
  final int requestBytes;
  final int responseBytes;
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
    required this.supportsImageGeneration,
    required this.supportsVideoGeneration,
    required this.supportsAudioGeneration,
    required this.supportsTextTitleGeneration,
    required this.supportsEmbeddings,
    required this.providerDefaultTitleModelKey,
    required this.isGlobalDefaultTitleModel,
  });

  final String key;
  final String providerId;
  final String providerLabel;
  final String protocolLabel;
  final String modelId;
  final String label;
  final bool supportsAttachments;
  final bool supportsImageGeneration;
  final bool supportsVideoGeneration;
  final bool supportsAudioGeneration;
  final bool supportsTextTitleGeneration;
  final bool supportsEmbeddings;
  final String? providerDefaultTitleModelKey;
  final bool isGlobalDefaultTitleModel;
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

String _truncate(String value, int maxChars) {
  if (value.length <= maxChars) return value;
  return '${value.substring(0, maxChars)}...';
}

String _safeFileName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  if (sanitized.isEmpty) return 'attachment.bin';
  return sanitized.length > 120 ? sanitized.substring(0, 120) : sanitized;
}

String _normalizeWorkspaceExtension(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  final withoutLeadingDot = trimmed.startsWith('.')
      ? trimmed.substring(1)
      : trimmed;
  final safe = withoutLeadingDot.replaceAll(RegExp(r'[^a-z0-9_+-]'), '');
  return safe.isEmpty ? '' : '.$safe';
}
