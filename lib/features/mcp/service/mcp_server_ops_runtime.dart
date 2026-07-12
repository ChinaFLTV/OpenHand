import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../../shared/net/http_response_utils.dart';
import '../../../shared/net/http_status_utils.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/path_safety.dart';
import '../../../shared/util/physical_path_safety.dart';
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
    Future<bool> Function(McpOpsApprovalRequest request);
typedef McpOpsAuditSink = void Function(McpOpsAuditEntry entry);
typedef McpOpsSnapshotSink = void Function(McpOpsRuntimeSnapshot snapshot);

class McpOpsToolInvocationContext {
  const McpOpsToolInvocationContext({
    required this.invocationId,
    required this.cancelSignal,
    required this.deadline,
  });

  final String invocationId;
  final Future<void> cancelSignal;
  final DateTime deadline;
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
      .toSet();
  if (words.any(_mcpOpsPathArgumentWords.contains)) return true;
  if (normalized == 'cwd' || normalized == 'workspace') return true;
  return words.contains('workspace') && words.contains('root');
}

class McpOpsRequestBodyTooLargeException implements Exception {
  const McpOpsRequestBodyTooLargeException({
    required this.maxBytes,
    required this.receivedBytes,
  });

  final int maxBytes;
  final int receivedBytes;

  @override
  String toString() {
    return 'MCP request body exceeded $maxBytes bytes '
        '(received at least $receivedBytes bytes).';
  }
}

/// Collects an MCP request body while enforcing independent byte, idle-time,
/// and wall-clock limits. Once a limit wins, later chunks are ignored without
/// being buffered. The owning HTTP handler closes the connection after writing
/// its 408/413 response; cancelling a `dart:io` request stream before Shelf has
/// written that response would abort the socket and hide the status from the
/// client.
Future<String> readBoundedMcpOpsRequestBody(
  Stream<List<int>> stream, {
  required int maxBytes,
  required Duration idleTimeout,
  required Duration totalTimeout,
}) {
  if (maxBytes < 1) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'Must be positive.');
  }
  if (idleTimeout <= Duration.zero) {
    throw ArgumentError.value(idleTimeout, 'idleTimeout', 'Must be positive.');
  }
  if (totalTimeout <= Duration.zero) {
    throw ArgumentError.value(
      totalTimeout,
      'totalTimeout',
      'Must be positive.',
    );
  }

  final completer = Completer<String>();
  final bytes = BytesBuilder(copy: false);
  Timer? idleTimer;
  Timer? totalTimer;
  var receivedBytes = 0;
  var settled = false;

  void cancelTimers() {
    idleTimer?.cancel();
    totalTimer?.cancel();
    idleTimer = null;
    totalTimer = null;
  }

  void fail(Object error, StackTrace stack) {
    if (settled) return;
    settled = true;
    cancelTimers();
    completer.completeError(error, stack);
  }

  void resetIdleTimer() {
    idleTimer?.cancel();
    idleTimer = Timer(
      idleTimeout,
      () => fail(
        TimeoutException('MCP request body stalled.', idleTimeout),
        StackTrace.current,
      ),
    );
  }

  totalTimer = Timer(
    totalTimeout,
    () => fail(
      TimeoutException(
        'MCP request body exceeded its total time limit.',
        totalTimeout,
      ),
      StackTrace.current,
    ),
  );
  stream.listen(
    (chunk) {
      if (settled) return;
      resetIdleTimer();
      receivedBytes += chunk.length;
      if (receivedBytes > maxBytes) {
        fail(
          McpOpsRequestBodyTooLargeException(
            maxBytes: maxBytes,
            receivedBytes: receivedBytes,
          ),
          StackTrace.current,
        );
        return;
      }
      bytes.add(chunk);
    },
    onError: (Object error, StackTrace stack) => fail(error, stack),
    onDone: () {
      if (settled) return;
      settled = true;
      cancelTimers();
      try {
        completer.complete(utf8.decode(bytes.takeBytes()));
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    },
    cancelOnError: true,
  );
  if (!settled) {
    resetIdleTimer();
  }
  return completer.future;
}

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
    if (maxRequestBodyBytes < 1) {
      throw ArgumentError.value(
        maxRequestBodyBytes,
        'maxRequestBodyBytes',
        'Must be positive.',
      );
    }
    if (requestBodyIdleTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestBodyIdleTimeout,
        'requestBodyIdleTimeout',
        'Must be positive.',
      );
    }
    if (requestBodyTotalTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestBodyTotalTimeout,
        'requestBodyTotalTimeout',
        'Must be positive.',
      );
    }
    if (maxConcurrentRequests < 1) {
      throw ArgumentError.value(
        maxConcurrentRequests,
        'maxConcurrentRequests',
        'Must be positive.',
      );
    }
    if (maxBatchItems < 1) {
      throw ArgumentError.value(
        maxBatchItems,
        'maxBatchItems',
        'Must be positive.',
      );
    }
  }

  static const String _protocolVersion = '2025-11-25';
  static const String _serverName = 'OpenHand MCP Server';
  static const String _serverVersion = '1.0.0';
  static const Duration _shutdownTimeout = Duration(seconds: 5);
  static const Duration _connectivityTimeout = Duration(seconds: 3);
  static const int _maxConnectivityResponseBytes = 1024 * 1024;
  static const Duration _sseKeepAliveInterval = Duration(seconds: 15);
  static const int _sseKeepAliveTicks = 480;
  static const int _maxSseStreams = 32;
  static const int _maxSessionIds = 1024;
  static const int _maxMetricDistributionKeys = 256;
  static const int _maxMetricKeyChars = 160;
  static const String _metricOverflowKey = 'other';
  static const int _latencyWindow = 512;
  static const int _rateWindowSeconds = 60;
  static const String _connectionInfoContextKey = 'shelf.io.connection_info';
  static const Map<String, String> _responseHeaders = <String, String>{
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
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
  Future<void>? _lifecycleTask;
  final List<DateTime> _requestTimes = <DateTime>[];
  final List<int> _latencies = <int>[];
  final Set<Object> _activeRequestTokens = <Object>{};
  final Set<Object> _activeSseTokens = <Object>{};
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
  // Minute-aligned traffic rollup keyed by UTC bucket start, feeding the
  // dashboard trend/latency charts from every request rather than audited
  // tool calls alone.
  final Map<DateTime, _McpOpsMinuteBucket> _trafficBuckets =
      <DateTime, _McpOpsMinuteBucket>{};

  McpOpsRuntimeSnapshot get snapshot => _snapshot;
  bool get isRunning => _server != null;

  void hydrateMetrics(McpOpsRuntimeSnapshot snapshot) {
    _snapshot = snapshot.asOfflinePersistedSnapshot();
    _requestTotal = snapshot.requestTotal;
    _blockedTotal = snapshot.blockedTotal;
    _failedTotal = snapshot.failedTotal;
    _inboundBytes = snapshot.inboundBytes;
    _outboundBytes = snapshot.outboundBytes;
    _fileMutationCount = snapshot.fileMutationCount;
    _ipDistribution
      ..clear()
      ..addAll(snapshot.ipDistribution);
    _clientDistribution
      ..clear()
      ..addAll(snapshot.clientDistribution);
    _requestDistribution
      ..clear()
      ..addAll(snapshot.requestDistribution);
    _protocolDistribution
      ..clear()
      ..addAll(snapshot.protocolDistribution);
    _trafficBuckets
      ..clear()
      ..addEntries(
        snapshot.trafficSeries.map(
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
          _mcpOpsTimeInRange(minute, startUtc: startUtc, endUtc: endUtc),
    );
    _setSnapshot(
      _snapshot.copyWith(
        trafficSeries: _trafficSnapshot()
            .where((sample) {
              return !_mcpOpsTimeInRange(
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
    return _runLifecycleLocked(() => _startUnlocked(config));
  }

  Future<void> _startUnlocked(McpOpsConfig config) async {
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
      // Streamable HTTP multiplexes POST (JSON-RPC), GET (SSE stream) and
      // DELETE (session end) onto a single endpoint URL. Clients disagree on
      // whether that URL carries a path (`/mcp`, `/mcp/`) or is the bare root,
      // so every non-health request is funneled through one method dispatcher
      // to avoid 404s from exact-path mismatches (e.g. Cursor's "Failed to open
      // SSE stream: Not Found").
      final router = Router(notFoundHandler: _dispatchMcp)
        ..get('/health', _health);
      final handler = const shelf.Pipeline()
          .addMiddleware(_telemetryMiddleware())
          .addHandler(router.call);
      _server = await shelf_io.serve(
        handler,
        mcpOpsListenAddress(config.listenHost),
        config.listenPort,
      );
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
          errorMessage: '$error',
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

  Future<void> _stopUnlocked() async {
    final server = _server;
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
    _server = null;
    try {
      await server.close(force: true).timeout(_shutdownTimeout);
    } finally {
      _activeRequestTokens.clear();
      _activeSseTokens.clear();
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
    return _runLifecycleLocked(() => _restartUnlocked(config));
  }

  Future<void> _restartUnlocked(McpOpsConfig config) async {
    _setSnapshot(
      _snapshot.copyWith(lifecycle: McpOpsLifecycleState.restarting),
    );
    await _stopUnlocked();
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

  Future<void> _runLifecycleLocked(Future<void> Function() action) async {
    while (_lifecycleTask != null) {
      await _lifecycleTask;
    }
    final completer = Completer<void>();
    _lifecycleTask = completer.future;
    try {
      await action();
    } finally {
      if (identical(_lifecycleTask, completer.future)) {
        _lifecycleTask = null;
      }
      if (!completer.isCompleted) {
        completer.complete();
      }
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
    // Exercise the real Streamable HTTP endpoint with an `initialize` handshake
    // so the test mirrors what external clients (Cursor, etc.) actually do,
    // rather than only probing /health.
    final uri = Uri(scheme: 'http', host: host, port: port, path: '/mcp');
    final client = HttpClient()..connectionTimeout = _connectivityTimeout;
    try {
      final request = await client.postUrl(uri).timeout(_connectivityTimeout);
      request.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.acceptHeader, 'application/json, text/event-stream')
        ..set('mcp-protocol-version', _protocolVersion)
        ..set('x-openhand-client', 'OpenHand Self-Test');
      final token = nullIfBlank(_config.authToken);
      if (_config.requireAuthToken && token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.add(utf8.encode(jsonEncode(_initializeProbePayload)));
      final response = await request.close().timeout(_connectivityTimeout);
      final body = await readBoundedHttpResponseText(
        response,
        maxBytes: _maxConnectivityResponseBytes,
        idleTimeout: _connectivityTimeout,
        totalTimeout: _connectivityTimeout,
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
    } catch (error) {
      final result = McpOpsConnectivityResult(
        ok: false,
        message: '$error',
        checkedAt: checkedAt,
      );
      _applyConnectivityResult(result);
      return result;
    } finally {
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
    return trimmed.length <= maxChars
        ? trimmed
        : '${trimmed.substring(0, maxChars)}...';
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
              ..._responseHeaders,
              'content-type': 'text/plain; charset=utf-8',
              'connection': 'close',
            },
          );
        }
        final requestToken = Object();
        final startedAt = DateTime.now().toUtc();
        _activeRequestTokens.add(requestToken);
        _setSnapshot(
          _snapshot.copyWith(
            activeRequests: _activeRequests,
            currentConnections: _currentConnections,
            memoryRssBytes: _currentRss(),
          ),
        );
        try {
          return await innerHandler(request);
        } finally {
          final durationMs = DateTime.now()
              .toUtc()
              .difference(startedAt)
              .inMilliseconds;
          _latencies.add(durationMs);
          if (_latencies.length > _latencyWindow) {
            _latencies.removeRange(0, _latencies.length - _latencyWindow);
          }
          _recordTrafficLatency(durationMs);
          _activeRequestTokens.remove(requestToken);
          _setSnapshot(
            _snapshot.copyWith(
              activeRequests: _activeRequests,
              currentConnections: _currentConnections,
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

  /// Single entrypoint for the Streamable HTTP endpoint, dispatching by method
  /// regardless of the request path so `/`, `/mcp` and `/mcp/` behave alike.
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
          ..._responseHeaders,
          'content-type': 'text/plain; charset=utf-8',
          'connection': 'close',
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
            'content-type': 'text/plain; charset=utf-8',
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
        headers: const <String, String>{
          ..._responseHeaders,
          'content-type': 'text/plain; charset=utf-8',
        },
      );
    }
    _recordLifecycle(
      request,
      method: method,
      started: DateTime.now().toUtc(),
      inboundBytes: 0,
      outboundBytes: 0,
    );
    final providedSessionId = nullIfBlank(request.headers['mcp-session-id']);
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
        'mcp-protocol-version': _protocolVersion,
        if (validSessionId != null) 'mcp-session-id': validSessionId,
      },
    );
  }

  shelf.Response _sseStream(shelf.Request request) {
    const method = 'stream/get';
    final started = DateTime.now().toUtc();
    if (!_requestAllowed(request, method, 0)) {
      return shelf.Response(
        HttpStatus.forbidden,
        body: 'Request blocked by OpenHand policy',
        headers: const <String, String>{
          ..._responseHeaders,
          'content-type': 'text/plain; charset=utf-8',
        },
      );
    }
    // Enforce the stream cap before counting a success so a rejected stream is
    // audited as blocked, never double-counted as both success and blocked.
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
        headers: const <String, String>{
          ..._responseHeaders,
          'content-type': 'text/plain; charset=utf-8',
        },
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
    _publishConnectionSnapshot();
    return shelf.Response.ok(
      _sseKeepAliveStream(streamToken),
      headers: <String, String>{
        ..._responseHeaders,
        ..._sessionHeaders(request),
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache, no-transform',
        'connection': 'keep-alive',
        'x-accel-buffering': 'no',
      },
    );
  }

  Stream<List<int>> _sseKeepAliveStream(Object streamToken) async* {
    try {
      yield utf8.encode(': OpenHand MCP stream ready\n\n');
      for (var index = 0; index < _sseKeepAliveTicks; index++) {
        await Future<void>.delayed(_sseKeepAliveInterval);
        yield utf8.encode(
          ': keepalive ${DateTime.now().toUtc().toIso8601String()}\n\n',
        );
      }
    } finally {
      _activeSseTokens.remove(streamToken);
      _publishConnectionSnapshot();
    }
  }

  Future<shelf.Response> _jsonRpc(shelf.Request request) async {
    if (!_requestTransportAllowed(request, 'request/preflight', 0)) {
      return shelf.Response(
        HttpStatus.forbidden,
        body: 'Request blocked by OpenHand policy',
        headers: const <String, String>{
          ..._responseHeaders,
          'content-type': 'text/plain; charset=utf-8',
          'connection': 'close',
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
    } on McpOpsRequestBodyTooLargeException {
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
    final processingDeadline = DateTime.now().toUtc().add(
      _mcpOpsRequestProcessingTimeout,
    );
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (error) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: 'Invalid JSON: $error',
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
        if (!DateTime.now().toUtc().isBefore(processingDeadline)) {
          responses.add(
            _jsonRpcError(null, -32008, 'MCP request processing timed out'),
          );
          break;
        }
        final response = await _handleJsonRpcMessage(
          request,
          item,
          inboundBytes: inboundBytes,
          processingDeadline: processingDeadline,
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
      processingDeadline: processingDeadline,
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
        ..._responseHeaders,
        'content-type': 'text/plain; charset=utf-8',
        'connection': 'close',
      },
    );
  }

  Future<Map<String, Object?>?> _handleJsonRpcMessage(
    shelf.Request request,
    Object? raw, {
    required int inboundBytes,
    required DateTime processingDeadline,
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
    final started = DateTime.now().toUtc();
    final isNotification = !message.containsKey('id');
    if (!_requestAllowed(request, method, inboundBytes)) {
      if (isNotification) return null;
      return _jsonRpcError(id, -32003, 'Request blocked by OpenHand policy');
    }
    if (method.startsWith('notifications/')) {
      // Notifications carry no id and expect no response; still audit them so
      // the console shows client-side lifecycle signals (initialized, etc.).
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
          'instructions':
              'OpenHand exposes approved local tools, memory, skills, instructions, knowledge and MCP bridges. Respect policy errors and request approval for write operations.',
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
          processingDeadline: processingDeadline,
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
    required DateTime processingDeadline,
  }) async {
    final started = DateTime.now().toUtc();
    final params = message['params'] is Map
        ? stringKeyedMapFromValue(message['params'])
        : const <String, Object?>{};
    final name = stringFromValue(params['name']).trim();
    final arguments = params['arguments'] is Map
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
        arguments: arguments,
      );
      return _jsonRpcError(id, -32602, 'Unknown tool: $name');
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
    if (!await _argumentsWithinWorkspaceBeforeDeadline(
      arguments,
      processingDeadline,
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
      final approvalTimeout = _shorterDuration(
        _config.approvalTimeout,
        _remainingUntil(processingDeadline),
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
      final approved = await _approvalGate(
        McpOpsApprovalRequest(
          id: _auditId(started),
          toolName: name,
          clientName: _clientName(request),
          ipAddress: _peerAddress(request).label,
          requestedAt: started,
          expiresAt: DateTime.now().toUtc().add(approvalTimeout),
          argumentsPreview: mcpOpsClipAuditText(arguments),
        ),
      ).timeout(approvalTimeout, onTimeout: () => false);
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
      // Approval can remain open long enough for a workspace directory to be
      // replaced by a symlink. Re-resolve immediately before invocation so an
      // approved path cannot inherit a different physical target.
      if (!await _argumentsWithinWorkspaceBeforeDeadline(
        arguments,
        processingDeadline,
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

    final invocationTimeout = _shorterDuration(
      _config.timeout,
      _remainingUntil(processingDeadline),
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
    final invocationContext = McpOpsToolInvocationContext(
      invocationId: 'mcp-ops-${_auditId(started)}',
      cancelSignal: invocationCancel.future,
      deadline: DateTime.now().toUtc().add(invocationTimeout),
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
      final durationMs = DateTime.now()
          .toUtc()
          .difference(started)
          .inMilliseconds;
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
    } catch (error) {
      final durationMs = DateTime.now()
          .toUtc()
          .difference(started)
          .inMilliseconds;
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
        errorMessage: '$error',
      );
      _recordTrafficOutcome('failed');
      _publishMetrics();
      return _jsonRpcError(id, -32000, '$error');
    }
  }

  bool _requestAllowed(shelf.Request request, String method, int inboundBytes) {
    final now = DateTime.now().toUtc();
    _requestTimes.removeWhere(
      (item) => now.difference(item).inSeconds >= _rateWindowSeconds,
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
    if (!_requestTransportAllowed(request, method, inboundBytes, now: now)) {
      return false;
    }
    _requestTimes.add(now);
    return true;
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
      if (expected == null || provided != expected) {
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

  Future<bool> _argumentsWithinWorkspaceBeforeDeadline(
    Map<String, Object?> arguments,
    DateTime processingDeadline,
  ) {
    final timeout = _shorterDuration(
      _mcpOpsWorkspacePathCheckTimeout,
      _remainingUntil(processingDeadline),
    );
    if (timeout <= Duration.zero) return Future<bool>.value(false);
    return _argumentsWithinWorkspace(
      arguments,
    ).timeout(timeout, onTimeout: () => false);
  }

  Future<bool> _argumentsWithinWorkspace(Map<String, Object?> arguments) async {
    final root = nullIfBlank(_config.workspaceRoot);
    if (root == null) return true;
    final normalizedRoot = p.normalize(p.absolute(root));
    final pathScan = _scanMcpOpsPathArguments(arguments);
    if (!pathScan.valid) return false;
    for (final path in pathScan.values) {
      final normalizedPath = p.normalize(p.absolute(path));
      if (!isPathWithinOrEqual(normalizedRoot, normalizedPath) ||
          !await isPhysicalPathWithinOrEqual(normalizedRoot, normalizedPath)) {
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
    // tools/call resolves its terminal outcome later in _handleToolCall; every
    // other allowed method is a completed success at this point.
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
    // When payload capture is off we still emit the audit trail (stage, timing,
    // peer, byte counts) but drop request/response bodies and their token
    // estimates so no tool payload is retained at rest.
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
          'query': request.requestedUri.query,
          'user_agent': request.headers['user-agent'],
          'mcp_protocol_version': request.headers['mcp-protocol-version'],
          'origin': request.headers['origin'],
          'referer': request.headers['referer'],
          'peer_ip': peer.ipAddress,
          if (peer.port != null) 'peer_port': peer.port,
          'write_mode': _config.writeMode.storageValue,
          'network_mode': _config.networkMode.storageValue,
        },
      ),
    );
  }

  /// Audits protocol-stage traffic (handshake / heartbeat / discovery / stream
  /// / session / notification) that isn't a `tools/call`, so the audit console
  /// reflects the full request lifecycle instead of only tool invocations.
  /// Also bumps the request counters via [_markRequest].
  void _recordLifecycle(
    shelf.Request request, {
    required String method,
    required DateTime started,
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
      durationMs: _elapsedMs(started),
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

  int _elapsedMs(DateTime started) =>
      DateTime.now().toUtc().difference(started).inMilliseconds;

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
        'content-type': 'application/json; charset=utf-8',
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
      'mcp-protocol-version': _protocolVersion,
      'mcp-session-id': _sessionIdForRequest(request),
    };
  }

  String _sessionIdForRequest(shelf.Request request) {
    final provided = nullIfBlank(request.headers['mcp-session-id']);
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
    final auth = request.headers['authorization'] ?? '';
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
    if (value == null || value <= 0 || value > 65535) return null;
    return value;
  }

  String _clientName(shelf.Request request) {
    return nullIfBlank(request.headers['mcp-client-name']) ??
        nullIfBlank(request.headers['x-openhand-client']) ??
        nullIfBlank(request.headers['user-agent']) ??
        'unknown';
  }

  String _protocol(shelf.Request request) {
    return nullIfBlank(request.headers['mcp-protocol-version']) ??
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

  Duration _remainingUntil(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now().toUtc());
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  Duration _shorterDuration(Duration first, Duration second) {
    return first < second ? first : second;
  }

  void _increment(Map<String, int> map, String key) {
    var normalized = nullIfBlank(key) ?? 'unknown';
    if (normalized.length > _maxMetricKeyChars) {
      normalized = normalized.substring(0, _maxMetricKeyChars);
    }
    final existing = map[normalized];
    if (existing != null) {
      map[normalized] = existing + 1;
      return;
    }
    if (map.length < _maxMetricDistributionKeys - 1) {
      map[normalized] = 1;
      return;
    }
    map[_metricOverflowKey] = (map[_metricOverflowKey] ?? 0) + 1;
  }

  /// Tallies a request outcome into the current minute bucket, pruning buckets
  /// older than the retained trend window.
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

  /// Emits the last [mcpOpsTrafficWindowMinutes] minute buckets in chronological
  /// order, padding gaps with empty samples so charts render a continuous axis.
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

/// Mutable accumulator for a single UTC minute of MCP traffic.
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

bool _mcpOpsTimeInRange(
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
