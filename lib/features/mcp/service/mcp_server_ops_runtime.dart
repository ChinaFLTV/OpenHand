import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../../shared/net/http_status_utils.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../model/mcp_http_headers.dart';
import '../model/mcp_server_ops.dart';

typedef McpOpsToolListProvider = List<McpOpsToolDefinition> Function();
typedef McpOpsToolInvoker =
    Future<McpOpsToolInvocationResult> Function(
      McpOpsToolDefinition tool,
      Map<String, Object?> arguments,
    );
typedef McpOpsApprovalGate =
    Future<bool> Function(McpOpsApprovalRequest request);
typedef McpOpsAuditSink = void Function(McpOpsAuditEntry entry);
typedef McpOpsSnapshotSink = void Function(McpOpsRuntimeSnapshot snapshot);

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
  }) : _toolListProvider = toolListProvider,
       _toolInvoker = toolInvoker,
       _approvalGate = approvalGate,
       _auditSink = auditSink,
       _snapshotSink = snapshotSink;

  static const String _protocolVersion = '2025-11-25';
  static const String _serverName = 'OpenHand MCP Server';
  static const String _serverVersion = '1.0.0';
  static const Duration _shutdownTimeout = Duration(seconds: 5);
  static const Duration _connectivityTimeout = Duration(seconds: 3);
  static const Duration _sseKeepAliveInterval = Duration(seconds: 15);
  static const int _sseKeepAliveTicks = 480;
  static const int _maxSseStreams = 32;
  static const int _latencyWindow = 512;
  static const int _rateWindowSeconds = 60;
  static const Map<String, String> _corsHeaders = <String, String>{
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS, HEAD',
    'access-control-allow-headers':
        'accept, authorization, content-type, mcp-protocol-version, mcp-session-id, x-openhand-client, x-openhand-mcp-token, x-openhand-model, x-model',
    'access-control-expose-headers': 'mcp-protocol-version, mcp-session-id',
  };

  final McpOpsToolListProvider _toolListProvider;
  final McpOpsToolInvoker _toolInvoker;
  final McpOpsApprovalGate _approvalGate;
  final McpOpsAuditSink _auditSink;
  final McpOpsSnapshotSink _snapshotSink;

  HttpServer? _server;
  McpOpsConfig _config = const McpOpsConfig();
  McpOpsRuntimeSnapshot _snapshot = const McpOpsRuntimeSnapshot();
  final List<DateTime> _requestTimes = <DateTime>[];
  final List<int> _latencies = <int>[];
  int _activeRequests = 0;
  int _activeSseStreams = 0;
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

  McpOpsRuntimeSnapshot get snapshot => _snapshot;
  bool get isRunning => _server != null;

  Future<void> start(McpOpsConfig config) async {
    if (_server != null) return;
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
        config.listenHost,
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

  Future<void> stop() async {
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
      _activeRequests = 0;
      _activeSseStreams = 0;
      _setSnapshot(
        _snapshot.copyWith(
          lifecycle: McpOpsLifecycleState.stopped,
          clearBound: true,
          clearStartedAt: true,
          activeRequests: 0,
          currentConnections: 0,
        ),
      );
    }
  }

  Future<void> restart(McpOpsConfig config) async {
    _setSnapshot(
      _snapshot.copyWith(lifecycle: McpOpsLifecycleState.restarting),
    );
    await stop();
    await start(config);
  }

  void updateConfig(McpOpsConfig config) {
    _config = config;
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
    final host = _connectivityHost(_snapshot.boundHost ?? _config.listenHost);
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
      final body = await response.transform(utf8.decoder).join();
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
        final startedAt = DateTime.now().toUtc();
        _activeRequests += 1;
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
          _activeRequests = math.max(0, _activeRequests - 1);
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
    return shelf.Response(HttpStatus.noContent, headers: _corsHeaders);
  }

  /// Single entrypoint for the Streamable HTTP endpoint, dispatching by method
  /// regardless of the request path so `/`, `/mcp` and `/mcp/` behave alike.
  FutureOr<shelf.Response> _dispatchMcp(shelf.Request request) {
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
          headers: <String, String>{..._corsHeaders, ..._sessionHeaders(request)},
        );
      default:
        return shelf.Response(
          HttpStatus.methodNotAllowed,
          body: 'Method not allowed on the OpenHand MCP endpoint',
          headers: const <String, String>{
            ..._corsHeaders,
            'allow': 'GET, POST, DELETE, OPTIONS, HEAD',
            'content-type': 'text/plain; charset=utf-8',
          },
        );
    }
  }

  shelf.Response _terminateSession(shelf.Request request) {
    return shelf.Response(
      HttpStatus.noContent,
      headers: <String, String>{..._corsHeaders, ..._sessionHeaders(request)},
    );
  }

  shelf.Response _sseStream(shelf.Request request) {
    const method = 'stream/get';
    if (!_requestAllowed(request, method, 0)) {
      return shelf.Response(
        HttpStatus.forbidden,
        body: 'Request blocked by OpenHand policy',
        headers: const <String, String>{
          ..._corsHeaders,
          'content-type': 'text/plain; charset=utf-8',
        },
      );
    }
    _markRequest(request, method);
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
          ..._corsHeaders,
          'content-type': 'text/plain; charset=utf-8',
        },
      );
    }
    _activeSseStreams += 1;
    _publishConnectionSnapshot();
    return shelf.Response.ok(
      _sseKeepAliveStream(),
      headers: <String, String>{
        ..._corsHeaders,
        ..._sessionHeaders(request),
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache, no-transform',
        'connection': 'keep-alive',
        'x-accel-buffering': 'no',
      },
    );
  }

  Stream<List<int>> _sseKeepAliveStream() async* {
    try {
      yield utf8.encode(': OpenHand MCP stream ready\n\n');
      for (var index = 0; index < _sseKeepAliveTicks; index++) {
        await Future<void>.delayed(_sseKeepAliveInterval);
        yield utf8.encode(
          ': keepalive ${DateTime.now().toUtc().toIso8601String()}\n\n',
        );
      }
    } finally {
      _activeSseStreams = math.max(0, _activeSseStreams - 1);
      _publishConnectionSnapshot();
    }
  }

  Future<shelf.Response> _jsonRpc(shelf.Request request) async {
    final body = await request.readAsString();
    final inboundBytes = utf8.encode(body).length;
    _inboundBytes += inboundBytes;
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
      final responses = <Object?>[];
      for (final item in decoded) {
        final response = await _handleJsonRpcMessage(
          request,
          item,
          inboundBytes: inboundBytes,
        );
        if (response != null) responses.add(response);
      }
      if (responses.isEmpty) {
        return shelf.Response(
          HttpStatus.accepted,
          headers: <String, String>{
            ..._corsHeaders,
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
    );
    if (response == null) {
      return shelf.Response(
        HttpStatus.accepted,
        headers: <String, String>{..._corsHeaders, ..._sessionHeaders(request)},
      );
    }
    return _jsonResponse(response, headers: _sessionHeaders(request));
  }

  Future<Map<String, Object?>?> _handleJsonRpcMessage(
    shelf.Request request,
    Object? raw, {
    required int inboundBytes,
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
    final isNotification = !message.containsKey('id');
    if (method == 'notifications/initialized') {
      return null;
    }
    if (!_requestAllowed(request, method, inboundBytes)) {
      if (isNotification) return null;
      return _jsonRpcError(id, -32003, 'Request blocked by OpenHand policy');
    }

    switch (method) {
      case 'initialize':
        _markRequest(request, method);
        if (isNotification) return null;
        return _jsonRpcResult(id, <String, Object?>{
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
      case 'ping':
        _markRequest(request, method);
        return isNotification ? null : _jsonRpcResult(id, const {});
      case 'tools/list':
        _markRequest(request, method);
        return isNotification
            ? null
            : _jsonRpcResult(id, <String, Object?>{
                'tools': _toolListProvider()
                    .map((item) => item.toMcpJson())
                    .toList(growable: false),
              });
      case 'resources/list':
        _markRequest(request, method);
        return isNotification
            ? null
            : _jsonRpcResult(id, const <String, Object?>{'resources': []});
      case 'tools/call':
        if (isNotification) return null;
        return _handleToolCall(
          request,
          id,
          message,
          inboundBytes: inboundBytes,
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
    if (!_argumentsWithinWorkspace(arguments)) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason:
            'Tool arguments reference a path outside the configured workspace.',
        method: 'tools/call',
        toolName: name,
        arguments: arguments,
      );
      return _jsonRpcError(id, -32006, 'Path is outside the workspace scope');
    }
    if (tool.isWrite && _config.writeMode == McpOpsWriteMode.approvalRequired) {
      final approved = await _approvalGate(
        McpOpsApprovalRequest(
          id: _auditId(started),
          toolName: name,
          clientName: _clientName(request),
          ipAddress: _ipAddress(request),
          requestedAt: started,
          expiresAt: started.add(_config.approvalTimeout),
          argumentsPreview: mcpOpsClipAuditText(arguments),
        ),
      ).timeout(_config.approvalTimeout, onTimeout: () => false);
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
    }

    _markRequest(request, 'tools/call', toolName: name);
    try {
      final result = await _toolInvoker(tool, arguments).timeout(
        _config.timeout,
        onTimeout: () => const McpOpsToolInvocationResult(
          text: 'MCP tool call timed out.',
          isError: true,
        ),
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
        status: result.isError ? 'failed' : 'success',
        durationMs: durationMs,
        inboundBytes: inboundBytes,
        outboundBytes: outboundBytes,
        arguments: arguments,
        responsePreview: result.text,
        errorMessage: result.isError ? result.text : '',
      );
      if (result.isError) _failedTotal += 1;
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
        status: 'failed',
        durationMs: durationMs,
        inboundBytes: inboundBytes,
        outboundBytes: 0,
        arguments: arguments,
        errorMessage: '$error',
      );
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
    if (!_networkAllowsIp(_ipAddress(request))) {
      _recordBlocked(
        request,
        inboundBytes: inboundBytes,
        reason: 'IP address is outside the configured network mode.',
        method: method,
      );
      return false;
    }
    if (!_timeWindowAllows(now.toLocal())) {
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
    _requestTimes.add(now);
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

  bool _argumentsWithinWorkspace(Map<String, Object?> arguments) {
    final root = nullIfBlank(_config.workspaceRoot);
    if (root == null) return true;
    final normalizedRoot = p.normalize(p.absolute(root));
    for (final path in _pathLikeArgumentValues(arguments)) {
      final normalizedPath = p.normalize(p.absolute(path));
      if (normalizedPath == normalizedRoot) continue;
      if (!p.isWithin(normalizedRoot, normalizedPath)) {
        return false;
      }
    }
    return true;
  }

  Iterable<String> _pathLikeArgumentValues(
    Object? value, [
    String key = '',
  ]) sync* {
    if (value is Map) {
      for (final entry in value.entries) {
        yield* _pathLikeArgumentValues(entry.value, '${entry.key}');
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        yield* _pathLikeArgumentValues(item, key);
      }
      return;
    }
    if (value is! String) return;
    final lowerKey = key.toLowerCase();
    final keyLooksPath =
        lowerKey.contains('path') ||
        lowerKey.contains('file') ||
        lowerKey.contains('dir') ||
        lowerKey.contains('workspace');
    if (!keyLooksPath) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    yield trimmed;
  }

  void _markRequest(shelf.Request request, String method, {String? toolName}) {
    _requestTotal += 1;
    _increment(_ipDistribution, _ipAddress(request));
    _increment(_clientDistribution, _clientName(request));
    _increment(_requestDistribution, toolName ?? method);
    _increment(_protocolDistribution, _protocol(request));
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
    _increment(_ipDistribution, _ipAddress(request));
    _increment(_clientDistribution, _clientName(request));
    _increment(_requestDistribution, toolName ?? method);
    _increment(_protocolDistribution, _protocol(request));
    _recordAudit(
      request,
      status: 'blocked',
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
    required String status,
    required int durationMs,
    required int inboundBytes,
    required int outboundBytes,
    Map<String, Object?> arguments = const <String, Object?>{},
    String responsePreview = '',
    String errorMessage = '',
  }) {
    final now = DateTime.now().toUtc();
    final argumentText = mcpOpsClipAuditText(arguments);
    final responseText = mcpOpsClipAuditText(responsePreview);
    final promptTokens = _estimateTokens(argumentText);
    final completionTokens = _estimateTokens(responseText);
    _auditSink(
      McpOpsAuditEntry(
        id: _auditId(now),
        timestamp: now,
        toolName: tool?.name ?? toolName ?? '',
        surface: tool?.surface.storageValue ?? surface ?? '',
        endpoint: tool?.endpointId ?? endpoint ?? '',
        status: status,
        protocol: _protocol(request),
        model: _model(request),
        clientName: _clientName(request),
        ipAddress: _ipAddress(request),
        durationMs: durationMs,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
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
          'write_mode': _config.writeMode.storageValue,
          'network_mode': _config.networkMode.storageValue,
        },
      ),
    );
  }

  void _publishMetrics() {
    _setSnapshot(
      _snapshot.copyWith(
        activeRequests: _activeRequests,
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

  void _publishConnectionSnapshot() {
    _setSnapshot(
      _snapshot.copyWith(
        activeRequests: _activeRequests,
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
        ..._corsHeaders,
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
      _sessionIds.add(provided);
      return provided;
    }
    final generated =
        'openhand-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 20)}';
    _sessionIds.add(generated);
    if (_sessionIds.length > 1024) {
      _sessionIds.remove(_sessionIds.first);
    }
    return generated;
  }

  String _requestToken(shelf.Request request) {
    final direct = nullIfBlank(request.headers['x-openhand-mcp-token']);
    if (direct != null) return direct;
    final auth = request.headers['authorization'] ?? '';
    final lower = auth.toLowerCase();
    if (lower.startsWith('bearer ')) return auth.substring(7).trim();
    return '';
  }

  String _ipAddress(shelf.Request request) {
    final forwarded = nullIfBlank(request.headers['x-forwarded-for']);
    if (forwarded != null) {
      return forwarded.split(',').first.trim();
    }
    final info = request.context['shelf.io.connection_info'];
    if (info is HttpConnectionInfo) {
      return info.remoteAddress.address;
    }
    return 'unknown';
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

  String _connectivityHost(String host) {
    final normalized = host.trim();
    if (normalized.isEmpty || normalized == '0.0.0.0' || normalized == '::') {
      return '127.0.0.1';
    }
    return normalized;
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
    final normalized = nullIfBlank(key) ?? 'unknown';
    map[normalized] = (map[normalized] ?? 0) + 1;
  }
}
