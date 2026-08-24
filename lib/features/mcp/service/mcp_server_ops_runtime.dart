import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../shared/net/bounded_http_request.dart';
import '../../../shared/net/http_redirect_utils.dart';
import '../../../shared/net/http_response_utils.dart';
import '../../../shared/net/http_status_utils.dart';
import '../../../shared/util/argument_guards.dart';
import '../../../shared/util/async_concurrency.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/date_time_format.dart';
import '../../../shared/util/duration_bounds.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/path_safety.dart';
import '../../../shared/util/physical_path_safety.dart';
import '../../../shared/util/sensitive_data.dart';
import '../../../shared/util/serial_task_queue.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/timer_safety.dart';
import '../mcp_errors.dart';
import '../model/mcp_http_headers.dart';
import '../model/mcp_server_ops.dart';
import 'mcp_ops_endpoint.dart';

typedef McpOpsToolListProvider = List<McpOpsToolDefinition> Function();
typedef McpOpsToolInvoker =
    Future<McpOpsToolInvocationResult> Function(
      McpOpsToolDefinition tool,
      Map<String, Object?> arguments,
      McpOpsToolInvocationContext context,
    );
typedef McpOpsApprovalGate =
    Future<bool> Function(
      McpOpsApprovalRequest request,
      Future<void> cancelSignal,
    );
typedef McpOpsAuditSink = void Function(McpOpsAuditEntry entry);
typedef McpOpsSnapshotSink = void Function(McpOpsRuntimeSnapshot snapshot);

class McpOpsToolInvocationContext {
  const McpOpsToolInvocationContext({
    required this.invocationId,
    required this.cancelSignal,
    required this.deadline,
    this.workspaceRoot = '',
  });

  final String invocationId;
  final Future<void> cancelSignal;
  final DateTime deadline;
  final String workspaceRoot;
}

const int _mcpOpsRequestBodyMaxBytes = 4 * kBytesPerMiB;
const Duration _mcpOpsRequestBodyIdleTimeout = Duration(seconds: 10);
const Duration _mcpOpsRequestBodyTotalTimeout = Duration(seconds: 30);
const int _mcpOpsMaxConcurrentRequests = 64;
const int _mcpOpsMaxBatchItems = 128;
const Duration _mcpOpsRequestProcessingTimeout = Duration(minutes: 2);
const Duration _mcpOpsWorkspacePathCheckTimeout = Duration(seconds: 2);
const int _mcpOpsMaxWorkspaceArgumentDepth = 64;
const int _mcpOpsMaxWorkspaceArgumentNodes = 4096;
const int _mcpOpsMaxWorkspacePathValues = 256;

final RegExp _mcpOpsArgumentWordBoundary = RegExp(r'([a-z0-9])([A-Z])');
final RegExp _mcpOpsArgumentKeySeparator = RegExp(r'[^a-z0-9]+');
const Set<String> _mcpOpsPathArgumentWords = <String>{
  'path',
  'paths',
  'file',
  'files',
  'filename',
  'filenames',
  'dir',
  'dirs',
  'directory',
  'directories',
};

class _McpOpsPathArgumentScan {
  const _McpOpsPathArgumentScan({required this.values, required this.valid});

  final List<String> values;
  final bool valid;
}

_McpOpsPathArgumentScan _scanMcpOpsPathArguments(Object? arguments) {
  final values = <String>[];
  var visitedNodes = 0;
  var valid = true;

  void visit(Object? value, String key, int depth) {
    if (!valid) return;
    visitedNodes += 1;
    if (depth > _mcpOpsMaxWorkspaceArgumentDepth ||
        visitedNodes > _mcpOpsMaxWorkspaceArgumentNodes) {
      valid = false;
      return;
    }
    if (value is Map) {
      for (final entry in value.entries) {
        visit(entry.value, '${entry.key}', depth + 1);
        if (!valid) return;
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        visit(item, key, depth + 1);
        if (!valid) return;
      }
      return;
    }
    if (value is! String || !_mcpOpsArgumentKeyLooksLikePath(key)) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    values.add(trimmed);
    if (values.length > _mcpOpsMaxWorkspacePathValues) valid = false;
  }

  visit(arguments, '', 0);
  return _McpOpsPathArgumentScan(
    values: List<String>.unmodifiable(values),
    valid: valid,
  );
}

bool _mcpOpsArgumentKeyLooksLikePath(String key) {
  final normalized = key
      .replaceAllMapped(
        _mcpOpsArgumentWordBoundary,
        (match) => '${match.group(1)}_${match.group(2)}',
      )
      .toLowerCase();
  final words = normalized
      .split(_mcpOpsArgumentKeySeparator)
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (normalized == 'cwd' ||
      normalized == 'workspace' ||
      normalized == 'workspace_root') {
    return true;
  }
  if (words.isEmpty) return false;
  return _mcpOpsPathArgumentWords.contains(words.last);
}

/// 有界读取 MCP 请求体。失败时由响应头关闭连接；此处不提前取消 Shelf 请求流，
/// 避免套接字在 408/413 响应写出前被中断。
Future<String> readBoundedMcpOpsRequestBody(
  Stream<List<int>> stream, {
  required int maxBytes,
  required Duration idleTimeout,
  required Duration totalTimeout,
}) => readBoundedByteStreamText(
  stream,
  maxBytes: maxBytes,
  idleTimeout: idleTimeout,
  totalTimeout: totalTimeout,
  cancelOnFailure: false,
);

class McpOpsConnectivityResult {
  const McpOpsConnectivityResult({
    required this.ok,
    required this.message,
    required this.checkedAt,
  });

  final bool ok;
  final String message;
  final DateTime checkedAt;
}

class McpServerOpsRuntime {
  McpServerOpsRuntime({
    required McpOpsToolListProvider toolListProvider,
    required McpOpsToolInvoker toolInvoker,
    required McpOpsApprovalGate approvalGate,
    required McpOpsAuditSink auditSink,
    required McpOpsSnapshotSink snapshotSink,
    int maxRequestBodyBytes = _mcpOpsRequestBodyMaxBytes,
    Duration requestBodyIdleTimeout = _mcpOpsRequestBodyIdleTimeout,
    Duration requestBodyTotalTimeout = _mcpOpsRequestBodyTotalTimeout,
    int maxConcurrentRequests = _mcpOpsMaxConcurrentRequests,
    int maxBatchItems = _mcpOpsMaxBatchItems,
  }) : _toolListProvider = toolListProvider,
       _toolInvoker = toolInvoker,
       _approvalGate = approvalGate,
       _auditSink = auditSink,
       _snapshotSink = snapshotSink,
       _maxRequestBodyBytes = maxRequestBodyBytes,
       _requestBodyIdleTimeout = requestBodyIdleTimeout,
       _requestBodyTotalTimeout = requestBodyTotalTimeout,
       _maxConcurrentRequests = maxConcurrentRequests,
       _maxBatchItems = maxBatchItems {
    requirePositiveIntAtMost(
      maxRequestBodyBytes,
      _mcpOpsRequestBodyMaxBytes,
      'maxRequestBodyBytes',
    );
    requirePositiveDurationAtMost(
      requestBodyIdleTimeout,
      _mcpOpsRequestBodyIdleTimeout,
      'requestBodyIdleTimeout',
    );
    requirePositiveDurationAtMost(
      requestBodyTotalTimeout,
      _mcpOpsRequestBodyTotalTimeout,
      'requestBodyTotalTimeout',
    );
    requirePositiveIntAtMost(
      maxConcurrentRequests,
      _mcpOpsMaxConcurrentRequests,
      'maxConcurrentRequests',
    );
    requirePositiveIntAtMost(
      maxBatchItems,
      _mcpOpsMaxBatchItems,
      'maxBatchItems',
    );
  }

  static const String _protocolVersion = kMcpProtocolVersion;
  static const String _serverName = 'OpenHand MCP Server';
  static const String _serverVersion = '1.0.0';
  static const Duration _startupTimeout = Duration(seconds: 10);
  static const Duration _shutdownTimeout = Duration(seconds: 5);
  static const Duration _connectivityTimeout = Duration(seconds: 3);
  static const int _maxConnectivityResponseBytes = kBytesPerMiB;
  static const Duration _sseKeepAliveInterval = Duration(seconds: 15);
  static const int _sseKeepAliveTicks = 480;
  static const int _maxSseStreams = 32;

  /// SSE 槽位「已占位但生成器未启动」的宽限期。超过即视为客户端在订阅响应体
  /// 前就断开，回收槽位。
  static const Duration _sseReservationGrace = Duration(seconds: 30);
  static const int _maxSessionIds = 1024;
  static const int _latencyWindow = 512;
  static const int _rateWindowSeconds = 60;
  static const String _connectionInfoContextKey = 'shelf.io.connection_info';
  static const String _requestCancellationContextKey =
      'openhand.mcp_ops.request_cancellation';
  static const Map<String, String> _responseHeaders = <String, String>{
    'cache-control': kCacheControlNoStore,
    'x-content-type-options': 'nosniff',
  };

  /// 纯文本响应头：错误与状态回执统一走这一份，避免 charset 在各分支漂移。
  static const Map<String, String> _plainTextResponseHeaders = <String, String>{
    ..._responseHeaders,
    kContentTypeHeaderName: kTextPlainUtf8ContentType,
  };

  final McpOpsToolListProvider _toolListProvider;
  final McpOpsToolInvoker _toolInvoker;
  final McpOpsApprovalGate _approvalGate;
  final McpOpsAuditSink _auditSink;
  final McpOpsSnapshotSink _snapshotSink;
  final int _maxRequestBodyBytes;
  final Duration _requestBodyIdleTimeout;
  final Duration _requestBodyTotalTimeout;
  final int _maxConcurrentRequests;
  final int _maxBatchItems;

  HttpServer? _server;
  McpOpsConfig _config = const McpOpsConfig();
  McpOpsRuntimeSnapshot _snapshot = const McpOpsRuntimeSnapshot();
  final SerialTaskQueue _lifecycleQueue = SerialTaskQueue();
  final Stopwatch _runtimeStopwatch = Stopwatch()..start();
  final List<Duration> _requestTimes = <Duration>[];
  final List<int> _latencies = <int>[];
  final Set<_McpOpsActiveRequest> _activeRequestTokens =
      <_McpOpsActiveRequest>{};
  final Set<Object> _activeSseTokens = <Object>{};

  /// 已占用 SSE 槽位但生成器尚未开始执行的 token → 占位时刻。
  ///
  /// 响应流只有被 listen 后才会触发取消回调；客户端若在订阅响应体之前
  /// 断开（或响应头写失败），仍需通过宽限期回收槽位。
  final Map<Object, Duration> _reservedSseTokens = <Object, Duration>{};
  int _requestTotal = 0;
  int _blockedTotal = 0;
  int _failedTotal = 0;
  int _inboundBytes = 0;
  int _outboundBytes = 0;
  int _fileMutationCount = 0;
  final Map<String, int> _ipDistribution = <String, int>{};
  final Map<String, int> _clientDistribution = <String, int>{};
  final Map<String, int> _requestDistribution = <String, int>{};
  final Map<String, int> _protocolDistribution = <String, int>{};
  final Set<String> _sessionIds = <String>{};
  bool _isShuttingDown = false;
  // 按 UTC 分钟汇总所有请求，为趋势和延迟图提供完整数据。
  final Map<DateTime, _McpOpsMinuteBucket> _trafficBuckets =
      <DateTime, _McpOpsMinuteBucket>{};

  McpOpsRuntimeSnapshot get snapshot => _snapshot;
  bool get isRunning => _server != null;

  void hydrateMetrics(McpOpsRuntimeSnapshot snapshot) {
    final ipDistribution = normalizeMcpOpsMetricDistribution(
      snapshot.ipDistribution,
    );
    final clientDistribution = normalizeMcpOpsMetricDistribution(
      snapshot.clientDistribution,
    );
    final requestDistribution = normalizeMcpOpsMetricDistribution(
      snapshot.requestDistribution,
    );
    final protocolDistribution = normalizeMcpOpsMetricDistribution(
      snapshot.protocolDistribution,
    );
    final trafficSeries =
        snapshot.trafficSeries.length <= mcpOpsTrafficWindowMinutes
        ? List<McpOpsTrafficSample>.unmodifiable(snapshot.trafficSeries)
        : List<McpOpsTrafficSample>.unmodifiable(
            snapshot.trafficSeries.skip(
              snapshot.trafficSeries.length - mcpOpsTrafficWindowMinutes,
            ),
          );
    _snapshot = snapshot.asOfflinePersistedSnapshot().copyWith(
      ipDistribution: ipDistribution,
      clientDistribution: clientDistribution,
      requestDistribution: requestDistribution,
      protocolDistribution: protocolDistribution,
      trafficSeries: trafficSeries,
    );
    _requestTotal = snapshot.requestTotal;
    _blockedTotal = snapshot.blockedTotal;
    _failedTotal = snapshot.failedTotal;
    _inboundBytes = snapshot.inboundBytes;
    _outboundBytes = snapshot.outboundBytes;
    _fileMutationCount = snapshot.fileMutationCount;
    _ipDistribution
      ..clear()
      ..addAll(ipDistribution);
    _clientDistribution
      ..clear()
      ..addAll(clientDistribution);
    _requestDistribution
      ..clear()
      ..addAll(requestDistribution);
    _protocolDistribution
      ..clear()
      ..addAll(protocolDistribution);
    _trafficBuckets
      ..clear()
      ..addEntries(
        trafficSeries.map(
          (sample) => MapEntry(
            _minuteStart(sample.minute),
            _McpOpsMinuteBucket.fromSample(sample),
          ),
        ),
      );
    _snapshotSink(_snapshot);
  }

  void clearMetrics({DateTime? startUtc, DateTime? endUtc}) {
    final clearsAll = startUtc == null && endUtc == null;
    if (clearsAll) {
      _requestTimes.clear();
      _latencies.clear();
      _requestTotal = 0;
      _blockedTotal = 0;
      _failedTotal = 0;
      _inboundBytes = 0;
      _outboundBytes = 0;
      _fileMutationCount = 0;
      _ipDistribution.clear();
      _clientDistribution.clear();
      _requestDistribution.clear();
      _protocolDistribution.clear();
      _trafficBuckets.clear();
      _publishMetrics();
      return;
    }
    _trafficBuckets.removeWhere(
      (minute, _) =>
          isDateTimeInUtcRange(minute, startUtc: startUtc, endUtc: endUtc),
    );
    _setSnapshot(
      _snapshot.copyWith(
        trafficSeries: _trafficSnapshot()
            .where((sample) {
              return !isDateTimeInUtcRange(
                sample.minute,
                startUtc: startUtc,
                endUtc: endUtc,
              );
            })
            .toList(growable: false),
      ),
    );
  }

  Future<void> start(McpOpsConfig config) {
    if (_isShuttingDown) return Future<void>.value();
    return _runLifecycleLocked(() => _startUnlocked(config));
  }

  Future<void> _startUnlocked(McpOpsConfig config) async {
    if (_isShuttingDown) return;
    if (_server != null) {
      _config = config;
      if (_listenerMatches(config)) {
        return;
      }
      await _restartUnlocked(config);
      return;
    }
    _config = config;
    _setSnapshot(
      _snapshot.copyWith(
        lifecycle: McpOpsLifecycleState.starting,
        clearErrorMessage: true,
      ),
    );
    try {
      // 流式 HTTP 在同一端点承载 JSON-RPC、SSE 和会话关闭请求。
      // 统一分发根路径、/mcp 与 /mcp/，避免客户端路径差异导致 404。
      final router = Router(notFoundHandler: _dispatchMcp)
        ..get('/health', _health);
      final handler = const shelf.Pipeline()
          .addMiddleware(_telemetryMiddleware())
          .addHandler(router.call);
      final serverFuture = shelf_io.serve(
        handler,
        mcpOpsListenAddress(config.listenHost),
        config.listenPort,
      );
      try {
        _server = await serverFuture.timeout(_startupTimeout);
      } on TimeoutException {
        unawaited(_closeLateServer(serverFuture));
        rethrow;
      }
      if (_isShuttingDown) {
        await _stopUnlocked();
        return;
      }
      final bound = _server!;
      _setSnapshot(
        _snapshot.copyWith(
          lifecycle: McpOpsLifecycleState.running,
          boundHost: config.listenHost,
          boundPort: bound.port,
          startedAt: DateTime.now().toUtc(),
          clearErrorMessage: true,
        ),
      );
    } catch (error) {
      _server = null;
      _setSnapshot(
        _snapshot.copyWith(
          lifecycle: McpOpsLifecycleState.failed,
          errorMessage: mcpFailureMessage(
            error,
            fallback: 'MCP 运维服务启动失败，请稍后重试。',
          ),
          clearBound: true,
          clearStartedAt: true,
        ),
      );
      rethrow;
    }
  }

  Future<void> stop() {
    return _runLifecycleLocked(_stopUnlocked);
  }

  Future<void> shutdown() {
    _isShuttingDown = true;
    return _runLifecycleLocked(_stopUnlocked);
  }

  Future<void> _stopUnlocked() async {
    final server = _server;
    _server = null;
    _cancelActiveRequests();
    if (server == null) {
      _setSnapshot(
        _snapshot.copyWith(
          lifecycle: McpOpsLifecycleState.stopped,
          clearBound: true,
          clearStartedAt: true,
        ),
      );
      return;
    }
    _setSnapshot(_snapshot.copyWith(lifecycle: McpOpsLifecycleState.stopping));
    try {
      await server.close(force: true).timeout(_shutdownTimeout);
    } finally {
      _activeSseTokens.clear();
      _reservedSseTokens.clear();
      _setSnapshot(
        _snapshot.copyWith(
          lifecycle: McpOpsLifecycleState.stopped,
          clearBound: true,
          clearStartedAt: true,
          activeRequests: 0,
          activeStreams: 0,
          currentConnections: 0,
        ),
      );
    }
  }

  Future<void> restart(McpOpsConfig config) {
    if (_isShuttingDown) return Future<void>.value();
    return _runLifecycleLocked(() => _restartUnlocked(config));
  }

  Future<void> _restartUnlocked(McpOpsConfig config) async {
    if (_isShuttingDown) return;
    _setSnapshot(
      _snapshot.copyWith(lifecycle: McpOpsLifecycleState.restarting),
    );
    await _stopUnlocked();
    if (_isShuttingDown) return;
    await _startUnlocked(config);
  }

  void updateConfig(McpOpsConfig config) {
    _config = config;
  }

  bool _listenerMatches(McpOpsConfig config) {
    final boundPort = _snapshot.boundPort;
    if (boundPort == null || boundPort != config.listenPort) {
      return false;
    }
    final boundHost = _snapshot.boundHost ?? _config.listenHost;
    return _normalizeListenHostForCompare(boundHost) ==
        _normalizeListenHostForCompare(config.listenHost);
  }

  String _normalizeListenHostForCompare(String host) {
    final normalized = host.trim().toLowerCase();
    if (mcpOpsIsWildcardHost(normalized)) return '*';
    return normalized;
  }

  Future<void> _runLifecycleLocked(Future<void> Function() action) {
    return _lifecycleQueue.enqueue(action);
  }

  void _cancelActiveRequests() {
    for (final request in _activeRequestTokens) {
      request.cancel();
    }
  }

  Future<void> _closeLateServer(Future<HttpServer> serverFuture) async {
    try {
      final server = await serverFuture;
      await server.close(force: true).timeout(_shutdownTimeout);
    } catch (_) {
      // 启动调用方已收到超时结果。
    }
  }

  Future<McpOpsConnectivityResult> testConnectivity() async {
    final checkedAt = DateTime.now().toUtc();
    final port = _snapshot.boundPort;
    if (_server == null || port == null) {
      final result = McpOpsConnectivityResult(
        ok: false,
        message: 'MCP server is not running.',
        checkedAt: checkedAt,
      );
      _applyConnectivityResult(result);
      return result;
    }
    final host = mcpOpsClientHost(_snapshot.boundHost ?? _config.listenHost);
    // 通过 initialize 握手探测真实流式端点，而非仅检查健康接口。
    final uri = Uri(scheme: 'http', host: host, port: port, path: '/mcp');
    final deadline = MonotonicDeadline(
      _connectivityTimeout,
      timeoutMessage: 'MCP 运维连通性测试超时。',
    );
    final client = HttpClient()..connectionTimeout = _connectivityTimeout;
    try {
      final request = await openHttpClientRequestBounded(
        () => client.postUrl(uri),
        timeout: deadline.remaining(),
        timeoutMessage: 'MCP 连通性请求打开超时。',
      );
      request.headers
        ..set(HttpHeaders.contentTypeHeader, kApplicationJsonMimeType)
        ..set(
          HttpHeaders.acceptHeader,
          '$kApplicationJsonMimeType, $kTextEventStreamMimeType',
        )
        ..set(kMcpProtocolVersionHeader, _protocolVersion)
        ..set('x-openhand-client', 'OpenHand Self-Test');
      final token = nullIfBlank(_config.authToken);
      if (_config.requireAuthToken && token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.add(utf8.encode(jsonEncode(_initializeProbePayload)));
      final response = await closeHttpClientRequestBounded(
        request,
        timeout: deadline.remaining(),
        timeoutMessage: 'MCP 连通性响应头获取超时。',
      );
      final remaining = deadline.remaining();
      final body = await readBoundedHttpResponseText(
        response,
        maxBytes: _maxConnectivityResponseBytes,
        idleTimeout: remaining,
        totalTimeout: remaining,
      );
      final ok = response.statusCode == HttpStatus.ok && _isInitializeAck(body);
      final result = McpOpsConnectivityResult(
        ok: ok,
        message: ok
            ? 'OK $uri'
            : 'HTTP ${response.statusCode}: ${_clipConnectivityBody(body)}',
        checkedAt: checkedAt,
      );
      _applyConnectivityResult(result);
      return result;
    } catch (error, stack) {
      silentLog('mcp_server_ops_runtime', '测试 MCP 运维连通性', error, stack);
      final result = McpOpsConnectivityResult(
        ok: false,
        message: mcpFailureMessage(error, fallback: 'MCP 运维连通性测试失败，请稍后重试。'),
        checkedAt: checkedAt,
      );
      _applyConnectivityResult(result);
      return result;
    } finally {
      deadline.stop();
      client.close(force: true);
    }
  }

  static const Map<String, Object?> _initializeProbePayload = <String, Object?>{
    'jsonrpc': '2.0',
    'id': 'openhand-self-test',
    'method': 'initialize',
    'params': <String, Object?>{
      'protocolVersion': _protocolVersion,
      'capabilities': <String, Object?>{},
      'clientInfo': <String, Object?>{
        'name': 'OpenHand Self-Test',
        'version': _serverVersion,
      },
    },
  };

  bool _isInitializeAck(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return false;
      final result = decoded['result'];
      return result is Map && result['protocolVersion'] != null;
    } catch (_) {
      return false;
    }
  }

  String _clipConnectivityBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '(empty body)';
    const maxChars = 200;
    return clipTextByCodeUnits(trimmed, maxChars);
  }

  shelf.Middleware _telemetryMiddleware() {
    return (innerHandler) {
      return (request) async {
        if (_activeRequests >= _maxConcurrentRequests) {
          _recordBlocked(
            request,
            inboundBytes: 0,
            reason: 'Concurrent request limit exceeded.',
            method: 'request/concurrency',
          );
          return shelf.Response(
            HttpStatus.tooManyRequests,
            body: 'Too many concurrent OpenHand MCP requests.',
            headers: const <String, String>{
              ..._plainTextResponseHeaders,
              HttpHeaders.connectionHeader: kConnectionClose,
            },
          );
        }
        final requestToken = _McpOpsActiveRequest();
        final requestStopwatch = Stopwatch()..start();
        _activeRequestTokens.add(requestToken);
        _setSnapshot(
          _snapshot.copyWith(
            activeRequests: _activeRequests,
            currentConnections: _currentConnections,
            memoryRssBytes: _currentRss(),
          ),
        );
        try {
          return await innerHandler(
            request.change(
              context: <String, Object>{
                ...request.context,
                _requestCancellationContextKey: requestToken.cancelSignal,
              },
            ),
          );
        } finally {
          requestToken.cancel();
          final durationMs = requestStopwatch.elapsedMilliseconds;
          _latencies.add(durationMs);
          if (_latencies.length > _latencyWindow) {
            _latencies.removeRange(0, _latencies.length - _latencyWindow);
          }
          _recordTrafficLatency(durationMs);
          _activeRequestTokens.remove(requestToken);
          final running = _server != null;
          _setSnapshot(
            _snapshot.copyWith(
              activeRequests: running ? _activeRequests : 0,
              currentConnections: running ? _currentConnections : 0,
              avgLatencyMs: _averageLatency(),
              p95LatencyMs: _p95Latency(),
              memoryRssBytes: _currentRss(),
            ),
          );
        }
      };
    };
  }

  shelf.Response _health(shelf.Request request) {
    final payload = <String, Object?>{
      'ok': true,
      'server': _serverName,
      'state': _snapshot.lifecycle.name,
      'started_at': _snapshot.startedAt?.toIso8601String(),
      'bound_port': _snapshot.boundPort,
      'request_total': _requestTotal,
    };
    return _jsonResponse(payload);
  }

  shelf.Response _options(shelf.Request request) {
    return shelf.Response(HttpStatus.noContent, headers: _responseHeaders);
  }

  /// 流式 HTTP 统一入口，使 `/`、`/mcp` 和 `/mcp/` 行为一致。
  FutureOr<shelf.Response> _dispatchMcp(shelf.Request request) {
    if (_isBrowserInitiatedRequest(request)) {
      _recordBlocked(
        request,
        inboundBytes: 0,
        reason: 'Browser-originated MCP requests are not accepted.',
        method: 'browser/request',
      );
      return shelf.Response(
        HttpStatus.forbidden,
        body: 'Browser-originated MCP requests are not accepted.',
        headers: const <String, String>{
          ..._plainTextResponseHeaders,
          HttpHeaders.connectionHeader: kConnectionClose,
        },
      );
    }
    switch (request.method) {
      case 'POST':
        return _jsonRpc(request);
      case 'GET':
        return _sseStream(request);
      case 'DELETE':
        return _terminateSession(request);
      case 'OPTIONS':
        return _options(request);
      case 'HEAD':
        return shelf.Response(
          HttpStatus.noContent,
          headers: <String, String>{
            ..._responseHeaders,
            ..._sessionHeaders(request),
          },
        );
      default:
        return shelf.Response(
          HttpStatus.methodNotAllowed,
          body: 'Method not allowed on the OpenHand MCP endpoint',
          headers: const <String, String>{
            ..._responseHeaders,
            'allow': 'GET, POST, DELETE, OPTIONS, HEAD',
            kContentTypeHeaderName: kTextPlainUtf8ContentType,
          },
        );
    }
  }

  bool _isBrowserInitiatedRequest(shelf.Request request) {
    return nullIfBlank(request.headers['origin']) != null ||
        nullIfBlank(request.headers['sec-fetch-site']) != null ||
        nullIfBlank(request.headers['sec-fetch-mode']) != null;
  }

  shelf.Response _terminateSession(shelf.Request request) {
    const method = 'session/delete';
    if (!_requestAllowed(request, method, 0)) {
      return shelf.Response(
        HttpStatus.forbidden,
        body: 'Request blocked by OpenHand policy',
        headers: const <String, String>{..._plainTextResponseHeaders},
      );
    }
    _recordLifecycle(
      request,
      method: method,
      started: Stopwatch()..start(),
      inboundBytes: 0,
      outboundBytes: 0,
    );
    final providedSessionId = nullIfBlank(request.headers[kMcpSessionIdHeader]);
    final validSessionId =
        providedSessionId != null &&
            isValidMcpHttpHeaderValue(providedSessionId)
        ? providedSessionId
        : null;
    if (validSessionId != null) {
      _sessionIds.remove(validSessionId);
      _publishConnectionSnapshot();
    }
    return shelf.Response(
      HttpStatus.noContent,
      headers: <String, String>{
        ..._responseHeaders,
        kMcpProtocolVersionHeader: _protocolVersion,
        if (validSessionId != null) kMcpSessionIdHeader: validSessionId,
      },
    );
  }

  shelf.Response _sseStream(shelf.Request request) {
    const method = 'stream/get';
    final started = Stopwatch()..start();
    if (!_requestAllowed(request, method, 0)) {
      return shelf.Response(
        HttpStatus.forbidden,
        body: 'Request blocked by OpenHand policy',
        headers: const <String, String>{..._plainTextResponseHeaders},
      );
    }
    // 成功计数前先执行流上限，避免拒绝请求被重复计为成功和阻止。
    _reapStaleSseReservations();
    if (_activeSseStreams >= _maxSseStreams) {
      _recordBlocked(
        request,
        inboundBytes: 0,
        reason: 'SSE stream limit exceeded.',
        method: method,
      );
      return shelf.Response(
        HttpStatus.tooManyRequests,
        body: 'Too many OpenHand MCP streams',
        headers: const <String, String>{..._plainTextResponseHeaders},
      );
    }
    _recordLifecycle(
      request,
      method: method,
      started: started,
      inboundBytes: 0,
      outboundBytes: 0,
    );
    final streamToken = Object();
    _activeSseTokens.add(streamToken);
    _reservedSseTokens[streamToken] = _runtimeStopwatch.elapsed;
    _publishConnectionSnapshot();
    return shelf.Response.ok(
      _sseKeepAliveStream(streamToken),
      headers: <String, String>{
        ..._responseHeaders,
        ..._sessionHeaders(request),
        kContentTypeHeaderName: kTextEventStreamUtf8ContentType,
        'cache-control': 'no-cache, no-transform',
        HttpHeaders.connectionHeader: kConnectionKeepAlive,
        'x-accel-buffering': 'no',
      },
    );
  }

  Stream<List<int>> _sseKeepAliveStream(Object streamToken) {
    Timer? timer;
    var ticks = 0;
    var released = false;
    late final StreamController<List<int>> controller;

    Future<void> closeController() async {
      await runAsyncCleanupBounded(
        controller.close,
        onError: (error, stack) =>
            silentLog('mcp_server_ops_runtime', '关闭 SSE 保活流', error, stack),
      );
    }

    void release() {
      if (released) return;
      released = true;
      timer?.cancel();
      timer = null;
      _reservedSseTokens.remove(streamToken);
      _activeSseTokens.remove(streamToken);
      _publishConnectionSnapshot();
    }

    void scheduleKeepAlive() {
      if (released || timer != null) return;
      timer = startNonOverlappingPeriodicTimer(
        _sseKeepAliveInterval,
        (_) async {
          if (released || controller.isClosed) return;
          ticks += 1;
          controller.add(
            utf8.encode(
              ': keepalive ${DateTime.now().toUtc().toIso8601String()}\n\n',
            ),
          );
          if (ticks < _sseKeepAliveTicks) return;
          release();
          await closeController();
        },
        onError: (error, stack) {
          silentLog('mcp_server_ops_runtime', '发送 SSE 保活消息', error, stack);
          release();
          unawaited(closeController());
        },
      );
    }

    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        if (!_activeSseTokens.contains(streamToken)) {
          release();
          unawaited(closeController());
          return;
        }
        _reservedSseTokens.remove(streamToken);
        controller.add(utf8.encode(': OpenHand MCP stream ready\n\n'));
        scheduleKeepAlive();
      },
      onPause: () {
        timer?.cancel();
        timer = null;
      },
      onResume: scheduleKeepAlive,
      onCancel: release,
    );
    return controller.stream;
  }

  /// 回收占位后迟迟没有开始推流的 SSE 槽位。
  void _reapStaleSseReservations() {
    if (_reservedSseTokens.isEmpty) return;
    final cutoff = _runtimeStopwatch.elapsed - _sseReservationGrace;
    var reaped = false;
    _reservedSseTokens.removeWhere((token, reservedAt) {
      if (reservedAt > cutoff) return false;
      _activeSseTokens.remove(token);
      reaped = true;
      return true;
    });
    if (reaped) _publishConnectionSnapshot();
  }

  Future<shelf.Response> _jsonRpc(shelf.Request request) async {
    if (!_requestTransportAllowed(request, 'request/preflight', 0)) {
      return shelf.Response(
        HttpStatus.forbidden,
        body: 'Request blocked by OpenHand policy',
        headers: const <String, String>{
          ..._plainTextResponseHeaders,
          HttpHeaders.connectionHeader: kConnectionClose,
        },
      );
    }
    final declaredLength = int.tryParse(
      request.headers[HttpHeaders.contentLengthHeader] ?? '',
    );
    if (declaredLength != null && declaredLength > _maxRequestBodyBytes) {
      return _requestBodyFailureResponse(
        HttpStatus.requestEntityTooLarge,
        'MCP request body is too large.',
      );
    }

    late final String body;
    try {
      body = await readBoundedMcpOpsRequestBody(
        request.read(),
        maxBytes: _maxRequestBodyBytes,
        idleTimeout: _requestBodyIdleTimeout,
        totalTimeout: _requestBodyTotalTimeout,
      );
    } on ByteStreamSizeLimitException {
      return _requestBodyFailureResponse(
        HttpStatus.requestEntityTooLarge,
        'MCP request body is too large.',
      );
    } on TimeoutException {
      return _requestBodyFailureResponse(
        HttpStatus.requestTimeout,
        'MCP request body timed out.',
      );
    } on FormatException {
      return _requestBodyFailureResponse(
        HttpStatus.badRequest,
        'MCP request body is not valid UTF-8.',
      );
    } on IOException {
      return _requestBodyFailureResponse(
        HttpStatus.badRequest,
        'MCP request body was interrupted.',
      );
    }
    final inboundBytes = utf8.encode(body).length;
    _inboundBytes += inboundBytes;
    final processingStopwatch = Stopwatch()..start();
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: '请求 JSON 无效。',
        method: 'invalid_json',
      );
      return _jsonResponse(
        _jsonRpcError(null, -32700, 'Parse error'),
        statusCode: HttpStatus.badRequest,
        headers: _sessionHeaders(request),
      );
    }

    if (decoded is List) {
      if (decoded.isEmpty || decoded.length > _maxBatchItems) {
        _recordBlocked(
          request,
          inboundBytes: inboundBytes,
          reason: decoded.isEmpty
              ? 'JSON-RPC batch is empty.'
              : 'JSON-RPC batch exceeds the $_maxBatchItems item limit.',
          method: 'batch/invalid',
        );
        return _jsonResponse(
          _jsonRpcError(null, -32600, 'Invalid JSON-RPC batch'),
          statusCode: HttpStatus.badRequest,
          headers: _sessionHeaders(request),
        );
      }
      final responses = <Object?>[];
      for (final item in decoded) {
        if (processingStopwatch.elapsed >= _mcpOpsRequestProcessingTimeout) {
          responses.add(
            _jsonRpcError(null, -32008, 'MCP request processing timed out'),
          );
          break;
        }
        final response = await _handleJsonRpcMessage(
          request,
          item,
          inboundBytes: inboundBytes,
          processingStopwatch: processingStopwatch,
        );
        if (response != null) responses.add(response);
      }
      if (responses.isEmpty) {
        return shelf.Response(
          HttpStatus.accepted,
          headers: <String, String>{
            ..._responseHeaders,
            ..._sessionHeaders(request),
          },
        );
      }
      return _jsonResponse(responses, headers: _sessionHeaders(request));
    }

    final response = await _handleJsonRpcMessage(
      request,
      decoded,
      inboundBytes: inboundBytes,
      processingStopwatch: processingStopwatch,
    );
    if (response == null) {
      return shelf.Response(
        HttpStatus.accepted,
        headers: <String, String>{
          ..._responseHeaders,
          ..._sessionHeaders(request),
        },
      );
    }
    return _jsonResponse(response, headers: _sessionHeaders(request));
  }

  shelf.Response _requestBodyFailureResponse(int statusCode, String message) {
    return shelf.Response(
      statusCode,
      body: message,
      headers: const <String, String>{
        ..._plainTextResponseHeaders,
        HttpHeaders.connectionHeader: kConnectionClose,
      },
    );
  }

  Future<Map<String, Object?>?> _handleJsonRpcMessage(
    shelf.Request request,
    Object? raw, {
    required int inboundBytes,
    required Stopwatch processingStopwatch,
  }) async {
    final message = raw is Map ? stringKeyedMapFromValue(raw) : null;
    if (message == null) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: 'Invalid JSON-RPC message.',
        method: 'invalid_message',
      );
      return _jsonRpcError(null, -32600, 'Invalid Request');
    }
    final id = message['id'];
    final method = stringFromValue(message['method']).trim();
    if (method.isEmpty) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: 'Missing JSON-RPC method.',
        method: 'missing_method',
      );
      return _jsonRpcError(id, -32600, 'Invalid Request');
    }
    final started = Stopwatch()..start();
    final isNotification = !message.containsKey('id');
    if (!_requestAllowed(request, method, inboundBytes)) {
      if (isNotification) return null;
      return _jsonRpcError(id, -32003, 'Request blocked by OpenHand policy');
    }
    if (method.startsWith('notifications/')) {
      // 通知没有 id 和响应，但仍记录审计，以展示客户端生命周期信号。
      _recordLifecycle(
        request,
        method: method,
        started: started,
        inboundBytes: inboundBytes,
        outboundBytes: 0,
      );
      return null;
    }

    switch (method) {
      case 'initialize':
        final result = _jsonRpcResult(id, <String, Object?>{
          'protocolVersion': _protocolVersion,
          'capabilities': const <String, Object?>{
            'tools': <String, Object?>{'listChanged': true},
          },
          'serverInfo': const <String, Object?>{
            'name': _serverName,
            'version': _serverVersion,
          },
          'instructions': _serverInstructions(),
        });
        _recordLifecycle(
          request,
          method: method,
          started: started,
          inboundBytes: inboundBytes,
          outboundBytes: isNotification ? 0 : _messageBytes(result),
        );
        return isNotification ? null : result;
      case 'ping':
        _recordLifecycle(
          request,
          method: method,
          started: started,
          inboundBytes: inboundBytes,
          outboundBytes: isNotification ? 0 : 2,
        );
        return isNotification ? null : _jsonRpcResult(id, const {});
      case 'tools/list':
        final result = _jsonRpcResult(id, <String, Object?>{
          'tools': _toolListProvider()
              .map((item) => item.toMcpJson())
              .toList(growable: false),
        });
        _recordLifecycle(
          request,
          method: method,
          started: started,
          inboundBytes: inboundBytes,
          outboundBytes: isNotification ? 0 : _messageBytes(result),
        );
        return isNotification ? null : result;
      case 'resources/list':
        final result = _jsonRpcResult(id, const <String, Object?>{
          'resources': [],
        });
        _recordLifecycle(
          request,
          method: method,
          started: started,
          inboundBytes: inboundBytes,
          outboundBytes: isNotification ? 0 : _messageBytes(result),
        );
        return isNotification ? null : result;
      case 'tools/call':
        if (isNotification) return null;
        return _handleToolCall(
          request,
          id,
          message,
          inboundBytes: inboundBytes,
          processingStopwatch: processingStopwatch,
        );
      default:
        _recordBlocked(
          request,
          inboundBytes: inboundBytes,
          reason: 'Unknown method: $method',
          method: method,
        );
        return isNotification
            ? null
            : _jsonRpcError(id, -32601, 'Method not found');
    }
  }

  Future<Map<String, Object?>> _handleToolCall(
    shelf.Request request,
    Object? id,
    Map<String, Object?> message, {
    required int inboundBytes,
    required Stopwatch processingStopwatch,
  }) async {
    final started = DateTime.now().toUtc();
    final invocationStopwatch = Stopwatch()..start();
    final params = message['params'] is Map
        ? stringKeyedMapFromValue(message['params'])
        : const <String, Object?>{};
    final name = stringFromValue(params['name']).trim();
    final rawArguments = params['arguments'] is Map
        ? stringKeyedMapFromValue(params['arguments'])
        : const <String, Object?>{};
    McpOpsToolDefinition? tool;
    for (final candidate in _toolListProvider()) {
      if (candidate.name == name) {
        tool = candidate;
        break;
      }
    }
    if (tool == null) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: 'Tool not exposed: $name',
        method: 'tools/call',
        toolName: name,
        arguments: rawArguments,
      );
      return _jsonRpcError(id, -32602, 'Unknown tool: $name');
    }
    final arguments = _normalizeArgumentsToWorkspace(rawArguments);
    if (arguments == null) {
      return _workspaceScopeBlockedResponse(
        request,
        id,
        inboundBytes: inboundBytes,
        toolName: name,
        arguments: rawArguments,
      );
    }
    if (tool.isWrite && _config.writeMode == McpOpsWriteMode.readOnly) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: 'Write tools are disabled by read-only mode.',
        method: 'tools/call',
        toolName: name,
        arguments: arguments,
      );
      return _jsonRpcError(id, -32004, 'Write tools are disabled');
    }
    if (!await _argumentsWithinWorkspaceWithinBudget(
      arguments,
      processingStopwatch,
    )) {
      return _workspaceScopeBlockedResponse(
        request,
        id,
        inboundBytes: inboundBytes,
        toolName: name,
        arguments: arguments,
      );
    }
    if (tool.isWrite && _config.writeMode == McpOpsWriteMode.approvalRequired) {
      final approvalTimeout = shorterDuration(
        _config.approvalTimeout,
        _remainingProcessingTime(processingStopwatch),
      );
      if (approvalTimeout <= Duration.zero) {
        _recordBlocked(
          request,
          inboundBytes: inboundBytes,
          reason: 'Request processing deadline reached before approval.',
          method: 'tools/call',
          toolName: name,
          arguments: arguments,
        );
        return _jsonRpcError(id, -32008, 'MCP request processing timed out');
      }
      final requestCancellation = _requestCancellationSignal(request);
      final approved = await awaitWithCancelSignal<bool>(
        _approvalGate(
          McpOpsApprovalRequest(
            id: _auditId(started),
            toolName: name,
            clientName: _clientName(request),
            ipAddress: _peerAddress(request).label,
            requestedAt: started,
            expiresAt: DateTime.now().toUtc().add(approvalTimeout),
            argumentsPreview: mcpOpsClipAuditText(arguments),
          ),
          requestCancellation,
        ).timeout(approvalTimeout, onTimeout: () => false),
        cancelSignal: requestCancellation,
      );
      if (approved == null) {
        _recordBlocked(
          request,
          inboundBytes: inboundBytes,
          reason: 'Request cancelled while waiting for approval.',
          method: 'tools/call',
          toolName: name,
          arguments: arguments,
        );
        return _jsonRpcError(id, -32008, 'MCP request was cancelled');
      }
      if (!approved) {
        _recordBlocked(
          request,
          inboundBytes: inboundBytes,
          reason: 'Write call rejected or timed out.',
          method: 'tools/call',
          toolName: name,
          arguments: arguments,
        );
        return _jsonRpcError(id, -32005, 'Write call requires approval');
      }
      // 审批期间目录可能被替换为符号链接，调用前重新解析物理路径。
      if (!await _argumentsWithinWorkspaceWithinBudget(
        arguments,
        processingStopwatch,
      )) {
        return _workspaceScopeBlockedResponse(
          request,
          id,
          inboundBytes: inboundBytes,
          toolName: name,
          arguments: arguments,
        );
      }
    }

    final invocationTimeout = shorterDuration(
      _config.timeout,
      _remainingProcessingTime(processingStopwatch),
    );
    if (invocationTimeout <= Duration.zero) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: 'Request processing deadline reached before invocation.',
        method: 'tools/call',
        toolName: name,
        arguments: arguments,
      );
      return _jsonRpcError(id, -32008, 'MCP request processing timed out');
    }
    _markRequest(request, 'tools/call', toolName: name);
    final invocationCancel = Completer<void>();
    final requestCancellation = _requestCancellationSignal(request);
    if (await isCancelSignalCompleted(requestCancellation)) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: 'Request cancelled before invocation.',
        method: 'tools/call',
        toolName: name,
        arguments: arguments,
      );
      return _jsonRpcError(id, -32008, 'MCP request was cancelled');
    }
    final invocationContext = McpOpsToolInvocationContext(
      invocationId: 'mcp-ops-${_auditId(started)}',
      cancelSignal: combineCancelSignals(<Future<void>>[
        invocationCancel.future,
        requestCancellation,
      ])!,
      deadline: DateTime.now().toUtc().add(invocationTimeout),
      workspaceRoot: _normalizedWorkspaceRoot ?? '',
    );
    try {
      final result = await _toolInvoker(tool, arguments, invocationContext)
          .timeout(
            invocationTimeout,
            onTimeout: () {
              if (!invocationCancel.isCompleted) invocationCancel.complete();
              return const McpOpsToolInvocationResult(
                text: 'MCP tool call timed out.',
                isError: true,
              );
            },
          );
      final durationMs = invocationStopwatch.elapsedMilliseconds;
      final payload = <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': result.text},
        ],
        if (result.isError) 'isError': true,
        if (result.metadata.isNotEmpty) 'structuredContent': result.metadata,
      };
      final outboundBytes = utf8.encode(jsonEncode(payload)).length;
      _outboundBytes += outboundBytes;
      if (tool.isWrite && !result.isError) {
        _fileMutationCount += 1;
      }
      _recordAudit(
        request,
        tool: tool,
        kind: McpOpsAuditKind.invocation,
        status: result.isError ? 'failed' : 'success',
        durationMs: durationMs,
        inboundBytes: inboundBytes,
        outboundBytes: outboundBytes,
        arguments: arguments,
        responsePreview: result.text,
        errorMessage: result.isError ? result.text : '',
      );
      if (result.isError) _failedTotal += 1;
      _recordTrafficOutcome(result.isError ? 'failed' : 'success');
      _publishMetrics();
      return _jsonRpcResult(id, payload);
    } catch (error, stack) {
      silentLog('mcp_server_ops_runtime', '执行 MCP 运维工具', error, stack);
      final durationMs = invocationStopwatch.elapsedMilliseconds;
      final message = mcpFailureMessage(error, fallback: 'MCP 工具执行失败，请稍后重试。');
      _failedTotal += 1;
      _recordAudit(
        request,
        tool: tool,
        kind: McpOpsAuditKind.invocation,
        status: 'failed',
        durationMs: durationMs,
        inboundBytes: inboundBytes,
        outboundBytes: 0,
        arguments: arguments,
        errorMessage: message,
      );
      _recordTrafficOutcome('failed');
      _publishMetrics();
      return _jsonRpcError(id, -32000, message);
    }
  }

  bool _requestAllowed(shelf.Request request, String method, int inboundBytes) {
    final now = _runtimeStopwatch.elapsed;
    _requestTimes.removeWhere(
      (item) => now - item >= const Duration(seconds: _rateWindowSeconds),
    );
    if (_config.rpmLimit > 0 && _requestTimes.length >= _config.rpmLimit) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: 'RPM limit exceeded.',
        method: method,
      );
      return false;
    }
    if (_config.callThreshold > 0 && _requestTotal >= _config.callThreshold) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: 'Call threshold reached.',
        method: method,
      );
      return false;
    }
    if (!_requestTransportAllowed(request, method, inboundBytes)) {
      return false;
    }
    _requestTimes.add(now);
    return true;
  }

  Future<void> _requestCancellationSignal(shelf.Request request) {
    final signal = request.context[_requestCancellationContextKey];
    return signal is Future<void> ? signal : Future<void>.value();
  }

  bool _requestTransportAllowed(
    shelf.Request request,
    String method,
    int inboundBytes, {
    DateTime? now,
  }) {
    final checkedAt = now ?? DateTime.now().toUtc();
    final socketPeer = _socketPeerAddress(request);
    if (socketPeer == null || !_networkAllowsIp(socketPeer.ipAddress)) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: socketPeer == null
            ? 'Socket peer identity is unavailable.'
            : 'IP address is outside the configured network mode.',
        method: method,
      );
      return false;
    }
    if (!_timeWindowAllows(checkedAt.toLocal())) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: 'Request is outside allowed time windows.',
        method: method,
      );
      return false;
    }
    if (_config.requireAuthToken) {
      final expected = nullIfBlank(_config.authToken);
      final provided = _requestToken(request);
      if (expected == null || !constantTimeStringEquals(provided, expected)) {
        _recordBlocked(
          request,
          inboundBytes: inboundBytes,
          reason: 'Auth token mismatch.',
          method: method,
        );
        return false;
      }
    }
    final allowedClients = _config.allowedClients
        .map((item) => item.toLowerCase())
        .toSet();
    if (allowedClients.isNotEmpty) {
      final client = _clientName(request).toLowerCase();
      final allowed = allowedClients.any((item) => client.contains(item));
      if (!allowed) {
        _recordBlocked(
          request,
          inboundBytes: inboundBytes,
          reason: 'Client is not allowed.',
          method: method,
        );
        return false;
      }
    }
    return true;
  }

  bool _networkAllowsIp(String rawIp) {
    final ip = InternetAddress.tryParse(rawIp);
    if (ip == null) {
      return _config.networkMode == McpOpsNetworkMode.custom &&
          _config.allowedIpCidrs.isEmpty;
    }
    if (ip.isLoopback) return true;
    if (_config.networkMode == McpOpsNetworkMode.loopbackOnly) return false;
    if (_config.networkMode == McpOpsNetworkMode.lan && !_isPrivateIp(ip)) {
      return false;
    }
    if (_config.allowedIpCidrs.isEmpty) return true;
    return _config.allowedIpCidrs.any((rule) => _ipMatchesRule(ip, rule));
  }

  bool _isPrivateIp(InternetAddress ip) {
    if (ip.type != InternetAddressType.IPv4) return ip.isLoopback;
    final parts = ip.address
        .split('.')
        .map((item) => int.tryParse(item) ?? -1)
        .toList(growable: false);
    if (parts.length != 4 || parts.any((part) => part < 0 || part > 255)) {
      return false;
    }
    return parts[0] == 10 ||
        parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31 ||
        parts[0] == 192 && parts[1] == 168 ||
        parts[0] == 169 && parts[1] == 254;
  }

  bool _ipMatchesRule(InternetAddress ip, String rawRule) {
    final rule = rawRule.trim();
    if (rule.isEmpty) return false;
    if (!rule.contains('/')) {
      final exact = InternetAddress.tryParse(rule);
      return exact != null && exact.address == ip.address;
    }
    final slash = rule.indexOf('/');
    final base = InternetAddress.tryParse(rule.substring(0, slash));
    final prefix = int.tryParse(rule.substring(slash + 1));
    if (base == null || prefix == null) return false;
    if (base.type != InternetAddressType.IPv4 ||
        ip.type != InternetAddressType.IPv4) {
      return base.address == ip.address;
    }
    final maskBits = prefix.clamp(0, 32);
    final mask = maskBits == 0
        ? 0
        : (0xffffffff << (32 - maskBits)) & 0xffffffff;
    return (_ipv4ToInt(base.address) & mask) == (_ipv4ToInt(ip.address) & mask);
  }

  int _ipv4ToInt(String address) {
    final parts = address
        .split('.')
        .map((item) => int.tryParse(item) ?? 0)
        .toList(growable: false);
    if (parts.length != 4) return 0;
    return parts.fold<int>(0, (value, part) => (value << 8) + part);
  }

  bool _timeWindowAllows(DateTime localNow) {
    if (_config.allowedTimeWindows.isEmpty) return true;
    final minuteOfDay = localNow.hour * 60 + localNow.minute;
    for (final window in _config.allowedTimeWindows) {
      final parts = window.split('-');
      if (parts.length != 2) continue;
      final start = _parseMinuteOfDay(parts[0]);
      final end = _parseMinuteOfDay(parts[1]);
      if (start == null || end == null) continue;
      if (start <= end) {
        if (minuteOfDay >= start && minuteOfDay <= end) return true;
      } else if (minuteOfDay >= start || minuteOfDay <= end) {
        return true;
      }
    }
    return false;
  }

  int? _parseMinuteOfDay(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  String _serverInstructions() {
    final root = _normalizedWorkspaceRoot;
    const base =
        'OpenHand exposes approved local tools, memory, skills, instructions, knowledge and MCP bridges. Respect policy errors and request approval for write operations.';
    if (root == null) return base;
    return '$base Workspace root: $root. Use "." or relative paths for this workspace; recognized path arguments are resolved from this root and paths outside it are rejected.';
  }

  String? get _normalizedWorkspaceRoot {
    final rawRoot = nullIfBlank(_config.workspaceRoot);
    if (rawRoot == null) return null;
    final expandedRoot = OpenHandPaths.normalizeOptionalPath(rawRoot);
    return p.normalize(p.absolute(expandedRoot));
  }

  Map<String, Object?>? _normalizeArgumentsToWorkspace(
    Map<String, Object?> arguments,
  ) {
    final root = _normalizedWorkspaceRoot;
    if (root == null) return arguments;
    final scan = _scanMcpOpsPathArguments(arguments);
    if (!scan.valid) return null;

    Object? normalize(Object? value, String key) {
      if (value is Map) {
        return <String, Object?>{
          for (final entry in value.entries)
            '${entry.key}': normalize(entry.value, '${entry.key}'),
        };
      }
      if (value is List) {
        return value
            .map((item) => normalize(item, key))
            .toList(growable: false);
      }
      if (value is! String || !_mcpOpsArgumentKeyLooksLikePath(key)) {
        return value;
      }
      final expanded = OpenHandPaths.normalizeOptionalPath(value);
      if (expanded.isEmpty) return value;
      return p.isAbsolute(expanded)
          ? p.normalize(expanded)
          : p.normalize(p.join(root, expanded));
    }

    return normalize(arguments, '')! as Map<String, Object?>;
  }

  Duration _remainingProcessingTime(Stopwatch processingStopwatch) {
    return nonNegativeDuration(
      _mcpOpsRequestProcessingTimeout - processingStopwatch.elapsed,
    );
  }

  Future<bool> _argumentsWithinWorkspaceWithinBudget(
    Map<String, Object?> arguments,
    Stopwatch processingStopwatch,
  ) {
    final timeout = shorterDuration(
      _mcpOpsWorkspacePathCheckTimeout,
      _remainingProcessingTime(processingStopwatch),
    );
    if (timeout <= Duration.zero) return Future<bool>.value(false);
    return _argumentsWithinWorkspace(
      arguments,
    ).timeout(timeout, onTimeout: () => false);
  }

  Future<bool> _argumentsWithinWorkspace(Map<String, Object?> arguments) async {
    final root = _normalizedWorkspaceRoot;
    if (root == null) return true;
    final pathScan = _scanMcpOpsPathArguments(arguments);
    if (!pathScan.valid) return false;
    for (final path in pathScan.values) {
      final normalizedPath = p.normalize(p.absolute(path));
      if (!isPathWithinOrEqual(root, normalizedPath) ||
          !await isPhysicalPathWithinOrEqual(root, normalizedPath)) {
        return false;
      }
    }
    return true;
  }

  Map<String, Object?> _workspaceScopeBlockedResponse(
    shelf.Request request,
    Object? id, {
    required int inboundBytes,
    required String toolName,
    required Map<String, Object?> arguments,
  }) {
    _recordBlocked(
      request,
      inboundBytes: inboundBytes,
      reason:
          'Tool arguments reference a path outside the configured workspace '
          'or the physical path could not be safely resolved.',
      method: 'tools/call',
      toolName: toolName,
      arguments: arguments,
    );
    return _jsonRpcError(id, -32006, 'Path is outside the workspace scope');
  }

  void _markRequest(shelf.Request request, String method, {String? toolName}) {
    _requestTotal += 1;
    _increment(_ipDistribution, _peerAddress(request).label);
    _increment(_clientDistribution, _clientName(request));
    _increment(_requestDistribution, toolName ?? method);
    _increment(_protocolDistribution, _protocol(request));
    // tools/call 由 _handleToolCall 记录最终结果，其余允许的方法此时均已成功。
    if (method != 'tools/call') {
      _recordTrafficOutcome('success');
    }
    _publishMetrics();
  }

  void _recordBlocked(
    shelf.Request request, {
    required int inboundBytes,
    required String reason,
    required String method,
    String? toolName,
    Map<String, Object?> arguments = const <String, Object?>{},
  }) {
    _blockedTotal += 1;
    _increment(_ipDistribution, _peerAddress(request).label);
    _increment(_clientDistribution, _clientName(request));
    _increment(_requestDistribution, toolName ?? method);
    _increment(_protocolDistribution, _protocol(request));
    _recordTrafficOutcome('blocked');
    _recordAudit(
      request,
      status: 'blocked',
      kind: _auditKindForMethod(toolName != null ? 'tools/call' : method),
      toolName: toolName ?? method,
      surface: 'policy',
      endpoint: method,
      durationMs: 0,
      inboundBytes: inboundBytes,
      outboundBytes: 0,
      arguments: arguments,
      errorMessage: reason,
    );
    _publishMetrics();
  }

  void _recordAudit(
    shelf.Request request, {
    McpOpsToolDefinition? tool,
    String? toolName,
    String? surface,
    String? endpoint,
    required McpOpsAuditKind kind,
    required String status,
    required int durationMs,
    required int inboundBytes,
    required int outboundBytes,
    Map<String, Object?> arguments = const <String, Object?>{},
    String responsePreview = '',
    String errorMessage = '',
  }) {
    final now = DateTime.now().toUtc();
    // 关闭载荷采集时仍记录阶段、耗时、对端和字节数，但不持久化正文与令牌估算。
    final capture = _config.capturePayload;
    final argumentText = capture ? mcpOpsClipAuditText(arguments) : '';
    final responseText = capture ? mcpOpsClipAuditText(responsePreview) : '';
    final peer = _peerAddress(request);
    _auditSink(
      McpOpsAuditEntry(
        id: _auditId(now),
        timestamp: now,
        toolName: tool?.name ?? toolName ?? '',
        surface: tool?.surface.storageValue ?? surface ?? '',
        endpoint: tool?.endpointId ?? endpoint ?? '',
        status: status,
        kind: kind,
        protocol: _protocol(request),
        model: _model(request),
        clientName: _clientName(request),
        ipAddress: peer.label,
        durationMs: durationMs,
        promptTokens: capture ? _estimateTokens(argumentText) : 0,
        completionTokens: capture ? _estimateTokens(responseText) : 0,
        inboundBytes: inboundBytes,
        outboundBytes: outboundBytes,
        errorMessage: errorMessage,
        requestSummary: '${request.method} ${request.requestedUri.path}',
        argumentsPreview: argumentText,
        responsePreview: responseText,
        environment: <String, Object?>{
          'method': request.method,
          'path': request.requestedUri.path,
          'query': redactSensitiveStringMap(
            request.requestedUri.queryParameters,
          ),
          'user_agent': request.headers[kUserAgentHeaderName],
          'mcp_protocol_version': request.headers[kMcpProtocolVersionHeader],
          'origin': redactSensitiveUriForLogging(request.headers['origin']),
          'referer': redactSensitiveUriForLogging(
            request.headers[HttpHeaders.refererHeader],
          ),
          'peer_ip': peer.ipAddress,
          if (peer.port != null) 'peer_port': peer.port,
          'write_mode': _config.writeMode.storageValue,
          'network_mode': _config.networkMode.storageValue,
        },
      ),
    );
  }

  /// 审计工具调用之外的协议流量，并通过 [_markRequest] 更新请求计数。
  void _recordLifecycle(
    shelf.Request request, {
    required String method,
    required Stopwatch started,
    required int inboundBytes,
    required int outboundBytes,
    String status = 'success',
  }) {
    _markRequest(request, method);
    _recordAudit(
      request,
      toolName: method,
      surface: 'protocol',
      endpoint: method,
      kind: _auditKindForMethod(method),
      status: status,
      durationMs: started.elapsedMilliseconds,
      inboundBytes: inboundBytes,
      outboundBytes: outboundBytes,
    );
  }

  static McpOpsAuditKind _auditKindForMethod(String method) {
    switch (method) {
      case 'initialize':
        return McpOpsAuditKind.handshake;
      case 'ping':
        return McpOpsAuditKind.heartbeat;
      case 'tools/list':
      case 'resources/list':
        return McpOpsAuditKind.discovery;
      case 'tools/call':
        return McpOpsAuditKind.invocation;
      case 'stream/get':
        return McpOpsAuditKind.stream;
      case 'session/delete':
        return McpOpsAuditKind.session;
      default:
        return method.startsWith('notifications/')
            ? McpOpsAuditKind.notification
            : McpOpsAuditKind.other;
    }
  }

  int _messageBytes(Object? message) => utf8.encode(jsonEncode(message)).length;

  void _publishMetrics() {
    _setSnapshot(
      _snapshot.copyWith(
        activeRequests: _activeRequests,
        activeStreams: _activeSseStreams,
        sessionCount: _sessionIds.length,
        currentConnections: _currentConnections,
        requestTotal: _requestTotal,
        blockedTotal: _blockedTotal,
        failedTotal: _failedTotal,
        inboundBytes: _inboundBytes,
        outboundBytes: _outboundBytes,
        fileMutationCount: _fileMutationCount,
        memoryRssBytes: _currentRss(),
        avgLatencyMs: _averageLatency(),
        p95LatencyMs: _p95Latency(),
        trafficSeries: _trafficSnapshot(),
        ipDistribution: Map<String, int>.unmodifiable(_ipDistribution),
        clientDistribution: Map<String, int>.unmodifiable(_clientDistribution),
        requestDistribution: Map<String, int>.unmodifiable(
          _requestDistribution,
        ),
        protocolDistribution: Map<String, int>.unmodifiable(
          _protocolDistribution,
        ),
      ),
    );
  }

  int get _currentConnections => _activeRequests + _activeSseStreams;

  int get _activeRequests => _activeRequestTokens.length;

  int get _activeSseStreams => _activeSseTokens.length;

  void _publishConnectionSnapshot() {
    _setSnapshot(
      _snapshot.copyWith(
        activeRequests: _activeRequests,
        activeStreams: _activeSseStreams,
        sessionCount: _sessionIds.length,
        currentConnections: _currentConnections,
        memoryRssBytes: _currentRss(),
      ),
    );
  }

  void _applyConnectivityResult(McpOpsConnectivityResult result) {
    _setSnapshot(
      _snapshot.copyWith(
        lastConnectivityAt: result.checkedAt,
        lastConnectivityOk: result.ok,
        lastConnectivityMessage: result.message,
      ),
    );
  }

  void _setSnapshot(McpOpsRuntimeSnapshot snapshot) {
    _snapshot = snapshot;
    _snapshotSink(snapshot);
  }

  shelf.Response _jsonResponse(
    Object? value, {
    int statusCode = HttpStatus.ok,
    Map<String, String> headers = const <String, String>{},
  }) {
    final body = jsonEncode(value);
    final bytes = utf8.encode(body).length;
    if (!isHttpFailureStatus(statusCode)) {
      _outboundBytes += bytes;
    }
    return shelf.Response(
      statusCode,
      body: body,
      headers: <String, String>{
        ..._responseHeaders,
        kContentTypeHeaderName: kApplicationJsonUtf8ContentType,
        ...headers,
      },
    );
  }

  Map<String, Object?> _jsonRpcResult(Object? id, Object? result) {
    return <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};
  }

  Map<String, Object?> _jsonRpcError(Object? id, int code, String message) {
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, Object?>{'code': code, 'message': message},
    };
  }

  Map<String, String> _sessionHeaders(shelf.Request request) {
    return <String, String>{
      kMcpProtocolVersionHeader: _protocolVersion,
      kMcpSessionIdHeader: _sessionIdForRequest(request),
    };
  }

  String _sessionIdForRequest(shelf.Request request) {
    final provided = nullIfBlank(request.headers[kMcpSessionIdHeader]);
    if (provided != null && isValidMcpHttpHeaderValue(provided)) {
      _trackSessionId(provided);
      return provided;
    }
    final generated =
        'openhand-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 20)}';
    _trackSessionId(generated);
    return generated;
  }

  void _trackSessionId(String sessionId) {
    _sessionIds.add(sessionId);
    while (_sessionIds.length > _maxSessionIds) {
      _sessionIds.remove(_sessionIds.first);
    }
  }

  String _requestToken(shelf.Request request) {
    final direct = nullIfBlank(request.headers['x-openhand-mcp-token']);
    if (direct != null) return direct;
    final auth = request.headers[kAuthorizationHeaderName] ?? '';
    final lower = auth.toLowerCase();
    if (lower.startsWith('bearer ')) return auth.substring(7).trim();
    return '';
  }

  _McpOpsPeerAddress _peerAddress(shelf.Request request) {
    return _socketPeerAddress(request) ?? const _McpOpsPeerAddress.unknown();
  }

  _McpOpsPeerAddress? _socketPeerAddress(shelf.Request request) {
    final info = request.context[_connectionInfoContextKey];
    if (info is! HttpConnectionInfo) return null;
    return _McpOpsPeerAddress(
      ipAddress: info.remoteAddress.address,
      port: _validPort(info.remotePort),
    );
  }

  int? _validPort(int? value) {
    if (!isValidPort(value)) return null;
    return value;
  }

  String _clientName(shelf.Request request) {
    return nullIfBlank(request.headers['mcp-client-name']) ??
        nullIfBlank(request.headers['x-openhand-client']) ??
        nullIfBlank(request.headers[kUserAgentHeaderName]) ??
        'unknown';
  }

  String _protocol(shelf.Request request) {
    return nullIfBlank(request.headers[kMcpProtocolVersionHeader]) ??
        _protocolVersion;
  }

  String _model(shelf.Request request) {
    return nullIfBlank(request.headers['x-openhand-model']) ??
        nullIfBlank(request.headers['x-model']) ??
        'external-mcp';
  }

  String _auditId(DateTime time) {
    return '${time.microsecondsSinceEpoch}-${math.Random().nextInt(1 << 20)}';
  }

  int _averageLatency() {
    if (_latencies.isEmpty) return 0;
    final sum = _latencies.fold<int>(0, (total, item) => total + item);
    return (sum / _latencies.length).round();
  }

  int _p95Latency() {
    if (_latencies.isEmpty) return 0;
    final sorted = List<int>.from(_latencies)..sort();
    final index = ((sorted.length - 1) * 0.95).round();
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  int _currentRss() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }

  int _estimateTokens(String text) {
    if (text.isEmpty) return 0;
    return math.max(1, (text.length / 4).ceil());
  }

  void _increment(Map<String, int> map, String key) {
    addMcpOpsMetricCount(map, key, 1);
  }

  /// 将请求结果计入当前分钟，并清理趋势窗口外的数据桶。
  void _recordTrafficOutcome(String outcome) {
    final bucket = _currentTrafficBucket();
    switch (outcome) {
      case 'blocked':
        bucket.blocked += 1;
      case 'failed':
        bucket.failed += 1;
      default:
        bucket.success += 1;
    }
  }

  void _recordTrafficLatency(int durationMs) {
    if (durationMs <= 0) return;
    _currentTrafficBucket().latencies.add(durationMs);
  }

  _McpOpsMinuteBucket _currentTrafficBucket() {
    final now = DateTime.now().toUtc();
    final minute = _minuteStart(now);
    final bucket = _trafficBuckets.putIfAbsent(
      minute,
      () => _McpOpsMinuteBucket(minute),
    );
    if (_trafficBuckets.length > mcpOpsTrafficWindowMinutes * 3) {
      final cutoff = minute.subtract(
        const Duration(minutes: mcpOpsTrafficWindowMinutes * 3),
      );
      _trafficBuckets.removeWhere((key, _) => key.isBefore(cutoff));
    }
    return bucket;
  }

  /// 按时间输出最近的分钟桶，并用空样本补齐间隔。
  List<McpOpsTrafficSample> _trafficSnapshot() {
    final now = DateTime.now().toUtc();
    final latest = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final samples = <McpOpsTrafficSample>[];
    for (var i = mcpOpsTrafficWindowMinutes - 1; i >= 0; i--) {
      final minute = latest.subtract(Duration(minutes: i));
      final bucket = _trafficBuckets[minute];
      samples.add(bucket?.toSample() ?? McpOpsTrafficSample(minute: minute));
    }
    return List<McpOpsTrafficSample>.unmodifiable(samples);
  }
}

final class _McpOpsActiveRequest {
  final Completer<void> _cancellation = Completer<void>();

  Future<void> get cancelSignal => _cancellation.future;

  void cancel() {
    if (!_cancellation.isCompleted) _cancellation.complete();
  }
}

class _McpOpsPeerAddress {
  const _McpOpsPeerAddress({required this.ipAddress, this.port});

  const _McpOpsPeerAddress.unknown() : ipAddress = 'unknown', port = null;

  final String ipAddress;
  final int? port;

  String get label {
    final host = nullIfBlank(ipAddress) ?? 'unknown';
    final sourcePort = port;
    if (host == 'unknown' || sourcePort == null) return host;
    return mcpOpsAuthority(host, sourcePort);
  }
}

/// 单个 UTC 分钟内的 MCP 流量累加器。
class _McpOpsMinuteBucket {
  _McpOpsMinuteBucket(this.minute);

  factory _McpOpsMinuteBucket.fromSample(McpOpsTrafficSample sample) {
    final bucket = _McpOpsMinuteBucket(_minuteStart(sample.minute));
    bucket.success = sample.success;
    bucket.blocked = sample.blocked;
    bucket.failed = sample.failed;
    if (sample.avgLatencyMs > 0) {
      bucket.latencies.add(sample.avgLatencyMs);
    }
    if (sample.p95LatencyMs > 0 && sample.p95LatencyMs != sample.avgLatencyMs) {
      bucket.latencies.add(sample.p95LatencyMs);
    }
    return bucket;
  }

  final DateTime minute;
  int success = 0;
  int blocked = 0;
  int failed = 0;
  final List<int> latencies = <int>[];

  McpOpsTrafficSample toSample() {
    var avg = 0;
    var p95 = 0;
    if (latencies.isNotEmpty) {
      final sorted = List<int>.from(latencies)..sort();
      avg = (sorted.fold<int>(0, (sum, item) => sum + item) / sorted.length)
          .round();
      final index = ((sorted.length - 1) * 0.95).round();
      p95 = sorted[index.clamp(0, sorted.length - 1)];
    }
    return McpOpsTrafficSample(
      minute: minute,
      success: success,
      blocked: blocked,
      failed: failed,
      avgLatencyMs: avg,
      p95LatencyMs: p95,
    );
  }
}

DateTime _minuteStart(DateTime value) {
  final utc = value.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
}
