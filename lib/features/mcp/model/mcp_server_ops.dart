import '../../../shared/util/duration_bounds.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';

const String mcpOpsDefaultListenHost = '127.0.0.1';
const int mcpOpsDefaultListenPort = 8765;
const int mcpOpsMinListenPort = 1;
const int mcpOpsMaxListenPort = 65535;
const int mcpOpsDefaultRpmLimit = 120;
const int mcpOpsMaxRpmLimit = 6000;
const int mcpOpsDefaultCallThreshold = 0;
const int mcpOpsMaxCallThreshold = 1000000;
const int mcpOpsDefaultTimeoutMs = 30000;
const int mcpOpsMinTimeoutMs = 1000;
const int mcpOpsMaxTimeoutMs = 600000;
const int mcpOpsDefaultApprovalTimeoutMs = 45000;
const int mcpOpsMaxAuditEntries = 300;
const int mcpOpsAuditPreviewMaxChars = 2800;
const int mcpOpsMaxPersistedAuditEntries = 1200;
const int mcpOpsMaxMetricDistributionKeys = 256;
const int mcpOpsMetricKeyMaxChars = 160;
const String mcpOpsMetricOverflowKey = 'other';

/// Number of minute-level buckets retained for traffic/latency trend charts.
const int mcpOpsTrafficWindowMinutes = 12;

enum McpOpsLifecycleState {
  stopped,
  starting,
  running,
  restarting,
  stopping,
  failed,
}

McpOpsLifecycleState mcpOpsLifecycleStateFromValue(Object? value) {
  return enumByNameOr(
    McpOpsLifecycleState.values,
    value,
    fallback: McpOpsLifecycleState.stopped,
    normalize: _normalizeOpsEnumValue,
  );
}

enum McpOpsWriteMode {
  approvalRequired('approval_required'),
  fullAccess('full_access'),
  readOnly('read_only');

  const McpOpsWriteMode(this.storageValue);

  final String storageValue;

  static McpOpsWriteMode fromValue(Object? value) {
    return enumByStorageValueOr(
      values,
      value,
      (item) => item.storageValue,
      fallback: approvalRequired,
      normalize: _normalizeOpsEnumValue,
    );
  }
}

enum McpOpsNetworkMode {
  loopbackOnly('loopback_only'),
  lan('lan'),
  custom('custom');

  const McpOpsNetworkMode(this.storageValue);

  final String storageValue;

  static McpOpsNetworkMode fromValue(Object? value) {
    return enumByStorageValueOr(
      values,
      value,
      (item) => item.storageValue,
      fallback: loopbackOnly,
      normalize: _normalizeOpsEnumValue,
    );
  }
}

enum McpOpsInvocationMode {
  direct('direct'),
  queued('queued'),
  guarded('guarded');

  const McpOpsInvocationMode(this.storageValue);

  final String storageValue;

  static McpOpsInvocationMode fromValue(Object? value) {
    return enumByStorageValueOr(
      values,
      value,
      (item) => item.storageValue,
      fallback: guarded,
      normalize: _normalizeOpsEnumValue,
    );
  }
}

enum McpOpsExposureSurface {
  builtinTools('builtin_tools'),
  memory('memory'),
  skills('skills'),
  instructions('instructions'),
  knowledgeBase('knowledge_base'),
  mcpServers('mcp_servers');

  const McpOpsExposureSurface(this.storageValue);

  final String storageValue;

  static McpOpsExposureSurface? fromValue(Object? value) {
    return enumByStorageValue(
      values,
      value,
      (item) => item.storageValue,
      normalize: _normalizeOpsEnumValue,
    );
  }
}

class McpOpsConfig {
  const McpOpsConfig({
    this.autoStart = false,
    this.listenHost = mcpOpsDefaultListenHost,
    this.listenPort = mcpOpsDefaultListenPort,
    this.networkMode = McpOpsNetworkMode.loopbackOnly,
    this.invocationMode = McpOpsInvocationMode.guarded,
    this.writeMode = McpOpsWriteMode.approvalRequired,
    this.requireAuthToken = false,
    this.authToken = '',
    this.allowedClients = const <String>[],
    this.allowedIpCidrs = const <String>[],
    this.allowedTimeWindows = const <String>['00:00-23:59'],
    this.workspaceRoot = '',
    this.rpmLimit = mcpOpsDefaultRpmLimit,
    this.callThreshold = mcpOpsDefaultCallThreshold,
    this.timeoutMs = mcpOpsDefaultTimeoutMs,
    this.approvalTimeoutMs = mcpOpsDefaultApprovalTimeoutMs,
    this.capturePayload = true,
    this.exposedSurfaces = const <McpOpsExposureSurface>{
      McpOpsExposureSurface.builtinTools,
      McpOpsExposureSurface.memory,
      McpOpsExposureSurface.skills,
      McpOpsExposureSurface.instructions,
      McpOpsExposureSurface.knowledgeBase,
      McpOpsExposureSurface.mcpServers,
    },
    this.hiddenItemIds = const <String>{},
    this.hiddenEndpointIds = const <String>{},
  });

  final bool autoStart;
  final String listenHost;
  final int listenPort;
  final McpOpsNetworkMode networkMode;
  final McpOpsInvocationMode invocationMode;
  final McpOpsWriteMode writeMode;
  final bool requireAuthToken;
  final String authToken;
  final List<String> allowedClients;
  final List<String> allowedIpCidrs;
  final List<String> allowedTimeWindows;
  final String workspaceRoot;
  final int rpmLimit;
  final int callThreshold;
  final int timeoutMs;
  final int approvalTimeoutMs;
  final bool capturePayload;
  final Set<McpOpsExposureSurface> exposedSurfaces;
  final Set<String> hiddenItemIds;
  final Set<String> hiddenEndpointIds;

  bool surfaceEnabled(McpOpsExposureSurface surface) {
    return exposedSurfaces.contains(surface);
  }

  bool itemVisible(McpOpsExposureSurface surface, String itemId) {
    return surfaceEnabled(surface) &&
        !hiddenItemIds.contains(mcpOpsItemKey(surface, itemId));
  }

  bool endpointVisible(McpOpsExposureSurface surface, String endpointId) {
    return surfaceEnabled(surface) &&
        !hiddenEndpointIds.contains(mcpOpsEndpointKey(surface, endpointId));
  }

  Duration get timeout => Duration(milliseconds: timeoutMs);
  Duration get approvalTimeout => Duration(milliseconds: approvalTimeoutMs);

  McpOpsConfig copyWith({
    bool? autoStart,
    String? listenHost,
    int? listenPort,
    McpOpsNetworkMode? networkMode,
    McpOpsInvocationMode? invocationMode,
    McpOpsWriteMode? writeMode,
    bool? requireAuthToken,
    String? authToken,
    List<String>? allowedClients,
    List<String>? allowedIpCidrs,
    List<String>? allowedTimeWindows,
    String? workspaceRoot,
    int? rpmLimit,
    int? callThreshold,
    int? timeoutMs,
    int? approvalTimeoutMs,
    bool? capturePayload,
    Set<McpOpsExposureSurface>? exposedSurfaces,
    Set<String>? hiddenItemIds,
    Set<String>? hiddenEndpointIds,
  }) {
    return McpOpsConfig(
      autoStart: autoStart ?? this.autoStart,
      listenHost: _normalizeListenHost(listenHost ?? this.listenHost),
      listenPort: _normalizePort(listenPort ?? this.listenPort),
      networkMode: networkMode ?? this.networkMode,
      invocationMode: invocationMode ?? this.invocationMode,
      writeMode: writeMode ?? this.writeMode,
      requireAuthToken: requireAuthToken ?? this.requireAuthToken,
      authToken: authToken ?? this.authToken,
      allowedClients: _normalizeStringList(
        allowedClients ?? this.allowedClients,
      ),
      allowedIpCidrs: _normalizeStringList(
        allowedIpCidrs ?? this.allowedIpCidrs,
      ),
      allowedTimeWindows: _normalizeStringList(
        allowedTimeWindows ?? this.allowedTimeWindows,
        fallback: const <String>['00:00-23:59'],
      ),
      workspaceRoot: (workspaceRoot ?? this.workspaceRoot).trim(),
      rpmLimit: _normalizeInt(
        rpmLimit ?? this.rpmLimit,
        min: 0,
        max: mcpOpsMaxRpmLimit,
      ),
      callThreshold: _normalizeInt(
        callThreshold ?? this.callThreshold,
        min: 0,
        max: mcpOpsMaxCallThreshold,
      ),
      timeoutMs: _normalizeInt(
        timeoutMs ?? this.timeoutMs,
        min: mcpOpsMinTimeoutMs,
        max: mcpOpsMaxTimeoutMs,
      ),
      approvalTimeoutMs: _normalizeInt(
        approvalTimeoutMs ?? this.approvalTimeoutMs,
        min: mcpOpsMinTimeoutMs,
        max: mcpOpsMaxTimeoutMs,
      ),
      capturePayload: capturePayload ?? this.capturePayload,
      exposedSurfaces: exposedSurfaces ?? this.exposedSurfaces,
      hiddenItemIds: hiddenItemIds ?? this.hiddenItemIds,
      hiddenEndpointIds: hiddenEndpointIds ?? this.hiddenEndpointIds,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'auto_start': autoStart,
      'listen_host': listenHost,
      'listen_port': listenPort,
      'network_mode': networkMode.storageValue,
      'invocation_mode': invocationMode.storageValue,
      'write_mode': writeMode.storageValue,
      'require_auth_token': requireAuthToken,
      if (authToken.trim().isNotEmpty) 'auth_token': authToken.trim(),
      'allowed_clients': List<String>.from(allowedClients),
      'allowed_ip_cidrs': List<String>.from(allowedIpCidrs),
      'allowed_time_windows': List<String>.from(allowedTimeWindows),
      if (workspaceRoot.trim().isNotEmpty) 'workspace_root': workspaceRoot,
      'rpm_limit': rpmLimit,
      'call_threshold': callThreshold,
      'timeout_ms': timeoutMs,
      'approval_timeout_ms': approvalTimeoutMs,
      'capture_payload': capturePayload,
      'exposed_surfaces': exposedSurfaces
          .map((item) => item.storageValue)
          .toList(growable: false),
      'hidden_item_ids': List<String>.from(hiddenItemIds),
      'hidden_endpoint_ids': List<String>.from(hiddenEndpointIds),
    };
  }

  static McpOpsConfig fromJson(Object? raw) {
    if (raw is! Map) {
      return const McpOpsConfig();
    }
    final map = stringKeyedMapFromValue(raw);
    final exposed = <McpOpsExposureSurface>{};
    for (final value in stringListFromValue(map['exposed_surfaces'])) {
      final surface = McpOpsExposureSurface.fromValue(value);
      if (surface != null) exposed.add(surface);
    }
    return McpOpsConfig(
      autoStart: boolFromValue(map['auto_start']),
      listenHost: _normalizeListenHost(stringFromValue(map['listen_host'])),
      listenPort: _normalizePort(
        nonNegativeIntFromValue(
          map['listen_port'],
          fallback: mcpOpsDefaultListenPort,
        ),
      ),
      networkMode: McpOpsNetworkMode.fromValue(map['network_mode']),
      invocationMode: McpOpsInvocationMode.fromValue(map['invocation_mode']),
      writeMode: McpOpsWriteMode.fromValue(map['write_mode']),
      requireAuthToken: boolFromValue(map['require_auth_token']),
      authToken: stringFromValue(map['auth_token']).trim(),
      allowedClients: _normalizeStringList(
        stringListFromValue(map['allowed_clients']),
      ),
      allowedIpCidrs: _normalizeStringList(
        stringListFromValue(map['allowed_ip_cidrs']),
      ),
      allowedTimeWindows: _normalizeStringList(
        stringListFromValue(map['allowed_time_windows']),
        fallback: const <String>['00:00-23:59'],
      ),
      workspaceRoot: stringFromValue(map['workspace_root']).trim(),
      rpmLimit: _normalizeInt(
        nonNegativeIntFromValue(
          map['rpm_limit'],
          fallback: mcpOpsDefaultRpmLimit,
        ),
        min: 0,
        max: mcpOpsMaxRpmLimit,
      ),
      callThreshold: _normalizeInt(
        nonNegativeIntFromValue(
          map['call_threshold'],
          fallback: mcpOpsDefaultCallThreshold,
        ),
        min: 0,
        max: mcpOpsMaxCallThreshold,
      ),
      timeoutMs: _normalizeInt(
        nonNegativeIntFromValue(
          map['timeout_ms'],
          fallback: mcpOpsDefaultTimeoutMs,
        ),
        min: mcpOpsMinTimeoutMs,
        max: mcpOpsMaxTimeoutMs,
      ),
      approvalTimeoutMs: _normalizeInt(
        nonNegativeIntFromValue(
          map['approval_timeout_ms'],
          fallback: mcpOpsDefaultApprovalTimeoutMs,
        ),
        min: mcpOpsMinTimeoutMs,
        max: mcpOpsMaxTimeoutMs,
      ),
      capturePayload: boolFromValue(map['capture_payload'], defaultValue: true),
      exposedSurfaces: exposed.isEmpty
          ? const McpOpsConfig().exposedSurfaces
          : exposed,
      hiddenItemIds: stringListFromValue(map['hidden_item_ids']).toSet(),
      hiddenEndpointIds: stringListFromValue(
        map['hidden_endpoint_ids'],
      ).toSet(),
    );
  }
}

class McpOpsToolDefinition {
  const McpOpsToolDefinition({
    required this.name,
    required this.title,
    required this.description,
    required this.surface,
    required this.itemId,
    required this.endpointId,
    required this.inputSchema,
    this.isWrite = false,
  });

  final String name;
  final String title;
  final String description;
  final McpOpsExposureSurface surface;
  final String itemId;
  final String endpointId;
  final Map<String, Object?> inputSchema;
  final bool isWrite;

  Map<String, Object?> toMcpJson() {
    return <String, Object?>{
      'name': name,
      'title': title,
      'description': description,
      'inputSchema': inputSchema,
      'annotations': <String, Object?>{
        'openhandSurface': surface.storageValue,
        'openhandItemId': itemId,
        'openhandEndpointId': endpointId,
        'readOnlyHint': !isWrite,
        'destructiveHint': isWrite,
      },
    };
  }
}

class McpOpsToolInvocationResult {
  const McpOpsToolInvocationResult({
    required this.text,
    this.isError = false,
    this.metadata = const <String, Object?>{},
  });

  final String text;
  final bool isError;
  final Map<String, Object?> metadata;
}

/// Coarse classification of an audit event's protocol stage ("环节"), used to
/// drive titles, icons and accent colors in the audit UI. Kept independent of
/// [McpOpsAuditEntry.status] so a blocked handshake still reads as a handshake.
enum McpOpsAuditKind {
  handshake,
  heartbeat,
  discovery,
  invocation,
  stream,
  session,
  notification,
  other,
}

McpOpsAuditKind mcpOpsAuditKindFromValue(Object? value) {
  return enumByNameOr(
    McpOpsAuditKind.values,
    value,
    fallback: McpOpsAuditKind.other,
    normalize: _normalizeOpsEnumValue,
  );
}

class McpOpsAuditEntry {
  const McpOpsAuditEntry({
    required this.id,
    required this.timestamp,
    required this.toolName,
    required this.surface,
    required this.endpoint,
    required this.status,
    required this.protocol,
    required this.model,
    required this.clientName,
    required this.ipAddress,
    required this.durationMs,
    required this.promptTokens,
    required this.completionTokens,
    required this.inboundBytes,
    required this.outboundBytes,
    this.kind = McpOpsAuditKind.other,
    this.errorMessage = '',
    this.requestSummary = '',
    this.argumentsPreview = '',
    this.responsePreview = '',
    this.environment = const <String, Object?>{},
  });

  final String id;
  final DateTime timestamp;
  final String toolName;
  final String surface;
  final String endpoint;
  final String status;
  final String protocol;
  final String model;
  final String clientName;
  final String ipAddress;
  final int durationMs;
  final int promptTokens;
  final int completionTokens;
  final int inboundBytes;
  final int outboundBytes;
  final McpOpsAuditKind kind;
  final String errorMessage;
  final String requestSummary;
  final String argumentsPreview;
  final String responsePreview;
  final Map<String, Object?> environment;

  int get totalTokens => promptTokens + completionTokens;
  bool get blocked => status == 'blocked';
  bool get errored => status == 'failed';
  bool get failed => errored || blocked;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'tool_name': toolName,
      'surface': surface,
      'endpoint': endpoint,
      'status': status,
      'protocol': protocol,
      'model': model,
      'client_name': clientName,
      'ip_address': ipAddress,
      'duration_ms': durationMs,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'inbound_bytes': inboundBytes,
      'outbound_bytes': outboundBytes,
      'kind': kind.name,
      if (errorMessage.isNotEmpty) 'error_message': errorMessage,
      if (requestSummary.isNotEmpty) 'request_summary': requestSummary,
      if (argumentsPreview.isNotEmpty) 'arguments_preview': argumentsPreview,
      if (responsePreview.isNotEmpty) 'response_preview': responsePreview,
      if (environment.isNotEmpty) 'environment': environment,
    };
  }

  static McpOpsAuditEntry fromJson(Object? raw) {
    final map = stringKeyedMapFromValue(raw);
    final timestamp =
        utcDateTimeFromValue(map['timestamp']) ?? DateTime.now().toUtc();
    return McpOpsAuditEntry(
      id: stringFromValue(
        map['id'],
        fallback: 'restored-${timestamp.microsecondsSinceEpoch}',
      ),
      timestamp: timestamp,
      toolName: stringFromValue(map['tool_name']),
      surface: stringFromValue(map['surface']),
      endpoint: stringFromValue(map['endpoint']),
      status: stringFromValue(map['status'], fallback: 'success'),
      protocol: stringFromValue(map['protocol']),
      model: stringFromValue(map['model']),
      clientName: stringFromValue(map['client_name'], fallback: 'unknown'),
      ipAddress: stringFromValue(map['ip_address'], fallback: 'unknown'),
      durationMs: nonNegativeIntFromValue(map['duration_ms'], fallback: 0),
      promptTokens: nonNegativeIntFromValue(map['prompt_tokens'], fallback: 0),
      completionTokens: nonNegativeIntFromValue(
        map['completion_tokens'],
        fallback: 0,
      ),
      inboundBytes: nonNegativeIntFromValue(map['inbound_bytes'], fallback: 0),
      outboundBytes: nonNegativeIntFromValue(
        map['outbound_bytes'],
        fallback: 0,
      ),
      kind: mcpOpsAuditKindFromValue(map['kind']),
      errorMessage: stringFromValue(map['error_message']),
      requestSummary: stringFromValue(map['request_summary']),
      argumentsPreview: stringFromValue(map['arguments_preview']),
      responsePreview: stringFromValue(map['response_preview']),
      environment: stringKeyedMapFromValue(map['environment']),
    );
  }
}

class McpOpsApprovalRequest {
  const McpOpsApprovalRequest({
    required this.id,
    required this.toolName,
    required this.clientName,
    required this.ipAddress,
    required this.requestedAt,
    required this.expiresAt,
    required this.argumentsPreview,
  });

  final String id;
  final String toolName;
  final String clientName;
  final String ipAddress;
  final DateTime requestedAt;
  final DateTime expiresAt;
  final String argumentsPreview;
}

/// Minute-level rollup of MCP traffic. Backs the trend/latency charts so the
/// dashboard reflects *every* request (initialize/list/stream/call), not only
/// audited tool calls.
class McpOpsTrafficSample {
  const McpOpsTrafficSample({
    required this.minute,
    this.success = 0,
    this.blocked = 0,
    this.failed = 0,
    this.avgLatencyMs = 0,
    this.p95LatencyMs = 0,
  });

  /// UTC minute-aligned bucket start.
  final DateTime minute;
  final int success;
  final int blocked;
  final int failed;
  final int avgLatencyMs;
  final int p95LatencyMs;

  int get total => success + blocked + failed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'minute': minute.toUtc().toIso8601String(),
      'success': success,
      'blocked': blocked,
      'failed': failed,
      'avg_latency_ms': avgLatencyMs,
      'p95_latency_ms': p95LatencyMs,
    };
  }

  static McpOpsTrafficSample fromJson(Object? raw) {
    final map = stringKeyedMapFromValue(raw);
    return McpOpsTrafficSample(
      minute: utcDateTimeFromValue(map['minute']) ?? DateTime.now().toUtc(),
      success: nonNegativeIntFromValue(map['success'], fallback: 0),
      blocked: nonNegativeIntFromValue(map['blocked'], fallback: 0),
      failed: nonNegativeIntFromValue(map['failed'], fallback: 0),
      avgLatencyMs: nonNegativeIntFromValue(map['avg_latency_ms'], fallback: 0),
      p95LatencyMs: nonNegativeIntFromValue(map['p95_latency_ms'], fallback: 0),
    );
  }

  McpOpsTrafficSample copyWith({
    int? success,
    int? blocked,
    int? failed,
    int? avgLatencyMs,
    int? p95LatencyMs,
  }) {
    return McpOpsTrafficSample(
      minute: minute,
      success: success ?? this.success,
      blocked: blocked ?? this.blocked,
      failed: failed ?? this.failed,
      avgLatencyMs: avgLatencyMs ?? this.avgLatencyMs,
      p95LatencyMs: p95LatencyMs ?? this.p95LatencyMs,
    );
  }
}

class McpOpsRuntimeSnapshot {
  const McpOpsRuntimeSnapshot({
    this.lifecycle = McpOpsLifecycleState.stopped,
    this.boundHost,
    this.boundPort,
    this.startedAt,
    this.lastConnectivityAt,
    this.lastConnectivityOk = false,
    this.lastConnectivityMessage = '',
    this.currentConnections = 0,
    this.activeRequests = 0,
    this.activeStreams = 0,
    this.sessionCount = 0,
    this.requestTotal = 0,
    this.blockedTotal = 0,
    this.failedTotal = 0,
    this.inboundBytes = 0,
    this.outboundBytes = 0,
    this.avgLatencyMs = 0,
    this.p95LatencyMs = 0,
    this.fileMutationCount = 0,
    this.memoryRssBytes = 0,
    this.errorMessage,
    this.ipDistribution = const <String, int>{},
    this.clientDistribution = const <String, int>{},
    this.requestDistribution = const <String, int>{},
    this.protocolDistribution = const <String, int>{},
    this.trafficSeries = const <McpOpsTrafficSample>[],
  });

  final McpOpsLifecycleState lifecycle;
  final String? boundHost;
  final int? boundPort;
  final DateTime? startedAt;
  final DateTime? lastConnectivityAt;
  final bool lastConnectivityOk;
  final String lastConnectivityMessage;
  final int currentConnections;
  final int activeRequests;
  final int activeStreams;
  final int sessionCount;
  final int requestTotal;
  final int blockedTotal;
  final int failedTotal;
  final int inboundBytes;
  final int outboundBytes;
  final int avgLatencyMs;
  final int p95LatencyMs;
  final int fileMutationCount;
  final int memoryRssBytes;
  final String? errorMessage;
  final Map<String, int> ipDistribution;
  final Map<String, int> clientDistribution;
  final Map<String, int> requestDistribution;
  final Map<String, int> protocolDistribution;
  final List<McpOpsTrafficSample> trafficSeries;

  /// Live SSE streams held open beyond the request/response cycle.
  int get idleStreams =>
      (currentConnections - activeRequests).clamp(0, 1 << 30);
  int get successTotal =>
      (requestTotal - blockedTotal - failedTotal).clamp(0, 1 << 30);

  bool get isRunning => lifecycle == McpOpsLifecycleState.running;

  Duration get uptime {
    final start = startedAt;
    if (start == null || !isRunning) return Duration.zero;
    return nonNegativeDuration(DateTime.now().toUtc().difference(start));
  }

  McpOpsRuntimeSnapshot asOfflinePersistedSnapshot() {
    return copyWith(
      lifecycle: McpOpsLifecycleState.stopped,
      clearBound: true,
      clearStartedAt: true,
      currentConnections: 0,
      activeRequests: 0,
      activeStreams: 0,
      sessionCount: 0,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'lifecycle': lifecycle.name,
      'bound_host': boundHost,
      'bound_port': boundPort,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'last_connectivity_at': lastConnectivityAt?.toUtc().toIso8601String(),
      'last_connectivity_ok': lastConnectivityOk,
      'last_connectivity_message': lastConnectivityMessage,
      'current_connections': currentConnections,
      'active_requests': activeRequests,
      'active_streams': activeStreams,
      'session_count': sessionCount,
      'request_total': requestTotal,
      'blocked_total': blockedTotal,
      'failed_total': failedTotal,
      'inbound_bytes': inboundBytes,
      'outbound_bytes': outboundBytes,
      'avg_latency_ms': avgLatencyMs,
      'p95_latency_ms': p95LatencyMs,
      'file_mutation_count': fileMutationCount,
      'memory_rss_bytes': memoryRssBytes,
      if (errorMessage != null && errorMessage!.isNotEmpty)
        'error_message': errorMessage,
      'ip_distribution': ipDistribution,
      'client_distribution': clientDistribution,
      'request_distribution': requestDistribution,
      'protocol_distribution': protocolDistribution,
      'traffic_series': trafficSeries
          .map((item) => item.toJson())
          .toList(growable: false),
    };
  }

  static McpOpsRuntimeSnapshot fromJson(Object? raw) {
    final map = stringKeyedMapFromValue(raw);
    return McpOpsRuntimeSnapshot(
      lifecycle: mcpOpsLifecycleStateFromValue(map['lifecycle']),
      boundHost: optionalStringFromValue(map['bound_host']),
      boundPort: optionalIntFromValue(map['bound_port']),
      startedAt: utcDateTimeFromValue(map['started_at']),
      lastConnectivityAt: utcDateTimeFromValue(map['last_connectivity_at']),
      lastConnectivityOk: boolFromValue(map['last_connectivity_ok']),
      lastConnectivityMessage: stringFromValue(
        map['last_connectivity_message'],
      ),
      currentConnections: nonNegativeIntFromValue(
        map['current_connections'],
        fallback: 0,
      ),
      activeRequests: nonNegativeIntFromValue(
        map['active_requests'],
        fallback: 0,
      ),
      activeStreams: nonNegativeIntFromValue(
        map['active_streams'],
        fallback: 0,
      ),
      sessionCount: nonNegativeIntFromValue(map['session_count'], fallback: 0),
      requestTotal: nonNegativeIntFromValue(map['request_total'], fallback: 0),
      blockedTotal: nonNegativeIntFromValue(map['blocked_total'], fallback: 0),
      failedTotal: nonNegativeIntFromValue(map['failed_total'], fallback: 0),
      inboundBytes: nonNegativeIntFromValue(map['inbound_bytes'], fallback: 0),
      outboundBytes: nonNegativeIntFromValue(
        map['outbound_bytes'],
        fallback: 0,
      ),
      avgLatencyMs: nonNegativeIntFromValue(map['avg_latency_ms'], fallback: 0),
      p95LatencyMs: nonNegativeIntFromValue(map['p95_latency_ms'], fallback: 0),
      fileMutationCount: nonNegativeIntFromValue(
        map['file_mutation_count'],
        fallback: 0,
      ),
      memoryRssBytes: nonNegativeIntFromValue(
        map['memory_rss_bytes'],
        fallback: 0,
      ),
      errorMessage: optionalStringFromValue(map['error_message']),
      ipDistribution: _stringIntMapFromValue(map['ip_distribution']),
      clientDistribution: _stringIntMapFromValue(map['client_distribution']),
      requestDistribution: _stringIntMapFromValue(map['request_distribution']),
      protocolDistribution: _stringIntMapFromValue(
        map['protocol_distribution'],
      ),
      trafficSeries: stringKeyedMapListFromValue(
        map['traffic_series'],
        limit: mcpOpsTrafficWindowMinutes,
        fromEnd: true,
      ).map(McpOpsTrafficSample.fromJson).toList(growable: false),
    );
  }

  McpOpsRuntimeSnapshot copyWith({
    McpOpsLifecycleState? lifecycle,
    String? boundHost,
    int? boundPort,
    bool clearBound = false,
    DateTime? startedAt,
    bool clearStartedAt = false,
    DateTime? lastConnectivityAt,
    bool? lastConnectivityOk,
    String? lastConnectivityMessage,
    int? currentConnections,
    int? activeRequests,
    int? activeStreams,
    int? sessionCount,
    int? requestTotal,
    int? blockedTotal,
    int? failedTotal,
    int? inboundBytes,
    int? outboundBytes,
    int? avgLatencyMs,
    int? p95LatencyMs,
    int? fileMutationCount,
    int? memoryRssBytes,
    String? errorMessage,
    bool clearErrorMessage = false,
    Map<String, int>? ipDistribution,
    Map<String, int>? clientDistribution,
    Map<String, int>? requestDistribution,
    Map<String, int>? protocolDistribution,
    List<McpOpsTrafficSample>? trafficSeries,
  }) {
    return McpOpsRuntimeSnapshot(
      lifecycle: lifecycle ?? this.lifecycle,
      boundHost: clearBound ? null : boundHost ?? this.boundHost,
      boundPort: clearBound ? null : boundPort ?? this.boundPort,
      startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
      lastConnectivityAt: lastConnectivityAt ?? this.lastConnectivityAt,
      lastConnectivityOk: lastConnectivityOk ?? this.lastConnectivityOk,
      lastConnectivityMessage:
          lastConnectivityMessage ?? this.lastConnectivityMessage,
      currentConnections: currentConnections ?? this.currentConnections,
      activeRequests: activeRequests ?? this.activeRequests,
      activeStreams: activeStreams ?? this.activeStreams,
      sessionCount: sessionCount ?? this.sessionCount,
      requestTotal: requestTotal ?? this.requestTotal,
      blockedTotal: blockedTotal ?? this.blockedTotal,
      failedTotal: failedTotal ?? this.failedTotal,
      inboundBytes: inboundBytes ?? this.inboundBytes,
      outboundBytes: outboundBytes ?? this.outboundBytes,
      avgLatencyMs: avgLatencyMs ?? this.avgLatencyMs,
      p95LatencyMs: p95LatencyMs ?? this.p95LatencyMs,
      fileMutationCount: fileMutationCount ?? this.fileMutationCount,
      memoryRssBytes: memoryRssBytes ?? this.memoryRssBytes,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      ipDistribution: ipDistribution ?? this.ipDistribution,
      clientDistribution: clientDistribution ?? this.clientDistribution,
      requestDistribution: requestDistribution ?? this.requestDistribution,
      protocolDistribution: protocolDistribution ?? this.protocolDistribution,
      trafficSeries: trafficSeries ?? this.trafficSeries,
    );
  }
}

class McpOpsPersistedRuntimeData {
  const McpOpsPersistedRuntimeData({
    this.snapshot,
    this.auditEntries = const <McpOpsAuditEntry>[],
  });

  final McpOpsRuntimeSnapshot? snapshot;
  final List<McpOpsAuditEntry> auditEntries;

  int get itemCount => (snapshot == null ? 0 : 1) + auditEntries.length;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (snapshot != null) 'snapshot': snapshot!.toJson(),
      'audit_entries': auditEntries
          .map((entry) => entry.toJson())
          .toList(growable: false),
    };
  }

  static McpOpsPersistedRuntimeData fromJson(Object? raw) {
    final map = stringKeyedMapFromValue(raw);
    final snapshotRaw = map['snapshot'];
    return McpOpsPersistedRuntimeData(
      snapshot: snapshotRaw is Map
          ? McpOpsRuntimeSnapshot.fromJson(snapshotRaw)
          : null,
      auditEntries: stringKeyedMapListFromValue(
        map['audit_entries'],
        limit: mcpOpsMaxPersistedAuditEntries,
      ).map(McpOpsAuditEntry.fromJson).toList(growable: false),
    );
  }
}

class McpOpsPersistenceReport {
  const McpOpsPersistenceReport({required this.bytes, required this.itemCount});

  final int bytes;
  final int itemCount;

  static const McpOpsPersistenceReport empty = McpOpsPersistenceReport(
    bytes: 0,
    itemCount: 0,
  );
}

String mcpOpsItemKey(McpOpsExposureSurface surface, String itemId) {
  return '${surface.storageValue}:${itemId.trim()}';
}

String mcpOpsEndpointKey(McpOpsExposureSurface surface, String endpointId) {
  return '${surface.storageValue}:${endpointId.trim()}';
}

String mcpOpsClipAuditText(Object? value) {
  final text = value is Map || value is List
      ? prettyPrintJson(value)
      : '$value'.trim();
  if (text.length <= mcpOpsAuditPreviewMaxChars) return text;
  return clipTextByCodeUnits(text, mcpOpsAuditPreviewMaxChars);
}

String _normalizeOpsEnumValue(String value) {
  return value.trim().toLowerCase().replaceAll('-', '_');
}

String _normalizeListenHost(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? mcpOpsDefaultListenHost : trimmed;
}

int _normalizePort(int value) {
  return _normalizeInt(
    value,
    min: mcpOpsMinListenPort,
    max: mcpOpsMaxListenPort,
  );
}

int _normalizeInt(int value, {required int min, required int max}) {
  final lower = min <= max ? min : max;
  final upper = min <= max ? max : min;
  return value.clamp(lower, upper).toInt();
}

List<String> _normalizeStringList(
  Iterable<String> values, {
  List<String> fallback = const <String>[],
}) {
  final result = <String>[];
  final seen = <String>{};
  for (final raw in values) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    if (seen.add(value.toLowerCase())) {
      result.add(value);
    }
  }
  return result.isEmpty ? List<String>.from(fallback) : result;
}

Map<String, int> _stringIntMapFromValue(Object? raw) {
  final source = stringKeyedMapFromValue(raw);
  if (source.isEmpty) return const <String, int>{};
  final result = <String, int>{};
  for (final entry in source.entries) {
    final value = nonNegativeIntFromValue(entry.value, fallback: 0);
    addMcpOpsMetricCount(result, entry.key, value);
  }
  return Map<String, int>.unmodifiable(result);
}

void addMcpOpsMetricCount(
  Map<String, int> distribution,
  String key,
  int count,
) {
  if (count <= 0) return;
  var normalized = key.trim();
  if (normalized.isEmpty) normalized = 'unknown';
  if (normalized.length > mcpOpsMetricKeyMaxChars) {
    normalized = clipTextByCodeUnits(
      normalized,
      mcpOpsMetricKeyMaxChars,
      suffix: '',
    );
  }
  final existing = distribution[normalized];
  if (existing != null) {
    distribution[normalized] = existing + count;
    return;
  }
  final entryLimit = distribution.containsKey(mcpOpsMetricOverflowKey)
      ? mcpOpsMaxMetricDistributionKeys
      : mcpOpsMaxMetricDistributionKeys - 1;
  if (normalized == mcpOpsMetricOverflowKey ||
      distribution.length < entryLimit) {
    distribution[normalized] = count;
    return;
  }
  distribution[mcpOpsMetricOverflowKey] =
      (distribution[mcpOpsMetricOverflowKey] ?? 0) + count;
}

Map<String, int> normalizeMcpOpsMetricDistribution(
  Map<String, int> distribution,
) {
  if (distribution.isEmpty) return const <String, int>{};
  final normalized = <String, int>{};
  for (final entry in distribution.entries) {
    addMcpOpsMetricCount(normalized, entry.key, entry.value);
  }
  return Map<String, int>.unmodifiable(normalized);
}
