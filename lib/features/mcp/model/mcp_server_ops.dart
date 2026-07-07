import '../../../shared/util/input_value_parsing.dart';

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

enum McpOpsLifecycleState {
  stopped,
  starting,
  running,
  restarting,
  stopping,
  failed,
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
  final String errorMessage;
  final String requestSummary;
  final String argumentsPreview;
  final String responsePreview;
  final Map<String, Object?> environment;

  int get totalTokens => promptTokens + completionTokens;
  bool get failed => status == 'failed' || status == 'blocked';
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

  bool get isRunning => lifecycle == McpOpsLifecycleState.running;

  Duration get uptime {
    final start = startedAt;
    if (start == null || !isRunning) return Duration.zero;
    final delta = DateTime.now().toUtc().difference(start);
    return delta.isNegative ? Duration.zero : delta;
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
    );
  }
}

String mcpOpsItemKey(McpOpsExposureSurface surface, String itemId) {
  return '${surface.storageValue}:${itemId.trim()}';
}

String mcpOpsEndpointKey(McpOpsExposureSurface surface, String endpointId) {
  return '${surface.storageValue}:${endpointId.trim()}';
}

String mcpOpsClipAuditText(Object? value) {
  final text = '$value'.trim();
  if (text.length <= mcpOpsAuditPreviewMaxChars) return text;
  return '${text.substring(0, mcpOpsAuditPreviewMaxChars)}...';
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
